use crate::state::{AppState, PingResponse, UploadResponse};
use axum::{
    body::Bytes,
    extract::{Path, State},
    http::StatusCode,
    response::{IntoResponse, Json, Response},
};
use std::sync::Arc;
use tokio::{fs, io::AsyncWriteExt};

pub async fn handle_ping(State(state): State<Arc<AppState>>) -> Response {
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();

    let storage_ready = fs::metadata(&state.audio_root).await.is_ok();
    let db_ready = state.db_path.exists();

    (
        StatusCode::OK,
        Json(PingResponse {
            status: "ok",
            timestamp: now,
            storage_ready,
            db_ready,
        }),
    )
        .into_response()
}

pub async fn handle_audio_upload(
    Path((lang, date, category, index)): Path<(String, String, String, String)>,
    State(state): State<Arc<AppState>>,
    body: Bytes,
) -> Response {
    let safe_lang = lang.trim().replace(['/', '\\', '.'], "");
    let safe_date = date.trim().replace(['/', '\\', '.'], "");
    let safe_category = category.trim().replace(['/', '\\', '.'], "");
    let clean_index = index.trim().replace(['/', '\\', '.'], "");
    let safe_filename = format!("{}.webm", clean_index.strip_suffix(".webm").unwrap_or(&clean_index));

    let target_dir = state
        .audio_root
        .join(&safe_lang)
        .join(&safe_date)
        .join(&safe_category);

    if let Err(e) = fs::create_dir_all(&target_dir).await {
        eprintln!("[AUDIO ERROR] Failed to create directories: {:?}", e);
        return (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(UploadResponse {
                status: "failed",
                relative_path: "".to_string(),
                bytes_written: 0,
            }),
        )
            .into_response();
    }

    let file_path = target_dir.join(&safe_filename);
    let bytes_len = body.len();

    let mut file = match fs::File::create(&file_path).await {
        Ok(f) => f,
        Err(e) => {
            eprintln!("[AUDIO ERROR] Failed to create file: {:?}", e);
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(UploadResponse {
                    status: "failed",
                    relative_path: "".to_string(),
                    bytes_written: 0,
                }),
            )
                .into_response();
        }
    };

    if let Err(e) = file.write_all(&body).await {
        eprintln!("[AUDIO ERROR] Failed to write file body: {:?}", e);
        return (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(UploadResponse {
                status: "failed",
                relative_path: "".to_string(),
                bytes_written: 0,
            }),
        )
            .into_response();
    }

    let relative_path = format!("{}/{}/{}/{}", safe_lang, safe_date, safe_category, safe_filename);
    println!("[AUDIO SAVED] {} ({} bytes)", relative_path, bytes_len);

    (
        StatusCode::CREATED,
        Json(UploadResponse {
            status: "success",
            relative_path,
            bytes_written: bytes_len,
        }),
    )
        .into_response()
}