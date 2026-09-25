use crate::db::{load_blob_for_room, save_blob_for_room};
use crate::state::{AppState, Room};
use axum::{
    body::Bytes,
    extract::{
        ws::{Message as WsMessage, WebSocket, WebSocketUpgrade},
        State,
    },
    response::IntoResponse,
};
use futures_util::{SinkExt, StreamExt};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::{broadcast, mpsc, RwLock};
use tracing::{debug, error, info};
use yrs::sync::{Message as SyncMessage, SyncMessage as YrsSync};
use yrs::updates::decoder::Decode;
use yrs::updates::encoder::Encode;
use yrs::{Doc, ReadTxn, StateVector, Transact, Update};

// Frame Header Types
const MSG_SUBSCRIBE: u8 = 0x01;
const MSG_UNSUBSCRIBE: u8 = 0x02;
const MSG_PAYLOAD: u8 = 0x03;

async fn get_or_create_room(state: &Arc<AppState>, room_name: &str) -> Arc<Room> {
    {
        let rooms = state.rooms.read().await;
        if let Some(room) = rooms.get(room_name) {
            return room.clone();
        }
    }

    let mut rooms = state.rooms.write().await;
    if let Some(room) = rooms.get(room_name) {
        return room.clone();
    }

    let doc = Doc::new();
    let state_db = state.clone();
    let name_owned = room_name.to_string();

    let blob_opt = tokio::task::spawn_blocking(move || {
        let conn = state_db.db_conn.lock().unwrap();
        load_blob_for_room(&conn, &name_owned)
    })
    .await
    .unwrap_or_else(|e| {
        error!(target: "ws", room = %room_name, error = %e, "Failed blocking task during hydration");
        None
    });

    if let Some(blob) = blob_opt {
        if let Ok(update) = Update::decode_v1(&blob) {
            let mut txn = doc.transact_mut();
            let _ = txn.apply_update(update);
            info!(target: "ws", room = %room_name, bytes = blob.len(), "Hydrated room from SQLite");
        }
    }

    let (bcast, _) = broadcast::channel::<Bytes>(1024);
    let room = Arc::new(Room {
        doc: Arc::new(RwLock::new(doc)),
        bcast,
    });

    rooms.insert(room_name.to_string(), room.clone());
    room
}

/// Helper to pack a room-tagged binary frame: [0x03][u16 len][room_name][data]
fn encode_room_frame(room_name: &str, data: &[u8]) -> Vec<u8> {
    let name_bytes = room_name.as_bytes();
    let name_len = name_bytes.len() as u16;
    let mut out = Vec::with_capacity(1 + 2 + name_bytes.len() + data.len());
    out.push(MSG_PAYLOAD);
    out.extend_from_slice(&name_len.to_be_bytes());
    out.extend_from_slice(name_bytes);
    out.extend_from_slice(data);
    out
}

/// Helper to parse incoming frame: returns (flag, room_name, remainder)
fn decode_room_frame(buf: &[u8]) -> Option<(u8, String, &[u8])> {
    if buf.len() < 3 {
        return None;
    }
    let flag = buf[0];
    let name_len = u16::from_be_bytes([buf[1], buf[2]]) as usize;
    if buf.len() < 3 + name_len {
        return None;
    }
    let room_name = std::str::from_utf8(&buf[3..3 + name_len]).ok()?.to_string();
    let payload = &buf[3 + name_len..];
    Some((flag, room_name, payload))
}

pub async fn handle_ws_upgrade(
    State(state): State<Arc<AppState>>,
    ws: WebSocketUpgrade,
) -> impl IntoResponse {
    ws.on_upgrade(move |socket| handle_multiplexed_connection(socket, state))
}

