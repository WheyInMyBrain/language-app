mod backup;
mod db;
mod handlers;
mod notifications;
mod state;

use axum::{
    http::{Method, StatusCode},
    routing::{get, post},
    Json, Router,
};
use chrono::{Duration as ChronoDuration, Local, NaiveTime};
use serde_json::json;
use std::{
    collections::HashMap,
    env,
    path::PathBuf,
    sync::{Arc, Mutex},
    time::Duration as StdDuration,
};
use tokio::fs;
use tower_http::cors::CorsLayer;
use tower_http::services::ServeDir;
use tracing::{error, info};
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt, EnvFilter};

use handlers::{audio, ws};
use state::AppState;

#[tokio::main]
async fn main() {
    dotenvy::dotenv().ok();

    // 1. Initialize structured logging
    tracing_subscriber::registry()
        .with(
            EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "info,tower_http=info,axum=info".into()),
        )
        .with(tracing_subscriber::fmt::layer().compact())
        .init();

    // 2. Storage setup
    let storage_dir = env::var("STORAGE_DIR").unwrap_or_else(|_| "./storage".to_string());
    let storage_root = PathBuf::from(storage_dir);

    let db_dir = storage_root.join("database");
    let audio_root = storage_root.join("audio");
    let backups_dir = storage_root.join("backups");

    fs::create_dir_all(&db_dir)
        .await
        .expect("Failed to initialize storage/database directory");
    fs::create_dir_all(&audio_root)
        .await
        .expect("Failed to initialize storage/audio directory");
    fs::create_dir_all(&backups_dir)
        .await
        .expect("Failed to initialize storage/backups directory");

    let live_db_path = db_dir.join("language_database.db");
    let conn = db::init_db(&live_db_path);

    let state = Arc::new(AppState {
        audio_root: audio_root.clone(),
        db_path: live_db_path.clone(),
        rooms: tokio::sync::RwLock::new(HashMap::new()),
        db_conn: Mutex::new(conn),
    });

    // 3. Background Notification Scheduler (Checks for due SRS cards and streak nudges)
    notifications::scheduler::start_notification_worker(state.clone());

    // 4. Background Nightly Backup Scheduler (03:00 AM Local Time)
    let live_db_for_cron = live_db_path.clone();
    let backups_dir_for_cron = backups_dir.clone();

    tokio::spawn(async move {
        loop {
            let now = Local::now();
            let target_time = NaiveTime::from_hms_opt(3, 0, 0).unwrap();
            let mut target_datetime = now
                .date_naive()
                .and_time(target_time)
                .and_local_timezone(Local)
                .unwrap();

            if now >= target_datetime {
                target_datetime += ChronoDuration::days(1);
            }

            let wait_duration = (target_datetime - now)
                .to_std()
                .unwrap_or(StdDuration::from_secs(3600));

            info!(
                target: "scheduler",
                next_run = %target_datetime.format("%Y-%m-%d %H:%M:%S"),
                wait_minutes = wait_duration.as_secs() / 60,
                "Backup scheduler initialized"
            );

            tokio::time::sleep(wait_duration).await;

            let live = live_db_for_cron.clone();
            let backups = backups_dir_for_cron.clone();

            let res = tokio::task::spawn_blocking(move || {
                backup::execute_atomic_backup(&live, &backups)
            })
            .await;

            match res {
                Ok(Ok(path)) => info!(target: "scheduler", path = ?path, "Nightly backup succeeded"),
                Ok(Err(e)) => error!(target: "scheduler", error = %e, "Nightly backup execution error"),
                Err(e) => error!(target: "scheduler", error = %e, "Background task join error"),
            }
        }
    });

    // 5. Manual Backup Handler
    let live_db_for_api = live_db_path.clone();
    let backups_dir_for_api = backups_dir.clone();

    let trigger_backup = move || {
        let live = live_db_for_api.clone();
        let backups = backups_dir_for_api.clone();
        async move {
            let res = tokio::task::spawn_blocking(move || {
                backup::execute_atomic_backup(&live, &backups)
            })
            .await;

            match res {
                Ok(Ok(path)) => (
                    StatusCode::OK,
                    Json(json!({
                        "status": "ok",
                        "message": "Atomic backup created and pruned successfully",
                        "file": path.file_name().and_then(|f| f.to_str()).unwrap_or("")
                    })),
                ),
                Ok(Err(e)) => {
                    error!(target: "api", error = %e, "Manual backup failed");
                    (
                        StatusCode::INTERNAL_SERVER_ERROR,
                        Json(json!({"status": "error", "message": e.to_string()})),
                    )
                }
                Err(e) => {
                    error!(target: "api", error = %e, "Manual backup thread join error");
                    (
                        StatusCode::INTERNAL_SERVER_ERROR,
                        Json(json!({"status": "error", "message": e.to_string()})),
                    )
                }
            }
        }
    };

    // 6. CORS Layer
    let cors = CorsLayer::new()
        .allow_origin(tower_http::cors::Any)
        .allow_methods([Method::GET, Method::POST, Method::OPTIONS])
        .allow_headers(tower_http::cors::Any);

    // 7. Router Setup
    let app = Router::new()
        .route("/ping", get(audio::handle_ping))
        .route("/api/ping", get(audio::handle_ping))
        .route("/api/backup/now", post(move || trigger_backup()))
        .route("/ws/{room_name}", get(ws::handle_ws_upgrade))
        .route(
            "/api/notifications/vapid-key",
            get(notifications::get_vapid_public_key),
        )
        .route(
            "/api/notifications/subscribe",
            post(notifications::handle_subscribe),
        )
        .route(
            "/api/notifications/dispatch",
            post(notifications::handle_dispatch),
        )
        .route(
            "/api/audio/{lang}/{date}/{category}/{index}",
            post(audio::handle_audio_upload),
        )
        .nest_service("/audio", ServeDir::new(&audio_root))
        .layer(cors)
        .with_state(state);

    // 8. Bind & Serve
    let port = env::var("PORT").unwrap_or_else(|_| "3000".to_string());
    let bind_addr = format!("0.0.0.0:{}", port);

    let listener = tokio::net::TcpListener::bind(&bind_addr)
        .await
        .unwrap_or_else(|err| panic!("Failed to bind to {}: {}", bind_addr, err));

    info!(target: "server", bind = %bind_addr, "Language App Server running");
    info!(target: "server", live_db = ?live_db_path, "SQLite live storage mounted");
    info!(target: "server", audio_root = ?audio_root, "Audio storage mounted");
    info!(target: "server", backups_dir = ?backups_dir, "Backups directory active");

    if let Err(e) = axum::serve(listener, app).await {
        error!(target: "server", error = %e, "Server crashed");
    }
}