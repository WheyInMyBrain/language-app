use rusqlite::{params, Connection};
use serde_json::Value;
use std::collections::HashMap;
use tracing::{error, info};
use yrs::types::ToJson;
use yrs::updates::decoder::Decode;
use yrs::{Array, Doc, Map, ReadTxn, Transact, Update};

fn out_to_serde<T: ReadTxn>(out: &yrs::Out, txn: &T) -> Value {
    let mut buf = String::new();
    out.to_json(txn).to_json(&mut buf);
    serde_json::from_str(&buf).unwrap_or(Value::Null)
}

/// Projects a single Yjs room's binary snapshot directly into the relational tables.
pub fn project_room_to_relational(conn: &Connection, room_name: &str, blob: &[u8]) {
    if blob.is_empty() {
        return;
    }

    let doc = Doc::new();
    if let Ok(update) = Update::decode_v1(blob) {
        let mut txn = doc.transact_mut();
        let _ = txn.apply_update(update);
    } else {
        return;
    }
    let txn = doc.transact();

    // 1. global:metadata
    if room_name == "global:metadata" {
        if let Some(langs_map) = txn.get_map("languages") {
            for (code, val) in langs_map.iter(&txn) {
                let j = out_to_serde(&val, &txn);
                let name = j.get("name").and_then(|v| v.as_str()).unwrap_or(&code);

                let _ = conn.execute(
                    "INSERT INTO languages (code, name) VALUES (?1, ?2)
                     ON CONFLICT(code) DO UPDATE SET name = excluded.name",
                    params![code, name],
                );
            }
        }
        return;
    }

    // 2. Daily sessions: "{lang_code}:{YYYY-MM-DD}"
    if room_name.contains(':')
        && !room_name.starts_with("global:")
        && !room_name.ends_with(":srs")
        && !room_name.ends_with("_index")
    {
        let parts: Vec<&str> = room_name.split(':').collect();
        if parts.len() == 2 && parts[1].len() == 10 {
            let lang_code = parts[0];
            let log_date = parts[1];

            // Ensure language exists
            let _ = conn.execute(
                "INSERT INTO languages (code, name) VALUES (?1, ?2) ON CONFLICT(code) DO NOTHING",
                params![lang_code, lang_code],
            );

            let lang_id: i64 = match conn.query_row(
                "SELECT id FROM languages WHERE code = ?1",
                params![lang_code],
                |r| r.get(0),
            ) {
                Ok(id) => id,
                Err(_) => return,
            };

            // Read session metadata
            let meta_map = txn.get_map("meta");
            let (revision, due_date, ease, interval) = if let Some(meta) = meta_map {
                if let Some(session_val) = meta.get(&txn, "session") {
                    let j = out_to_serde(&session_val, &txn);
                    (
                        j.get("revision").and_then(|v| v.as_i64()).unwrap_or(0),
                        j.get("due_date").and_then(|v| v.as_str()).map(|s| s.to_string()),
                        j.get("ease").and_then(|v| v.as_f64()).unwrap_or(2.50),
                        j.get("interval").and_then(|v| v.as_i64()).unwrap_or(0),
                    )
                } else {
                    (0, None, 2.50, 0)
                }
            } else {
                (0, None, 2.50, 0)
            };

            let _ = conn.execute(
                "INSERT INTO daily_logs (language_id, log_date, due_date, ease, interval)
                 VALUES (?1, ?2, ?3, ?4, ?5)
                 ON CONFLICT(language_id, log_date) DO UPDATE SET
                    due_date = excluded.due_date,
                    ease = excluded.ease,
                    interval = excluded.interval",
                params![lang_id, log_date, due_date, ease, interval],
            );

            let log_id: i64 = match conn.query_row(
                "SELECT id FROM daily_logs WHERE language_id = ?1 AND log_date = ?2",
                params![lang_id, log_date],
                |r| r.get(0),
            ) {
                Ok(id) => id,
                Err(_) => return,
            };

            // Words
            if let Some(words_array) = txn.get_array("words") {
                for item in words_array.iter(&txn) {
                    let j = out_to_serde(&item, &txn);
                    let list = j.as_array().cloned().unwrap_or_else(|| vec![j]);
                    for w in list {
                        let word_idx = w.get("word_index").and_then(|v| v.as_i64()).unwrap_or(1);
                        let native = w.get("native_script").and_then(|v| v.as_str()).unwrap_or("");
                        let pron = w.get("pronunciation").and_then(|v| v.as_str()).unwrap_or("");
                        let link = w.get("link").and_then(|v| v.as_str());
                        let audio_dur = w.get("audio_duration").and_then(|v| v.as_i64());

                        if !native.is_empty() || !pron.is_empty() {
                            let _ = conn.execute(
                                "INSERT INTO words (language_id, log_id, word_index, native_script, pronunciation, link, audio_duration)
                                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
                                params![lang_id, log_id, word_idx, native, pron, link, audio_dur],
                            );
                        }
                    }
                }
            }

            // Activities
            if let Some(act_array) = txn.get_array("activities") {
                for item in act_array.iter(&txn) {
                    let j = out_to_serde(&item, &txn);
                    let list = j.as_array().cloned().unwrap_or_else(|| vec![j]);
                    for act in list {
                        let act_type = act.get("activity_type").and_then(|v| v.as_str()).unwrap_or("unknown");
                        let item_idx = act.get("item_index").and_then(|v| v.as_i64()).unwrap_or(1);
                        let link = act.get("link").and_then(|v| v.as_str());
                        let link_dur = act.get("link_duration").and_then(|v| v.as_i64());
                        let audio_dur = act.get("audio_duration").and_then(|v| v.as_i64());
                        let meta_str = act.get("metadata").map(|m| m.to_string());

                        let _ = conn.execute(
                            "INSERT INTO activities (language_id, log_id, activity_type, item_index, link, link_duration, audio_duration, metadata)
                             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
                            params![lang_id, log_id, act_type, item_idx, link, link_dur, audio_dur, meta_str],
                        );
                    }
                }
            }
        }
    }
}