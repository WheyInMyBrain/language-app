use rusqlite::{params, Connection};
use std::path::Path;

/// Embedded DDL from schema.sql
const SCHEMA_SQL: &str = include_str!("schema.sql");

pub fn init_db(db_path: &Path) -> Connection {
    let conn = Connection::open(db_path).expect("Failed to open SQLite database");

    // Configure core operational pragmas before executing tables
    conn.execute_batch(
        "PRAGMA foreign_keys = ON;
         PRAGMA journal_mode = WAL;
         PRAGMA synchronous = NORMAL;
         PRAGMA busy_timeout = 5000;
         PRAGMA wal_autocheckpoint = 1000;",
    )
    .expect("Failed to initialize SQLite pragmas");

    // 1. Execute schema.sql to ensure all relational tables, columns, and indices exist
    conn.execute_batch(SCHEMA_SQL)
        .expect("Failed to execute schema.sql migrations");

    // 2. Ensure push_subscriptions table exists alongside relational tables
    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS push_subscriptions (
             id INTEGER PRIMARY KEY AUTOINCREMENT,
             endpoint TEXT NOT NULL UNIQUE,
             p256dh TEXT NOT NULL,
             auth TEXT NOT NULL,
             created_at TEXT DEFAULT (datetime('now'))
         );
         CREATE INDEX IF NOT EXISTS idx_push_endpoint ON push_subscriptions(endpoint);",
    )
    .expect("Failed to create push_subscriptions table");

    // Run passive checkpoint to flush any stranded WAL log frames to the primary database file
    let _ = conn.execute_batch("PRAGMA wal_checkpoint(PASSIVE);");

    conn
}

pub fn save_push_subscription(
    conn: &Connection,
    endpoint: &str,
    p256dh: &str,
    auth: &str,
) -> Result<(), rusqlite::Error> {
    conn.execute(
        "INSERT INTO push_subscriptions (endpoint, p256dh, auth)
         VALUES (?1, ?2, ?3)
         ON CONFLICT(endpoint) DO UPDATE SET
            p256dh = excluded.p256dh,
            auth = excluded.auth",
        params![endpoint, p256dh, auth],
    )?;
    Ok(())
}

#[allow(dead_code)]
pub fn delete_push_subscription(
    conn: &Connection,
    endpoint: &str,
) -> Result<(), rusqlite::Error> {
    conn.execute(
        "DELETE FROM push_subscriptions WHERE endpoint = ?1",
        params![endpoint],
    )?;
    Ok(())
}

#[allow(dead_code)]
pub fn get_all_push_subscriptions(
    conn: &Connection,
) -> Result<Vec<(String, String, String)>, rusqlite::Error> {
    let mut stmt = conn.prepare("SELECT endpoint, p256dh, auth FROM push_subscriptions")?;
    let rows = stmt.query_map([], |row| {
        Ok((
            row.get::<_, String>(0)?,
            row.get::<_, String>(1)?,
            row.get::<_, String>(2)?,
        ))
    })?;

    let mut list = Vec::new();
    for row in rows.flatten() {
        list.push(row);
    }
    Ok(list)
}