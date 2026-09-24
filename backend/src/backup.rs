use chrono::{Datelike, Duration, Local, NaiveDate};
use flate2::write::GzEncoder;
use flate2::Compression;
use rusqlite::{params, Connection};
use serde_json::Value;
use std::collections::{HashMap, HashSet};
use std::fs::{self, File};
use std::io::{copy, BufReader};
use std::path::{Path, PathBuf};
use tracing::{error, info, warn};
use yrs::types::ToJson;
use yrs::updates::decoder::Decode;
use yrs::{Array, Doc, Map, ReadTxn, Transact, Update};

// Compile-time inclusion of clean, external SQL schema
const SCHEMA: &str = include_str!("schema.sql");

/// Helper: converts yrs::Out -> yrs::Any -> serde_json::Value
fn out_to_serde<T: ReadTxn>(out: &yrs::Out, txn: &T) -> Value {
    let mut buf = String::new();
    out.to_json(txn).to_json(&mut buf);
    serde_json::from_str(&buf).unwrap_or(Value::Null)
}

pub fn execute_atomic_backup(
    live_db_path: &Path,
    backups_dir: &Path,
) -> Result<PathBuf, Box<dyn std::error::Error + Send + Sync>> {
    let now = Local::now();
    let date_str = now.format("%Y-%m-%d").to_string();

    let tmp_db_path = backups_dir.join(format!("backup_{}.db.tmp", date_str));
    let final_gz_path = backups_dir.join(format!("backup_{}.db.gz", date_str));

    if tmp_db_path.exists() {
        let _ = fs::remove_file(&tmp_db_path);
    }

    info!(
        target: "backup",
        live_db = ?live_db_path,
        tmp_db = ?tmp_db_path,
        "Projecting live Yjs state into temporary relational DB"
    );

    // 1. Build and project into temporary SQLite database
    {
        let live_conn = Connection::open(live_db_path)?;
        let mut target_conn = Connection::open(&tmp_db_path)?;

        target_conn.execute_batch(SCHEMA)?;

        project_yjs_to_relational(&live_conn, &mut target_conn)?;

        // 2. Run PRAGMA quick_check
        let check_result: String =
            target_conn.query_row("PRAGMA quick_check;", [], |r| r.get(0))?;

        if check_result.to_lowercase() != "ok" {
            let _ = fs::remove_file(&tmp_db_path);
            error!(target: "backup", result = %check_result, "SQLite integrity check failed");
            return Err(format!("SQLite integrity quick_check failed: {}", check_result).into());
        }
    }

    // 3. Compress to .db.gz
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

    // Atomic rename & temp cleanup
    fs::rename(&tmp_gz_path, &final_gz_path)?;
    let _ = fs::remove_file(&tmp_db_path);

    info!(target: "backup", snapshot = ?final_gz_path, "Verified relational backup created");

    // 4. Prune older backups
    prune_old_backups(backups_dir);

    Ok(final_gz_path)
}

