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