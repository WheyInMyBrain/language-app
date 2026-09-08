use crate::db::{load_blob_for_room, save_blob_for_room};
use crate::state::{AppState, Room};
use axum::{
    body::Bytes,
    extract::{
        ws::{Message as WsMessage, WebSocket, WebSocketUpgrade},
        Path, State,
    },
    response::IntoResponse,
};
use futures_util::{SinkExt, StreamExt};
use std::sync::Arc;
use tokio::sync::{broadcast, RwLock};
use yrs::sync::{Message as SyncMessage, SyncMessage as YrsSync};
use yrs::updates::decoder::Decode;
use yrs::updates::encoder::Encode;
use yrs::{Doc, ReadTxn, StateVector, Transact, Update};

async fn get_or_create_room(state: &Arc<AppState>, room_name: &str) -> Arc<Room> {
    // Fast path: Read lock
    {
        let rooms = state.rooms.read().await;
        if let Some(room) = rooms.get(room_name) {
            return room.clone();
        }
    }

    // Slow path: Write lock
    let mut rooms = state.rooms.write().await;
    if let Some(room) = rooms.get(room_name) {
        return room.clone();
    }

    let doc = Doc::new();

    // Hydrate doc from stored SQLite blob via spawn_blocking
    let state_db = state.clone();
    let name_owned = room_name.to_string();
    let blob_opt = tokio::task::spawn_blocking(move || {
        let conn = state_db.db_conn.lock().unwrap();
        load_blob_for_room(&conn, &name_owned)
    })
    .await
    .unwrap_or(None);

    if let Some(blob) = blob_opt {
        if let Ok(update) = Update::decode_v1(&blob) {
            let mut txn = doc.transact_mut();
            let _ = txn.apply_update(update);
            println!("[ROOM HYDRATED] Loaded blob for '{}'", room_name);
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

pub async fn handle_ws_upgrade(
    Path(room_name): Path<String>,
    State(state): State<Arc<AppState>>,
    ws: WebSocketUpgrade,
) -> impl IntoResponse {
    ws.on_upgrade(move |socket| handle_ws_connection(socket, room_name, state))
}

async fn handle_ws_connection(socket: WebSocket, room_name: String, state: Arc<AppState>) {
    let room = get_or_create_room(&state, &room_name).await;
    let (mut ws_sender, mut ws_receiver) = socket.split();

    // 1. Initial Sync Step 1: Send local StateVector to connecting client
    {
        let doc = room.doc.read().await;
        let txn = doc.transact();
        let sv = txn.state_vector();
        let step1 = SyncMessage::Sync(YrsSync::SyncStep1(sv)).encode_v1();
        let _ = ws_sender.send(WsMessage::Binary(Bytes::from(step1))).await;
    }

    let mut sub = room.bcast.subscribe();

    // 2. Broadcast Task: Forward room updates from other peers
    let mut send_task = tokio::spawn(async move {
        while let Ok(msg) = sub.recv().await {
            if ws_sender.send(WsMessage::Binary(msg)).await.is_err() {
                break;
            }
        }
    });

    // 3. Receive Task: Handle incoming binary messages from this client
    let state_clone = state.clone();
    let room_clone = room.clone();
    let room_name_clone = room_name.clone();

    let mut recv_task = tokio::spawn(async move {
        while let Some(Ok(msg)) = ws_receiver.next().await {
            if let WsMessage::Binary(data) = msg {
                if let Ok(sync_msg) = SyncMessage::decode_v1(&data) {
                    match sync_msg {
                        // Client sent StateVector (Step 1) -> Reply with diff (Step 2)
                        SyncMessage::Sync(YrsSync::SyncStep1(sv)) => {
                            let doc = room_clone.doc.read().await;
                            let txn = doc.transact();
                            let update = txn.encode_diff_v1(&sv);
                            let step2 = SyncMessage::Sync(YrsSync::SyncStep2(update)).encode_v1();
                            let _ = room_clone.bcast.send(Bytes::from(step2));
                        }

                        // Client sent mutations (Step 2 or incremental Update)
                        SyncMessage::Sync(YrsSync::SyncStep2(update_data))
                        | SyncMessage::Sync(YrsSync::Update(update_data)) => {
                            if let Ok(update) = Update::decode_v1(&update_data) {
                                {
                                    let doc = room_clone.doc.write().await;
                                    let mut txn = doc.transact_mut();
                                    let _ = txn.apply_update(update);
                                }

                                // Broadcast to other peers using zero-copy Bytes
                                let update_msg =
                                    SyncMessage::Sync(YrsSync::Update(update_data)).encode_v1();
                                let _ = room_clone.bcast.send(Bytes::from(update_msg));

                                // Encode full document state vector diff
                                let current_blob = {
                                    let doc = room_clone.doc.read().await;
                                    let txn = doc.transact();
                                    txn.encode_diff_v1(&StateVector::default())
                                };

                                // Offload SQLite persistence to a blocking thread
                                let st = state_clone.clone();
                                let rn = room_name_clone.clone();
                                tokio::task::spawn_blocking(move || {
                                    let conn = st.db_conn.lock().unwrap();
                                    save_blob_for_room(&conn, &rn, &current_blob);
                                });
                            }
                        }

                        // Awareness (presence/cursors)
                        SyncMessage::Awareness(awareness_update) => {
                            let echo_msg = SyncMessage::Awareness(awareness_update).encode_v1();
                            let _ = room_clone.bcast.send(Bytes::from(echo_msg));
                        }

                        _ => {}
                    }
                }
            }
        }
    });

    tokio::select! {
        _ = (&mut send_task) => recv_task.abort(),
        _ = (&mut recv_task) => send_task.abort(),
    };

    println!("[WS DISCONNECTED] Room: {}", room_name);

    // Evict room from RAM if no active WebSocket clients remain
    if room.bcast.receiver_count() == 0 {
        let mut rooms = state.rooms.write().await;
        if let Some(r) = rooms.get(&room_name) {
            if r.bcast.receiver_count() == 0 {
                rooms.remove(&room_name);
                println!("[ROOM EVICTED FROM RAM] '{}'", room_name);
            }
        }
    }
}