fn project_yjs_to_relational(
    live_conn: &Connection,
    target_conn: &mut Connection,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let mut stmt = live_conn.prepare("SELECT room_name, blob FROM yjs_sync_rooms")?;
    let rows = stmt.query_map([], |row| {
        Ok((row.get::<_, String>(0)?, row.get::<_, Vec<u8>>(1)?))
    })?;

    let tx = target_conn.transaction()?;

    let mut room_cache: Vec<(String, Vec<u8>)> = Vec::new();
    for row in rows {
        let (room, blob) = row?;
        if !blob.is_empty() {
            room_cache.push((room, blob));
        }
    }

    let mut lang_id_map: HashMap<String, i64> = HashMap::new();

    // Pass 1: Languages from global:metadata
    for (room_name, blob) in &room_cache {
        if room_name == "global:metadata" {
            let doc = Doc::new();
            if let Ok(update) = Update::decode_v1(blob) {
                let mut txn = doc.transact_mut();
                let _ = txn.apply_update(update);
            }
            let txn = doc.transact();

            if let Some(langs_map) = txn.get_map("languages") {
                for (code, val) in langs_map.iter(&txn) {
                    let j = out_to_serde(&val, &txn);
                    let name = j.get("name").and_then(|v| v.as_str()).unwrap_or(&code);

                    tx.execute(
                        "INSERT INTO languages (code, name) VALUES (?1, ?2)
                         ON CONFLICT(code) DO UPDATE SET name = excluded.name",
                        params![code, name],
                    )?;
                }
            }
        }
    }

    // Cache language primary keys
    {
        let mut get_langs = tx.prepare("SELECT id, code FROM languages")?;
        let l_rows = get_langs.query_map([], |r| Ok((r.get::<_, i64>(0)?, r.get::<_, String>(1)?)))?;
        for r in l_rows {
            let (id, code) = r?;
            lang_id_map.insert(code, id);
        }
    }

    // Pass 2: Daily log sessions ('{lang_code}:{YYYY-MM-DD}')
    for (room_name, blob) in &room_cache {
        if !room_name.contains(':')
            || room_name.starts_with("global:")
            || room_name.ends_with(":srs")
            || room_name.ends_with("_index")
        {
            continue;
        }

        let parts: Vec<&str> = room_name.split(':').collect();
        if parts.len() != 2 || parts[1].len() != 10 {
            continue;
        }

        let lang_code = parts[0];
        let log_date = parts[1];

        let lang_id = *lang_id_map.entry(lang_code.to_string()).or_insert_with(|| {
            tx.execute(
                "INSERT INTO languages (code, name) VALUES (?1, ?2) ON CONFLICT(code) DO NOTHING",
                params![lang_code, lang_code],
            ).ok();
            tx.query_row("SELECT id FROM languages WHERE code = ?1", params![lang_code], |r| r.get(0)).unwrap_or(1)
        });

        let doc = Doc::new();
        if let Ok(update) = Update::decode_v1(blob) {
            let mut txn = doc.transact_mut();
            let _ = txn.apply_update(update);
        }
        let txn = doc.transact();

        let meta_map = txn.get_map("meta");
        let (revision, due_date, ease, interval) = if let Some(meta) = meta_map {
            if let Some(session_val) = meta.get(&txn, "session") {
                let j = out_to_serde(&session_val, &txn);
                (
                    j.get("revision").and_then(|v| v.as_i64()).unwrap_or(0),
                    j.get("due_date").and_then(|v| v.as_str()).map(|s| s.to_string()),
                    j.get("ease").and_then(|v| v.as_f64()).unwrap_or(2.50),
                    j.get("interval").and_then(|v| v.as_i64()).unwrap_or(0),
                )
            } else {
                (0, None, 2.50, 0)
            }
        } else {
            (0, None, 2.50, 0)
        };

        tx.execute(
            "INSERT INTO daily_logs (language_id, log_date, due_date, ease, interval)
             VALUES (?1, ?2, ?3, ?4, ?5)
             ON CONFLICT(language_id, log_date) DO UPDATE SET
                due_date = excluded.due_date,
                ease = excluded.ease,
                interval = excluded.interval",
            params![lang_id, log_date, due_date, ease, interval],
        )?;

        let log_id: i64 = tx.query_row(
            "SELECT id FROM daily_logs WHERE language_id = ?1 AND log_date = ?2",
            params![lang_id, log_date],
            |r| r.get(0),
        )?;

        tx.execute(
            "INSERT INTO log_revisions (language_id, log_id, revision_number, revision_date)
             VALUES (?1, ?2, ?3, ?4)",
            params![lang_id, log_id, revision, log_date],
        )?;

        // Activities
        if let Some(act_array) = txn.get_array("activities") {
            for item in act_array.iter(&txn) {
                let j = out_to_serde(&item, &txn);
                let list = j.as_array().cloned().unwrap_or_else(|| vec![j]);
                for act in list {
                    let act_type = act.get("activity_type").and_then(|v| v.as_str()).unwrap_or("unknown");
                    let item_idx = act.get("item_index").and_then(|v| v.as_i64()).unwrap_or(1);
                    let link = act.get("link").and_then(|v| v.as_str());
                    let link_dur = act.get("link_duration").and_then(|v| v.as_i64());
                    let audio_dur = act.get("audio_duration").and_then(|v| v.as_i64());
                    let meta_str = act.get("metadata").map(|m| m.to_string());

                    tx.execute(
                        "INSERT INTO activities (language_id, log_id, activity_type, item_index, link, link_duration, audio_duration, metadata)
                         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
                        params![lang_id, log_id, act_type, item_idx, link, link_dur, audio_dur, meta_str],
                    )?;
                }
            }
        }

        // Words
        if let Some(words_array) = txn.get_array("words") {
            for item in words_array.iter(&txn) {
                let j = out_to_serde(&item, &txn);
                let list = j.as_array().cloned().unwrap_or_else(|| vec![j]);
                for w in list {
                    let word_idx = w.get("word_index").and_then(|v| v.as_i64()).unwrap_or(1);
                    let native = w.get("native_script").and_then(|v| v.as_str()).unwrap_or("");
                    let pron = w.get("pronunciation").and_then(|v| v.as_str()).unwrap_or("");
                    let link = w.get("link").and_then(|v| v.as_str());
                    let audio_dur = w.get("audio_duration").and_then(|v| v.as_i64());

                    if !native.is_empty() || !pron.is_empty() {
                        tx.execute(
                            "INSERT INTO words (language_id, log_id, word_index, native_script, pronunciation, link, audio_duration)
                             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
                            params![lang_id, log_id, word_idx, native, pron, link, audio_dur],
                        )?;
                    }
                }
            }
        }
    }

    // Pass 3: SRS entries
    for (room_name, blob) in &room_cache {
        if !room_name.ends_with(":srs") {
            continue;
        }

        let lang_code = room_name.trim_end_matches(":srs");
        let lang_id = match lang_id_map.get(lang_code) {
            Some(id) => *id,
            None => continue,
        };

        let doc = Doc::new();
        if let Ok(update) = Update::decode_v1(blob) {
            let mut txn = doc.transact_mut();
            let _ = txn.apply_update(update);
        }
        let txn = doc.transact();

        if let Some(queue) = txn.get_map("queue") {
            for (_, val) in queue.iter(&txn) {
                let j = out_to_serde(&val, &txn);
                let card_type = j.get("card_type").and_then(|v| v.as_str()).unwrap_or("");
                let due_date = j.get("due_date").and_then(|v| v.as_str()).unwrap_or("");
                let interval = j.get("interval").and_then(|v| v.as_i64()).unwrap_or(0);
                let ease = j.get("ease").and_then(|v| v.as_f64()).unwrap_or(2.50);
                let native = j.get("native").and_then(|v| v.as_str()).unwrap_or("");
                let source_date = j.get("source_date").and_then(|v| v.as_str()).unwrap_or("");

                if native.is_empty() || source_date.is_empty() {
                    continue;
                }

                let word_info: Option<(i64, i64)> = tx.query_row(
                    "SELECT w.id, w.log_id 
                     FROM words w 
                     JOIN daily_logs d ON w.log_id = d.id 
                     WHERE w.language_id = ?1 AND d.log_date = ?2 AND w.native_script = ?3
                     LIMIT 1",
                    params![lang_id, source_date, native],
                    |r| Ok((r.get(0)?, r.get(1)?)),
                ).ok();

                if let Some((word_id, log_id)) = word_info {
                    tx.execute(
                        "INSERT INTO word_srs (language_id, log_id, word_id, card_type, due_date, interval, ease)
                         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
                         ON CONFLICT(word_id, card_type) DO UPDATE SET
                            due_date = excluded.due_date,
                            interval = excluded.interval,
                            ease = excluded.ease",
                        params![lang_id, log_id, word_id, card_type, due_date, interval, ease],
                    )?;
                }
            }
        }
    }

    tx.commit()?;
    Ok(())
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