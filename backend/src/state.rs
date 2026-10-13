use rusqlite::Connection;
use serde::Serialize;
use std::{
    collections::HashMap,
    path::PathBuf,
    sync::{Arc, Mutex},
};
use tokio::sync::broadcast;

pub struct AppState {
    pub audio_root: PathBuf,
    pub db_path: PathBuf,
    pub db_conn: Mutex<Connection>,
    pub lexicon_conns: Mutex<HashMap<String, Arc<Mutex<Connection>>>>,
    // Channel broadcasting invalidation notifications (e.g. language code)
    pub sync_tx: broadcast::Sender<String>,
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
    pub fn get_lexicon_conn(&self, lang: &str) -> Option<Arc<Mutex<Connection>>> {
        let mut conns = self.lexicon_conns.lock().unwrap();

        if let Some(conn) = conns.get(lang) {
            return Some(conn.clone());
        }

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