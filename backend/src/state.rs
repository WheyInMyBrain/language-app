use axum::body::Bytes;
use rusqlite::Connection;
use serde::Serialize;
use std::{
    collections::HashMap,
    path::PathBuf,
    sync::{Arc, Mutex},
};
use tokio::sync::{broadcast, RwLock};
use yrs::Doc;

pub struct Room {
    pub doc: Arc<RwLock<Doc>>,
    pub bcast: broadcast::Sender<Bytes>,
}

pub struct AppState {
    pub audio_root: PathBuf,
    pub db_path: PathBuf,
    pub rooms: RwLock<HashMap<String, Arc<Room>>>,
    pub db_conn: Mutex<Connection>,
    pub lexicon_conns: Mutex<HashMap<String, Arc<Mutex<Connection>>>>,
}

#[derive(Serialize)]
pub struct PingResponse {
    pub status: &'static str,
    pub timestamp: u64,
    pub storage_ready: bool,
    pub db_ready: bool,
}

#[derive(Serialize)]
pub struct UploadResponse {
    pub status: &'static str,
    pub relative_path: String,
    pub bytes_written: usize,
}

impl AppState {
    /// Retrieves or lazily opens a read-only SQLite database for any language code
    pub fn get_lexicon_conn(&self, lang: &str) -> Option<Arc<Mutex<Connection>>> {
        let mut conns = self.lexicon_conns.lock().unwrap();

        if let Some(conn) = conns.get(lang) {
            return Some(conn.clone());
        }

        // Resolves storage/database/lexicons/{lang}.db relative to db_path
        let lexicons_dir = self.db_path.parent()?.join("lexicons");
        let target_db_path = lexicons_dir.join(format!("{}.db", lang));

        if !target_db_path.exists() {
            return None;
        }

        let conn = Connection::open_with_flags(
            &target_db_path,
            rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY | rusqlite::OpenFlags::SQLITE_OPEN_NO_MUTEX,
        )
        .ok()?;

        let _ = conn.execute_batch("PRAGMA query_only = ON; PRAGMA mmap_size = 67108864;");

        let arc_conn = Arc::new(Mutex::new(conn));
        conns.insert(lang.to_string(), arc_conn.clone());
        Some(arc_conn)
    }
}