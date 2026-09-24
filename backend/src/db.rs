use rusqlite::{params, Connection};
use std::path::Path;

pub fn init_db(db_path: &Path) -> Connection {
    let conn = Connection::open(db_path).expect("Failed to open SQLite database");
    conn.execute_batch(
        "PRAGMA foreign_keys = ON;
         PRAGMA journal_mode = WAL;
         PRAGMA synchronous = NORMAL;
         PRAGMA busy_timeout = 5000;
         PRAGMA mmap_size = 268435456;

         CREATE TABLE IF NOT EXISTS yjs_sync_rooms (
             room_name TEXT PRIMARY KEY,
             blob BLOB NOT NULL
         );

         CREATE TABLE IF NOT EXISTS push_subscriptions (
             id INTEGER PRIMARY KEY AUTOINCREMENT,
             endpoint TEXT NOT NULL UNIQUE,
             p256dh TEXT NOT NULL,
             auth TEXT NOT NULL,
             created_at TEXT DEFAULT (datetime('now'))
         );",
    )
    .expect("Failed to configure SQLite PRAGMAs");
    conn
}

pub fn load_blob_for_room(conn: &Connection, room_name: &str) -> Option<Vec<u8>> {
    let mut stmt = conn
        .prepare("SELECT blob FROM yjs_sync_rooms WHERE room_name = ? LIMIT 1")
        .ok()?;
    stmt.query_row([room_name], |row| row.get::<_, Vec<u8>>(0)).ok()
}

pub fn save_blob_for_room(conn: &Connection, room_name: &str, blob: &[u8]) {
    let _ = conn.execute(
        "INSERT INTO yjs_sync_rooms (room_name, blob) VALUES (?, ?)
         ON CONFLICT(room_name) DO UPDATE SET blob = excluded.blob",
        params![room_name, blob],
    );
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