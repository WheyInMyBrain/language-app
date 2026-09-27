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
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use tokio::sync::{broadcast, mpsc, RwLock};
use tracing::{debug, error, info};
use yrs::updates::decoder::Decode;
use yrs::updates::encoder::Encode;
use yrs::{Doc, ReadTxn, StateVector, Transact, Update};

// Monotonic ID counter for assigning unique client connection IDs
static CLIENT_COUNTER: AtomicU64 = AtomicU64::new(1);

// Top-level multiplexer flags
const MSG_SUBSCRIBE: u8 = 0x01;
const MSG_UNSUBSCRIBE: u8 = 0x02;
const MSG_PAYLOAD: u8 = 0x03;

// y-protocols/sync message sub-types
const YJS_SYNC_STEP_1: u8 = 0;
const YJS_SYNC_STEP_2: u8 = 1;
const YJS_UPDATE: u8 = 2;

/// Writes a variable-length unsigned integer (lib0 / yjs format)
fn write_var_uint(buf: &mut Vec<u8>, mut num: u64) {
    while num >= 0x80 {
        buf.push(((num & 0x7F) | 0x80) as u8);
        num >>= 7;
    }
    buf.push((num & 0x7F) as u8);
}

/// Reads a variable-length unsigned integer from a byte slice, advancing the slice
fn read_var_uint(buf: &mut &[u8]) -> Option<u64> {
    let mut result: u64 = 0;
    let mut shift: u32 = 0;

    while !buf.is_empty() {
        let byte = buf[0];
        *buf = &buf[1..];
        result |= ((byte & 0x7F) as u64) << shift;
        if (byte & 0x80) == 0 {
            return Some(result);
        }
        shift += 7;
        if shift > 63 {
            return None;
        }
    }
    None
}

/// Writes a length-prefixed buffer (lib0 writeVarUint8Array format)
fn write_var_uint8_array(buf: &mut Vec<u8>, bytes: &[u8]) {
    write_var_uint(buf, bytes.len() as u64);
    buf.extend_from_slice(bytes);
}

/// Encodes SyncStep1 matching y-protocols: [0][varuint length][sv_bytes]
fn encode_sync_step_1(sv: &StateVector) -> Vec<u8> {
    let sv_bytes = sv.encode_v1();
    let mut out = Vec::with_capacity(1 + 5 + sv_bytes.len());
    out.push(YJS_SYNC_STEP_1);
    write_var_uint8_array(&mut out, &sv_bytes);
    out
}

/// Encodes SyncStep2 matching y-protocols: [1][varuint length][update_bytes]
fn encode_sync_step_2(update: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(1 + 5 + update.len());
    out.push(YJS_SYNC_STEP_2);
    write_var_uint8_array(&mut out, update);
    out
}

/// Encodes Update matching y-protocols: [2][varuint length][update_bytes]
fn encode_sync_update(update: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(1 + 5 + update.len());
    out.push(YJS_UPDATE);
    write_var_uint8_array(&mut out, update);
    out
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

/// Helper to parse incoming multiplexed frame: returns (flag, room_name, payload)
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

    // Broadcast tuple: (origin_client_id, encoded_data)
    let (bcast, _) = broadcast::channel::<(u64, Bytes)>(1024);
    let room = Arc::new(Room {
        doc: Arc::new(RwLock::new(doc)),
        bcast,
    });

    rooms.insert(room_name.to_string(), room.clone());
    room
}

pub async fn handle_ws_upgrade(
    State(state): State<Arc<AppState>>,
    ws: WebSocketUpgrade,
) -> impl IntoResponse {
    ws.on_upgrade(move |socket| handle_multiplexed_connection(socket, state))
}

async fn handle_multiplexed_connection(socket: WebSocket, state: Arc<AppState>) {
    let client_id = CLIENT_COUNTER.fetch_add(1, Ordering::Relaxed);
    info!(target: "ws", client_id = %client_id, "Multiplexed WebSocket connected");

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

                // 1. Initial Sync Step 1 sent directly to the new subscriber
                {
                    let doc = room.doc.read().await;
                    let txn = doc.transact();
                    let sv = txn.state_vector();
                    let step1_payload = encode_sync_step_1(&sv);
                    let frame = encode_room_frame(&r_name_sub, &step1_payload);
                    let _ = tx_out_sub.send(Bytes::from(frame)).await;
                }

                // 2. Forward updates to this client, skipping messages originated by this client
                let sub_task = tokio::spawn(async move {
                    while let Ok((sender_id, msg)) = bcast_rx.recv().await {
                        if sender_id == client_id {
                            continue; // Skip echoing back to originator
                        }
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
                    check_and_evict_room(&state_clone, &room_name).await;
                }
            }

            // INCOMING YJS SYNC PAYLOAD
            MSG_PAYLOAD => {
                if payload.is_empty() {
                    continue;
                }

                let room = get_or_create_room(&state_clone, &room_name).await;
                let room_clone = room.clone();
                let st = state_clone.clone();
                let rn = room_name.clone();
                let tx_out_reply = tx_out_clone.clone();

                let sync_type = payload[0];
                let mut rest = &payload[1..];

                if let Some(len) = read_var_uint(&mut rest) {
                    let len = len as usize;
                    if rest.len() >= len {
                        let inner_data = &rest[..len];

                        match sync_type {
                            // Client sent SyncStep1 -> Reply with SyncStep2 directly to client
                            YJS_SYNC_STEP_1 => {
                                if let Ok(sv) = StateVector::decode_v1(inner_data) {
                                    let doc = room_clone.doc.read().await;
                                    let txn = doc.transact();
                                    let diff = txn.encode_diff_v1(&sv);
                                    let step2_payload = encode_sync_step_2(&diff);
                                    let frame = encode_room_frame(&rn, &step2_payload);
                                    let _ = tx_out_reply.send(Bytes::from(frame)).await;
                                }
                            }

                            // Client sent SyncStep2 or Update -> Apply to server doc and broadcast
                            YJS_SYNC_STEP_2 | YJS_UPDATE => {
                                if let Ok(update) = Update::decode_v1(inner_data) {
                                    {
                                        let doc = room_clone.doc.write().await;
                                        let mut txn = doc.transact_mut();
                                        let _ = txn.apply_update(update);
                                    }

                                    // Broadcast update to all other subscribers of this room
                                    let bcast_payload = encode_sync_update(inner_data);
                                    let _ = room_clone.bcast.send((client_id, Bytes::from(bcast_payload)));

                                    // Persist current state blob to SQLite
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
                            _ => {}
                        }
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

    info!(target: "ws", client_id = %client_id, "Multiplexed WebSocket disconnected");
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