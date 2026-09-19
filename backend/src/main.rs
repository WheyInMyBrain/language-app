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
    env,
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
    // 1. Storage directory from env (fallback: "./storage")
    let storage_dir = env::var("STORAGE_DIR").unwrap_or_else(|_| "./storage".to_string());
    let storage_root = PathBuf::from(storage_dir);

    let db_dir = storage_root.join("database");
    let audio_root = storage_root.join("audio");

    fs::create_dir_all(&db_dir)
        .await
        .expect("Failed to initialize storage/database directory");
    fs::create_dir_all(&audio_root)
        .await
        .expect("Failed to initialize storage/audio directory");

    let db_path = db_dir.join("language_database.db");
    let conn = db::init_db(&db_path);

    let state = Arc::new(AppState {
        audio_root: audio_root.clone(),
        db_path: db_path.clone(),
        rooms: tokio::sync::RwLock::new(HashMap::new()),
        db_conn: Mutex::new(conn),
    });

    let cors = CorsLayer::new()
        .allow_origin(tower_http::cors::Any)
        .allow_methods([Method::GET, Method::POST, Method::OPTIONS])
        .allow_headers(tower_http::cors::Any);

    let app = Router::new()
        .route("/ping", get(audio::handle_ping))
        .route("/api/ping", get(audio::handle_ping))

        // WebSocket protocol
        .route("/ws/{room_name}", get(ws::handle_ws_upgrade))

        // Audio upload endpoint
        .route(
            "/api/audio/{lang}/{date}/{category}/{index}",
            post(audio::handle_audio_upload),
        )

        // Static audio file streaming
        .nest_service("/audio", ServeDir::new(&audio_root))
        .layer(cors)
        .with_state(state);

    // 2. Port from env (fallback: "3000")
    let port = env::var("PORT").unwrap_or_else(|_| "3000".to_string());
    let bind_addr = format!("0.0.0.0:{}", port);

    let listener = tokio::net::TcpListener::bind(&bind_addr)
        .await
        .unwrap_or_else(|err| panic!("Failed to bind to {}: {}", bind_addr, err));

    println!("⚡ Language App Server: http://{}", bind_addr);
    println!("⚡ Database: {:?}", db_path);
    println!("⚡ Audio Root: {:?}", audio_root);
    println!("⚡ WebSocket Sync: ws://{}/ws/{{room_name}}", bind_addr);

    axum::serve(listener, app).await.unwrap();
}