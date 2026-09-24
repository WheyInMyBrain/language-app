pub mod templates;
pub mod scheduler;

pub use templates::{NotificationEvent, NotificationPayload};

use crate::db::save_push_subscription;
use crate::state::AppState;
use axum::{
    extract::State,
    http::StatusCode,
    response::IntoResponse,
    Json,
};
use serde::{Deserialize};
use serde_json::json;
use std::env;
use std::sync::Arc;
use tracing::{error, info, warn};
use web_push::{
    ContentEncoding, IsahcWebPushClient, SubscriptionInfo, VapidSignatureBuilder,
    WebPushClient, WebPushMessageBuilder,
};

#[derive(Deserialize)]
pub struct SubscriptionKeys {
    pub p256dh: String,
    pub auth: String,
}

#[derive(Deserialize)]
pub struct SubscribeRequest {
    pub endpoint: String,
    pub keys: SubscriptionKeys,
}

#[derive(Deserialize)]
pub struct DispatchManualRequest {
    #[serde(flatten)]
    pub event: NotificationEvent,
}

/// GET /api/notifications/vapid-key
pub async fn get_vapid_public_key() -> impl IntoResponse {
    let key = env::var("VAPID_PUBLIC_KEY").unwrap_or_default();
    (StatusCode::OK, Json(json!({ "publicKey": key })))
}

/// POST /api/notifications/subscribe
pub async fn handle_subscribe(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<SubscribeRequest>,
) -> impl IntoResponse {
    let endpoint = payload.endpoint.trim().to_string();
    let p256dh = payload.keys.p256dh.trim().to_string();
    let auth = payload.keys.auth.trim().to_string();

    let db_res = {
        let conn = state.db_conn.lock().unwrap();
        save_push_subscription(&conn, &endpoint, &p256dh, &auth)
    };

    match db_res {
        Ok(_) => {
            info!(target: "push", endpoint = %endpoint, "Device registered for push notifications");
            (StatusCode::CREATED, Json(json!({ "status": "ok", "message": "Subscribed" })))
        }
        Err(e) => {
            error!(target: "push", error = %e, "Failed to save push subscription");
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(json!({ "status": "error", "message": e.to_string() })),
            )
        }
    }
}

/// POST /api/notifications/dispatch
/// Administrative endpoint to trigger typed notifications
pub async fn handle_dispatch(
    State(state): State<Arc<AppState>>,
    Json(body): Json<DispatchManualRequest>,
) -> impl IntoResponse {
    let payload = body.event.into_payload();
    let count = broadcast_push(&state, &payload).await;

    (
        StatusCode::OK,
        Json(json!({
            "status": "ok",
            "delivered_targets": count,
            "title": payload.title,
            "body": payload.body
        })),
    )
}

/// Broadcasts a WebPush notification payload to all stored devices.
/// Prunes dead endpoints (expired tokens, uninstalled apps) automatically.
pub async fn broadcast_push(
    state: &Arc<AppState>,
    payload: &NotificationPayload,
) -> usize {
    let private_key = match env::var("VAPID_PRIVATE_KEY") {
        Ok(k) if !k.is_empty() => k,
        _ => {
            warn!(target: "push", "VAPID_PRIVATE_KEY is unset; skipping push dispatch");
            return 0;
        }
    };

    let subject = env::var("VAPID_SUBJECT").unwrap_or_else(|_| "mailto:admin@example.com".into());

    let subs: Vec<(String, String, String)> = {
        let conn = state.db_conn.lock().unwrap();
        let mut stmt = match conn.prepare("SELECT endpoint, p256dh, auth FROM push_subscriptions") {
            Ok(s) => s,
            Err(_) => return 0,
        };
        let rows = stmt
            .query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)))
            .ok();

        rows.map(|r| r.flatten().collect()).unwrap_or_default()
    };

    if subs.is_empty() {
        info!(target: "push", "No registered devices in SQLite; skipping dispatch");
        return 0;
    }

    let payload_json = match serde_json::to_string(payload) {
        Ok(j) => j,
        Err(_) => return 0,
    };

    let client = match IsahcWebPushClient::new() {
        Ok(c) => c,
        Err(e) => {
            error!(target: "push", error = %e, "Failed to initialize IsahcWebPushClient");
            return 0;
        }
    };

    let mut dead_endpoints = Vec::new();
    let mut success_count = 0;

    for (endpoint, p256dh, auth) in subs {
        let sub_info = SubscriptionInfo::new(endpoint.clone(), p256dh, auth);

        let mut sig_builder = match VapidSignatureBuilder::from_base64(&private_key, &sub_info) {
            Ok(b) => b,
            Err(e) => {
                warn!(target: "push", error = %e, "Failed creating VAPID signature builder");
                continue;
            }
        };
        sig_builder.add_claim("sub", subject.clone());

        let sig = match sig_builder.build() {
            Ok(s) => s,
            Err(e) => {
                warn!(target: "push", error = %e, "Failed signing VAPID claims");
                continue;
            }
        };

        let mut msg_builder = WebPushMessageBuilder::new(&sub_info);
        msg_builder.set_payload(ContentEncoding::Aes128Gcm, payload_json.as_bytes());
        msg_builder.set_vapid_signature(sig);

        let msg = match msg_builder.build() {
            Ok(m) => m,
            Err(e) => {
                warn!(target: "push", error = %e, "Failed building WebPushMessage");
                continue;
            }
        };

        match client.send(msg).await {
            Ok(_) => {
                info!(target: "push", endpoint = %endpoint, "Push notification sent successfully");
                success_count += 1;
            }
            Err(web_push::WebPushError::EndpointNotValid(_))
            | Err(web_push::WebPushError::EndpointNotFound(_)) => {
                info!(target: "push", endpoint = %endpoint, "Unregistered/expired device endpoint; deleting");
                dead_endpoints.push(endpoint);
            }
            Err(e) => warn!(target: "push", endpoint = %endpoint, error = %e, "Failed to send webpush"),
        }
    }

    if !dead_endpoints.is_empty() {
        let conn = state.db_conn.lock().unwrap();
        for ep in dead_endpoints {
            let _ = conn.execute("DELETE FROM push_subscriptions WHERE endpoint = ?1", [ep]);
        }
    }

    success_count
}