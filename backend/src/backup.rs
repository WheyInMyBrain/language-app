use chrono::{Datelike, Duration, Local, NaiveDate};
use flate2::write::GzEncoder;
use flate2::Compression;
use rusqlite::Connection;
use std::collections::HashSet;
use std::fs::{self, File};
use std::io::{copy, BufReader};
use std::path::{Path, PathBuf};
use tracing::{error, info, warn};

pub fn execute_atomic_backup(
    live_db_path: &Path,
    backups_dir: &Path,
) -> Result<PathBuf, Box<dyn std::error::Error + Send + Sync>> {
    let now = Local::now();
    let date_str = now.format("%Y-%m-%d").to_string();

    fs::create_dir_all(backups_dir)?;

    let tmp_db_path = backups_dir.join(format!("backup_{}.db.tmp", date_str));
    let final_gz_path = backups_dir.join(format!("backup_{}.db.gz", date_str));

    if tmp_db_path.exists() {
        let _ = fs::remove_file(&tmp_db_path);
    }

    info!(
        target: "backup",
        live_db = ?live_db_path,
        tmp_db = ?tmp_db_path,
        "Initiating online SQLite transactional backup"
    );

    // 1. Snapshot the live SQLite database using the Online Backup API
    {
        let live_conn = Connection::open(live_db_path)?;
        let mut target_conn = Connection::open(&tmp_db_path)?;

        // Ensure WAL checkpoints do not stall
        live_conn.execute_batch("PRAGMA busy_timeout = 5000;")?;
        target_conn.execute_batch("PRAGMA busy_timeout = 5000;")?;

        {
            let backup = rusqlite::backup::Backup::new(&live_conn, &mut target_conn)?;
            backup.run_to_completion(50, std::time::Duration::from_millis(50), None)?;
        }

        // 2. Run PRAGMA quick_check to verify snapshot integrity
        let check_result: String =
            target_conn.query_row("PRAGMA quick_check;", [], |r| r.get(0))?;

        if check_result.to_lowercase() != "ok" {
            let _ = fs::remove_file(&tmp_db_path);
            error!(target: "backup", result = %check_result, "Snapshot integrity verification failed");
            return Err(format!("SQLite integrity quick_check failed: {}", check_result).into());
        }
    }

    // 3. Compress snapshot with Gzip
    info!(target: "backup", destination = ?final_gz_path, "Compressing snapshot with gzip");
    let tmp_gz_path = backups_dir.join(format!("backup_{}.db.gz.tmp", date_str));
    {
        let input_file = File::open(&tmp_db_path)?;
        let mut reader = BufReader::new(input_file);

        let output_file = File::create(&tmp_gz_path)?;
        let mut encoder = GzEncoder::new(output_file, Compression::best());
        copy(&mut reader, &mut encoder)?;
        encoder.finish()?;
    }

    // 4. Atomic rename and cleanup of uncompressed temporary DB
    fs::rename(&tmp_gz_path, &final_gz_path)?;
    let _ = fs::remove_file(&tmp_db_path);

    info!(target: "backup", snapshot = ?final_gz_path, "Verified relational backup complete");

    // 5. Prune expired backups according to retention policy
    prune_old_backups(backups_dir);

    Ok(final_gz_path)
}

fn prune_old_backups(backups_dir: &Path) {
    let entries = match fs::read_dir(backups_dir) {
        Ok(e) => e,
        Err(e) => {
            warn!(target: "backup", error = %e, "Could not open backups directory for pruning");
            return;
        }
    };

    let today = Local::now().date_naive();
    let cutoff_daily = today - Duration::days(14);
    let cutoff_weekly = today - Duration::days(60);

    let mut kept_weeks: HashSet<(i32, u32)> = HashSet::new();
    let mut kept_months: HashSet<(i32, u32)> = HashSet::new();
    let mut file_dates: Vec<(NaiveDate, PathBuf)> = Vec::new();

    for entry in entries.flatten() {
        let path = entry.path();
        if let Some(file_name) = path.file_name().and_then(|f| f.to_str()) {
            if file_name.starts_with("backup_") && file_name.ends_with(".db.gz") {
                let date_part = file_name
                    .trim_start_matches("backup_")
                    .trim_end_matches(".db.gz");
                if let Ok(d) = NaiveDate::parse_from_str(date_part, "%Y-%m-%d") {
                    file_dates.push((d, path));
                }
            }
        }
    }

    // Process from newest to oldest
    file_dates.sort_by(|a, b| b.0.cmp(&a.0));

    for (d, path) in file_dates {
        let keep = if d >= cutoff_daily {
            true
        } else if d >= cutoff_weekly {
            let week_key = (d.year(), d.iso_week().week());
            kept_weeks.insert(week_key)
        } else {
            let month_key = (d.year(), d.month());
            kept_months.insert(month_key)
        };

        if !keep {
            info!(target: "backup", file = ?path.file_name().unwrap_or_default(), "Pruning expired snapshot");
            let _ = fs::remove_file(path);
        }
    }
}