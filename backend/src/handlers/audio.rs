use crate::state::{AppState, PingResponse, UploadResponse};
use axum::{
    body::Bytes,
    extract::{Path, State},
    http::StatusCode,
    response::{IntoResponse, Json, Response},
};
use std::sync::Arc;
use tokio::{fs, io::AsyncWriteExt};
use tracing::{error, info, warn};

pub async fn handle_ping(State(state): State<Arc<AppState>>) -> Response {
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();

    let storage_ready = fs::metadata(&state.audio_root).await.is_ok();
    let db_ready = state.db_path.exists();

    if !storage_ready {
        warn!(target: "audio", path = ?state.audio_root, "Audio storage path not accessible");
    }
    if !db_ready {
        warn!(target: "audio", path = ?state.db_path, "Database path does not exist");
    }

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
        error!(
            target: "audio",
            dir = ?target_dir,
            error = %e,
            "Failed to create target audio directories"
        );
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
            error!(
                target: "audio",
                path = ?file_path,
                error = %e,
                "Failed to create destination audio file"
            );
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
        error!(
            target: "audio",
            path = ?file_path,
            error = %e,
            "Failed to write audio payload to disk"
        );
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
    info!(
        target: "audio",
        path = %relative_path,
        bytes = bytes_len,
        "Audio file saved successfully"
    );

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