async fn handle_multiplexed_connection(socket: WebSocket, state: Arc<AppState>) {
    info!(target: "ws", "Multiplexed WebSocket connected");
    let (mut ws_sender, mut ws_receiver) = socket.split();

    // Outbound channel to funnel all messages into the single ws_sender
    let (tx_out, mut rx_out) = mpsc::channel::<Bytes>(1024);

    // Sender worker task
    let send_task = tokio::spawn(async move {
        while let Some(msg) = rx_out.recv().await {
            if let Err(e) = ws_sender.send(WsMessage::Binary(msg)).await {
                debug!(target: "ws", error = %e, "WebSocket sender pipe broken");
                break;
            }
        }
    });

    // Map of active subscriptions for THIS client: room_name -> broadcast join handle
    let mut active_subscriptions: HashMap<String, tokio::task::JoinHandle<()>> = HashMap::new();

    // Receiver worker loop
    let state_clone = state.clone();
    let tx_out_clone = tx_out.clone();

    while let Some(msg_res) = ws_receiver.next().await {
        let raw_bytes = match msg_res {
            Ok(WsMessage::Binary(b)) => b,
            Ok(WsMessage::Close(_)) => break,
            _ => continue,
        };

        let (flag, room_name, payload) = match decode_room_frame(&raw_bytes) {
            Some(parsed) => parsed,
            None => continue,
        };

        match flag {
            // SUBSCRIBE TO ROOM
            MSG_SUBSCRIBE => {
                if active_subscriptions.contains_key(&room_name) {
                    continue;
                }

                let room = get_or_create_room(&state_clone, &room_name).await;
                let mut bcast_rx = room.bcast.subscribe();
                let tx_out_sub = tx_out_clone.clone();
                let r_name_sub = room_name.clone();

                // 1. Initial Sync Step 1 to client
                {
                    let doc = room.doc.read().await;
                    let txn = doc.transact();
                    let sv = txn.state_vector();
                    let step1 = SyncMessage::Sync(YrsSync::SyncStep1(sv)).encode_v1();
                    let frame = encode_room_frame(&r_name_sub, &step1);
                    let _ = tx_out_sub.send(Bytes::from(frame)).await;
                }

                // 2. Spawn listener forwarding room's broadcasts through multiplexed frame
                let sub_task = tokio::spawn(async move {
                    while let Ok(msg) = bcast_rx.recv().await {
                        let frame = encode_room_frame(&r_name_sub, &msg);
                        if tx_out_sub.send(Bytes::from(frame)).await.is_err() {
                            break;
                        }
                    }
                });

                active_subscriptions.insert(room_name, sub_task);
            }

            // UNSUBSCRIBE FROM ROOM
            MSG_UNSUBSCRIBE => {
                if let Some(task) = active_subscriptions.remove(&room_name) {
                    task.abort();
                    // Evict from state if zero receivers remain
                    check_and_evict_room(&state_clone, &room_name).await;
                }
            }

            // INCOMING YJS SYNC PAYLOAD
            MSG_PAYLOAD => {
                let room = get_or_create_room(&state_clone, &room_name).await;
                let room_clone = room.clone();
                let st = state_clone.clone();
                let rn = room_name.clone();

                if let Ok(sync_msg) = SyncMessage::decode_v1(payload) {
                    match sync_msg {
                        SyncMessage::Sync(YrsSync::SyncStep1(sv)) => {
                            let doc = room_clone.doc.read().await;
                            let txn = doc.transact();
                            let update = txn.encode_diff_v1(&sv);
                            let step2 = SyncMessage::Sync(YrsSync::SyncStep2(update)).encode_v1();
                            let _ = room_clone.bcast.send(Bytes::from(step2));
                        }
                        SyncMessage::Sync(YrsSync::SyncStep2(update_data))
                        | SyncMessage::Sync(YrsSync::Update(update_data)) => {
                            if let Ok(update) = Update::decode_v1(&update_data) {
                                {
                                    let doc = room_clone.doc.write().await;
                                    let mut txn = doc.transact_mut();
                                    let _ = txn.apply_update(update);
                                }

                                let update_msg =
                                    SyncMessage::Sync(YrsSync::Update(update_data)).encode_v1();
                                let _ = room_clone.bcast.send(Bytes::from(update_msg));

                                let current_blob = {
                                    let doc = room_clone.doc.read().await;
                                    let txn = doc.transact();
                                    txn.encode_diff_v1(&StateVector::default())
                                };

                                tokio::task::spawn_blocking(move || {
                                    let conn = st.db_conn.lock().unwrap();
                                    save_blob_for_room(&conn, &rn, &current_blob);
                                });
                            }
                        }
                        SyncMessage::Awareness(awareness_update) => {
                            let echo_msg = SyncMessage::Awareness(awareness_update).encode_v1();
                            let _ = room_clone.bcast.send(Bytes::from(echo_msg));
                        }
                        _ => {}
                    }
                }
            }
            _ => {}
        }
    }

    send_task.abort();

    // Clean up all client subscriptions and evict unused rooms from RAM
    for (room_name, task) in active_subscriptions {
        task.abort();
        check_and_evict_room(&state, &room_name).await;
    }

    info!(target: "ws", "Multiplexed WebSocket disconnected");
}

async fn check_and_evict_room(state: &Arc<AppState>, room_name: &str) {
    let mut rooms = state.rooms.write().await;
    if let Some(r) = rooms.get(room_name) {
        if r.bcast.receiver_count() == 0 {
            rooms.remove(room_name);
            info!(target: "ws", room = %room_name, "Zero active subscribers; evicted room from RAM");
        }
    }
}