mod db;
mod handlers;
mod state;

use axum::{
    http::Method,
    routing::{get, post},
    Router,
};
use std::{
    collections::HashMap,
    path::PathBuf,
    sync::{Arc, Mutex},
};
use tokio::fs;
use tower_http::cors::CorsLayer;
use tower_http::services::ServeDir;

use handlers::{audio, ws};
use state::AppState;

#[tokio::main]
async fn main() {
    let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let project_root = manifest_dir
        .parent()
        .map(|p| p.to_path_buf())
        .unwrap_or(manifest_dir);

    let storage_root = project_root.join("storage");
    let db_dir = storage_root.join("database");
    let audio_root = storage_root.join("audio");

    fs::create_dir_all(&db_dir)
        .await
        .expect("Failed to initialize storage/database directory");
    fs::create_dir_all(&audio_root)
        .await
        .expect("Failed to initialize storage/audio directory");

    let db_path = db_dir.join("language_database.db");

    // Copy initial DB from backend/src if missing in storage/database
    let initial_db = project_root
        .join("backend")
        .join("src")
        .join("language_database.db");

    if !db_path.exists() && initial_db.exists() {
        fs::copy(&initial_db, &db_path)
            .await
            .expect("Failed to migrate initial database into storage/database");
        println!("📦 Migrated database into storage: {:?}", db_path);
    }

    let conn = db::init_db(&db_path);

    let state = Arc::new(AppState {
        audio_root: audio_root.clone(),
        db_path,
        rooms: tokio::sync::RwLock::new(HashMap::new()),
        db_conn: Mutex::new(conn),
    });

    let cors = CorsLayer::new()
        .allow_origin(tower_http::cors::Any)
        .allow_methods([Method::GET, Method::POST, Method::OPTIONS])
        .allow_headers(tower_http::cors::Any);

    let app = Router::new()
        .route("/ping", get(audio::handle_ping))
        .route("/ws/{room_name}", get(ws::handle_ws_upgrade))
        .route(
            "/api/audio/{lang}/{date}/{category}/{index}",
            post(audio::handle_audio_upload),
        )
        .nest_service("/audio", ServeDir::new(&audio_root))
        .layer(cors)
        .with_state(state);

    let listener = tokio::net::TcpListener::bind("0.0.0.0:8080")
        .await
        .unwrap();

    println!("⚡ Language App Server: http://0.0.0.0:8080");
    println!("⚡ Database: {:?}", db_dir.join("language_database.db"));
    println!("⚡ Audio Root: {:?}", audio_root);
    println!("⚡ WebSocket Sync: ws://0.0.0.0:8080/ws/{{room_name}}");

    axum::serve(listener, app).await.unwrap();
}