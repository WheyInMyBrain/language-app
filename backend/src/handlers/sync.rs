use axum::{
    extract::{Query, State},
    http::StatusCode,
    response::{
        sse::{Event, KeepAlive, Sse},
        IntoResponse,
    },
    Json,
};
use chrono::Utc;
use futures_util::stream::Stream;
use rusqlite::{params, Connection, Transaction};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::{convert::Infallible, sync::Arc, time::Duration};
use tokio_stream::wrappers::BroadcastStream;
use tokio_stream::StreamExt;
use tracing::{error, warn};

use crate::state::AppState;

#[derive(Deserialize)]
pub struct PullQuery {
    pub lang: Option<String>,
    pub since: Option<i64>,
}

#[derive(Serialize)]
pub struct PullResponse {
    pub server_time: i64,
    pub languages: Vec<Value>,
    pub daily_logs: Vec<Value>,
    pub words: Vec<Value>,
    pub activities: Vec<Value>,
    pub word_srs: Vec<Value>,
}

#[derive(Deserialize)]
pub struct MutationItem {
    pub table: String,
    #[allow(dead_code)]
    pub key: String,
    pub data: Value,
}

#[derive(Deserialize)]
pub struct PushRequest {
    pub mutations: Vec<MutationItem>,
}

/// Helper function to safely parse integer fields from numbers or strings
fn extract_i64(v: &Value) -> i64 {
    v.as_i64()
        .or_else(|| v.as_f64().map(|f| f as i64))
        .or_else(|| v.as_str().and_then(|s| s.parse::<i64>().ok()))
        .unwrap_or(0)
}

/// Helper function to safely parse floating point fields from numbers or strings
fn extract_f64(v: &Value) -> f64 {
    v.as_f64()
        .or_else(|| v.as_i64().map(|i| i as f64))
        .or_else(|| v.as_str().and_then(|s| s.parse::<f64>().ok()))
        .unwrap_or(0.0)
}

/// Helper function to safely extract non-null string slices with a default fallback
fn extract_str<'a>(v: &'a Value, default: &'a str) -> &'a str {
    v.as_str().unwrap_or(default)
}

/// Helper function to safely extract optional string slices
fn extract_opt_str<'a>(v: &'a Value) -> Option<&'a str> {
    v.as_str().filter(|s| !s.is_empty())
}

/// Safely extracts and normalizes JSON strings without accidental double-escaping
fn extract_json_str(data: &Value, primary_key: &str, alt_key: &str, default: &str) -> String {
    if let Some(v) = data.get(primary_key).or_else(|| data.get(alt_key)) {
        match v {
            Value::String(s) => {
                let trimmed = s.trim();
                if trimmed.starts_with('{') || trimmed.starts_with('[') {
                    s.clone()
                } else if trimmed.is_empty() {
                    default.to_string()
                } else {
                    format!("\"{}\"", s)
                }
            }
            Value::Object(_) | Value::Array(_) => v.to_string(),
            Value::Null => default.to_string(),
            _ => v.to_string(),
        }
    } else {
        default.to_string()
    }
}

/// GET /api/sync/pull?lang=zh-CN&since=1710000000000
pub async fn handle_pull(
    State(state): State<Arc<AppState>>,
    Query(q): Query<PullQuery>,
) -> Result<Json<PullResponse>, (StatusCode, String)> {
    let since = q.since.unwrap_or(0);
    let lang = q.lang.unwrap_or_default();
    let now = Utc::now().timestamp_millis();

    let conn = state.db_conn.lock().unwrap();

    // 1. Languages (Includes colors_json and tones_json)
    let languages = fetch_table_deltas(
        &conn,
        "SELECT code, name, goals_json, milestones_json, momentum_json, colors_json, tones_json, \
                current_streak, longest_streak, total_days, updated_at, deleted_at \
         FROM languages WHERE (code = ?1 OR ?1 = '') AND updated_at > ?2",
        &lang,
        since,
        |row| {
            let goals: Value = row.get::<_, Option<String>>(2)?
                .and_then(|s| serde_json::from_str(&s).ok())
                .unwrap_or_else(|| serde_json::json!({}));
            let milestones: Value = row.get::<_, Option<String>>(3)?
                .and_then(|s| serde_json::from_str(&s).ok())
                .unwrap_or_else(|| serde_json::json!({}));
            let momentum: Value = row.get::<_, Option<String>>(4)?
                .and_then(|s| serde_json::from_str(&s).ok())
                .unwrap_or_else(|| serde_json::json!({}));
            let colors: Value = row.get::<_, Option<String>>(5)?
                .and_then(|s| serde_json::from_str(&s).ok())
                .unwrap_or_else(|| serde_json::json!({}));
            let tones: Value = row.get::<_, Option<String>>(6)?
                .and_then(|s| serde_json::from_str(&s).ok())
                .unwrap_or_else(|| serde_json::json!({}));

            Ok(serde_json::json!({
                "code": row.get::<_, String>(0)?,
                "name": row.get::<_, String>(1)?,
                "goals": goals,
                "milestones": milestones,
                "momentum": momentum,
                "colors": colors,
                "tones": tones,
                "current_streak": row.get::<_, Option<i64>>(7)?.unwrap_or(0),
                "longest_streak": row.get::<_, Option<i64>>(8)?.unwrap_or(0),
                "total_days": row.get::<_, Option<i64>>(9)?.unwrap_or(0),
                "updated_at": row.get::<_, i64>(10)?,
                "deleted_at": row.get::<_, Option<i64>>(11)?,
            }))
        },
    )?;

    // 2. Daily Logs (Using Option<T> for optional database fields)
    let daily_logs = fetch_table_deltas(
        &conn,
        "SELECT id, lang_code, log_date, due_date, ease, interval, revision, \
                word, ci, grammar, listening, speaking_time, listening_time, \
                vocab_done, ci_done, listening_done, speaking_done, grammar_done, \
                srs_vision_done, srs_listen_done, srs_write_done, revisions_done, \
                unvoiced_words_json, unvoiced_ci_json, unvoiced_listening_json, unvoiced_grammar_json, \
                updated_at, deleted_at \
         FROM daily_logs WHERE (lang_code = ?1 OR ?1 = '') AND updated_at > ?2",
        &lang,
        since,
        |row| {
            let unvoiced_words: Value = row.get::<_, Option<String>>(22)?
                .and_then(|s| serde_json::from_str(&s).ok())
                .unwrap_or_else(|| serde_json::json!([]));
            let unvoiced_ci: Value = row.get::<_, Option<String>>(23)?
                .and_then(|s| serde_json::from_str(&s).ok())
                .unwrap_or_else(|| serde_json::json!([]));
            let unvoiced_listening: Value = row.get::<_, Option<String>>(24)?
                .and_then(|s| serde_json::from_str(&s).ok())
                .unwrap_or_else(|| serde_json::json!([]));
            let unvoiced_grammar: Value = row.get::<_, Option<String>>(25)?
                .and_then(|s| serde_json::from_str(&s).ok())
                .unwrap_or_else(|| serde_json::json!([]));

            let srs_vision = row.get::<_, Option<i64>>(18)?.unwrap_or(0);
            let srs_listen = row.get::<_, Option<i64>>(19)?.unwrap_or(0);
            let srs_write = row.get::<_, Option<i64>>(20)?.unwrap_or(0);
            let day_revs = row.get::<_, Option<i64>>(21)?.unwrap_or(0);

            Ok(serde_json::json!({
                "id": row.get::<_, String>(0)?,
                "lang_code": row.get::<_, String>(1)?,
                "log_date": row.get::<_, String>(2)?,
                "date": row.get::<_, String>(2)?,
                "due_date": row.get::<_, Option<String>>(3)?,
                "ease": row.get::<_, Option<f64>>(4)?.unwrap_or(2.50),
                "interval": row.get::<_, Option<i64>>(5)?.unwrap_or(0),
                "revision": row.get::<_, Option<i64>>(6)?.unwrap_or(0),
                "word": row.get::<_, Option<i64>>(7)?.unwrap_or(0),
                "ci": row.get::<_, Option<i64>>(8)?.unwrap_or(0),
                "grammar": row.get::<_, Option<i64>>(9)?.unwrap_or(0),
                "listening": row.get::<_, Option<i64>>(10)?.unwrap_or(0),
                "speaking_time": row.get::<_, Option<f64>>(11)?.unwrap_or(0.0),
                "listening_time": row.get::<_, Option<f64>>(12)?.unwrap_or(0.0),
                "vocab_done": row.get::<_, Option<i64>>(13)?.unwrap_or(0),
                "ci_done": row.get::<_, Option<i64>>(14)?.unwrap_or(0),
                "listening_done": row.get::<_, Option<i64>>(15)?.unwrap_or(0),
                "speaking_done": row.get::<_, Option<i64>>(16)?.unwrap_or(0),
                "grammar_done": row.get::<_, Option<i64>>(17)?.unwrap_or(0),
                "srs_vision_done": srs_vision,
                "srs_listen_done": srs_listen,
                "srs_write_done": srs_write,
                "revisions_done": day_revs,
                "reviews_completed": {
                    "srs_vision": srs_vision,
                    "srs_listen": srs_listen,
                    "srs_write": srs_write,
                    "day_revisions": day_revs
                },
                "unvoiced_words_indices": unvoiced_words,
                "unvoiced_ci_indices": unvoiced_ci,
                "unvoiced_listening_indices": unvoiced_listening,
                "unvoiced_grammar_indices": unvoiced_grammar,
                "updated_at": row.get::<_, i64>(26)?,
                "deleted_at": row.get::<_, Option<i64>>(27)?,
            }))
        },
    )?;

    // 3. Words
    let words = fetch_table_deltas(
        &conn,
        "SELECT id, lang_code, log_date, word_index, native_script, pronunciation, \
                link, audio_duration, updated_at, deleted_at \
         FROM words WHERE (lang_code = ?1 OR ?1 = '') AND updated_at > ?2",
        &lang,
        since,
        |row| {
            Ok(serde_json::json!({
                "id": row.get::<_, String>(0)?,
                "lang_code": row.get::<_, String>(1)?,
                "log_date": row.get::<_, String>(2)?,
                "word_index": row.get::<_, Option<i64>>(3)?.unwrap_or(1),
                "native_script": row.get::<_, String>(4)?,
                "pronunciation": row.get::<_, String>(5)?,
                "link": row.get::<_, Option<String>>(6)?,
                "audio_duration": row.get::<_, Option<f64>>(7)?.unwrap_or(0.0),
                "updated_at": row.get::<_, i64>(8)?,
                "deleted_at": row.get::<_, Option<i64>>(9)?,
            }))
        },
    )?;

    // 4. Activities
    let activities = fetch_table_deltas(
        &conn,
        "SELECT id, lang_code, log_date, activity_type, item_index, link, \
                link_duration, audio_duration, metadata_json, updated_at, deleted_at \
         FROM activities WHERE (lang_code = ?1 OR ?1 = '') AND updated_at > ?2",
        &lang,
        since,
        |row| {
            let meta_raw = row.get::<_, Option<String>>(8)?.unwrap_or_else(|| "{}".to_string());
            let meta: Value = serde_json::from_str(&meta_raw).unwrap_or_else(|_| serde_json::json!({}));
            Ok(serde_json::json!({
                "id": row.get::<_, String>(0)?,
                "lang_code": row.get::<_, String>(1)?,
                "log_date": row.get::<_, String>(2)?,
                "activity_type": row.get::<_, String>(3)?,
                "item_index": row.get::<_, Option<i64>>(4)?.unwrap_or(1),
                "link": row.get::<_, Option<String>>(5)?,
                "link_duration": row.get::<_, Option<f64>>(6)?.unwrap_or(0.0),
                "durationSec": row.get::<_, Option<f64>>(6)?.unwrap_or(0.0),
                "audio_duration": row.get::<_, Option<f64>>(7)?.unwrap_or(0.0),
                "metadata": meta,
                "metadata_json": meta_raw,
                "updated_at": row.get::<_, i64>(9)?,
                "deleted_at": row.get::<_, Option<i64>>(10)?,
            }))
        },
    )?;

    // 5. Word SRS
    let word_srs = fetch_table_deltas(
        &conn,
        "SELECT card_key, lang_code, word_id, card_type, native_script, pronunciation, \
                due_date, interval, ease, reps, lapses, last_reviewed, updated_at, deleted_at \
         FROM word_srs WHERE (lang_code = ?1 OR ?1 = '') AND updated_at > ?2",
        &lang,
        since,
        |row| {
            Ok(serde_json::json!({
                "card_key": row.get::<_, String>(0)?,
                "lang_code": row.get::<_, String>(1)?,
                "word_id": row.get::<_, String>(2)?,
                "card_type": row.get::<_, String>(3)?,
                "native_script": row.get::<_, String>(4)?,
                "pronunciation": row.get::<_, Option<String>>(5)?,
                "due_date": row.get::<_, String>(6)?,
                "interval": row.get::<_, Option<i64>>(7)?.unwrap_or(0),
                "ease": row.get::<_, Option<f64>>(8)?.unwrap_or(2.50),
                "reps": row.get::<_, Option<i64>>(9)?.unwrap_or(0),
                "lapses": row.get::<_, Option<i64>>(10)?.unwrap_or(0),
                "last_reviewed": row.get::<_, Option<String>>(11)?,
                "updated_at": row.get::<_, i64>(12)?,
                "deleted_at": row.get::<_, Option<i64>>(13)?,
            }))
        },
    )?;

    Ok(Json(PullResponse {
        server_time: now,
        languages,
        daily_logs,
        words,
        activities,
        word_srs,
    }))
}

/// GET /api/sync/events -> Server-Sent Events stream
pub async fn handle_sse_stream(
    State(state): State<Arc<AppState>>,
) -> Sse<impl Stream<Item = Result<Event, Infallible>>> {
    let rx = state.sync_tx.subscribe();

    let stream = BroadcastStream::new(rx).filter_map(|msg| match msg {
        Ok(lang) => Some(Ok(Event::default().event("sync").data(lang))),
        Err(_) => None,
    });

    Sse::new(stream).keep_alive(
        KeepAlive::new()
            .interval(Duration::from_secs(15))
            .text("keep-alive"),
    )
}

/// POST /api/sync/push
pub async fn handle_push(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<PushRequest>,
) -> Result<impl IntoResponse, (StatusCode, String)> {
    let mut conn = state.db_conn.lock().unwrap();
    let tx = conn
        .transaction()
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    let mut affected_langs = std::collections::HashSet::new();

    for mutation in &payload.mutations {
        if let Some(code) = mutation.data.get("lang_code").and_then(|c| c.as_str()) {
            affected_langs.insert(code.to_string());
        } else if let Some(code) = mutation.data.get("code").and_then(|c| c.as_str()) {
            affected_langs.insert(code.to_string());
        }

        match mutation.table.as_str() {
            "languages" => upsert_language(&tx, &mutation.data)?,
            "daily_logs" => upsert_daily_log(&tx, &mutation.data)?,
            "words" => upsert_word(&tx, &mutation.data)?,
            "activities" => upsert_activity(&tx, &mutation.data)?,
            "word_srs" => upsert_word_srs(&tx, &mutation.data)?,
            _ => continue,
        }
    }

    tx.commit()
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    // If language-agnostic mutations took place, broadcast empty string to trigger all subscribers
    if affected_langs.is_empty() {
        let _ = state.sync_tx.send("".to_string());
    } else {
        for lang in affected_langs {
            let _ = state.sync_tx.send(lang);
        }
    }

    Ok(Json(serde_json::json!({ "status": "ok" })))
}

fn upsert_language(tx: &Transaction, data: &Value) -> Result<(), (StatusCode, String)> {
    let code = data["code"].as_str().ok_or((StatusCode::BAD_REQUEST, "Missing code".into()))?;
    let name = extract_str(&data["name"], code);

    // Normalize JSON strings cleanly
    let goals_json = extract_json_str(data, "goals", "goals_json", "{}");
    let milestones_json = extract_json_str(data, "milestones", "milestones_json", "{}");
    let momentum_json = extract_json_str(data, "momentum", "momentum_json", "{}");
    let colors_json = extract_json_str(data, "colors", "colors_json", "{}");
    let tones_json = extract_json_str(data, "tones", "tones_json", "{}");

    let current_streak = extract_i64(&data["current_streak"]);
    let longest_streak = extract_i64(&data["longest_streak"]);
    let total_days = extract_i64(&data["total_days"]);
    let updated_at = match extract_i64(&data["updated_at"]) {
        0 => Utc::now().timestamp_millis(),
        ts => ts,
    };
    let deleted_at = data["deleted_at"].as_i64();

    tx.execute(
        "INSERT INTO languages (code, name, goals_json, milestones_json, momentum_json, colors_json, tones_json, \
                                current_streak, longest_streak, total_days, updated_at, deleted_at) \
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12) \
         ON CONFLICT(code) DO UPDATE SET \
            name = excluded.name, \
            goals_json = excluded.goals_json, \
            milestones_json = excluded.milestones_json, \
            momentum_json = excluded.momentum_json, \
            colors_json = excluded.colors_json, \
            tones_json = excluded.tones_json, \
            current_streak = excluded.current_streak, \
            longest_streak = excluded.longest_streak, \
            total_days = excluded.total_days, \
            updated_at = excluded.updated_at, \
            deleted_at = excluded.deleted_at \
         WHERE excluded.updated_at >= languages.updated_at;",
        params![
            code, name, goals_json, milestones_json, momentum_json, colors_json, tones_json,
            current_streak, longest_streak, total_days, updated_at, deleted_at
        ],
    ).map_err(|e| {
        error!(target: "sync", error = %e, "Failed upserting language");
        (StatusCode::INTERNAL_SERVER_ERROR, e.to_string())
    })?;

    Ok(())
}

fn upsert_daily_log(tx: &Transaction, data: &Value) -> Result<(), (StatusCode, String)> {
    let id = data["id"].as_str().ok_or((StatusCode::BAD_REQUEST, "Missing daily_log id".into()))?;
    let lang_code = extract_str(&data["lang_code"], "");
    let log_date = data["log_date"].as_str().or_else(|| data["date"].as_str()).unwrap_or("");
    let due_date = extract_opt_str(&data["due_date"]);

    let ease = if data["ease"].is_null() { 2.50 } else { extract_f64(&data["ease"]) };
    let interval = extract_i64(&data["interval"]);
    let revision = extract_i64(&data["revision"]);

    let word = extract_i64(&data["word"]);
    let ci = extract_i64(&data["ci"]);
    let grammar = extract_i64(&data["grammar"]);
    let listening = extract_i64(&data["listening"]);
    let speaking_time = extract_f64(&data["speaking_time"]);
    let listening_time = extract_f64(&data["listening_time"]);

    let vocab_done = extract_i64(&data["vocab_done"]);
    let ci_done = extract_i64(&data["ci_done"]);
    let listening_done = extract_i64(&data["listening_done"]);
    let speaking_done = extract_i64(&data["speaking_done"]);
    let grammar_done = extract_i64(&data["grammar_done"]);

    let reviews = &data["reviews_completed"];
    let srs_vision_done = if !reviews["srs_vision"].is_null() {
        extract_i64(&reviews["srs_vision"])
    } else {
        extract_i64(&data["srs_vision_done"])
    };
    let srs_listen_done = if !reviews["srs_listen"].is_null() {
        extract_i64(&reviews["srs_listen"])
    } else {
        extract_i64(&data["srs_listen_done"])
    };
    let srs_write_done = if !reviews["srs_write"].is_null() {
        extract_i64(&reviews["srs_write"])
    } else {
        extract_i64(&data["srs_write_done"])
    };
    let revisions_done = if !reviews["day_revisions"].is_null() {
        extract_i64(&reviews["day_revisions"])
    } else {
        extract_i64(&data["revisions_done"])
    };

    let unvoiced_words = extract_json_str(data, "unvoiced_words_indices", "unvoiced_words_json", "[]");
    let unvoiced_ci = extract_json_str(data, "unvoiced_ci_indices", "unvoiced_ci_json", "[]");
    let unvoiced_listening = extract_json_str(data, "unvoiced_listening_indices", "unvoiced_listening_json", "[]");
    let unvoiced_grammar = extract_json_str(data, "unvoiced_grammar_indices", "unvoiced_grammar_json", "[]");

    let updated_at = match extract_i64(&data["updated_at"]) {
        0 => Utc::now().timestamp_millis(),
        ts => ts,
    };
    let deleted_at = data["deleted_at"].as_i64();

    tx.execute(
        "INSERT INTO daily_logs (
            id, lang_code, log_date, due_date, ease, interval, revision,
            word, ci, grammar, listening, speaking_time, listening_time,
            vocab_done, ci_done, listening_done, speaking_done, grammar_done,
            srs_vision_done, srs_listen_done, srs_write_done, revisions_done,
            unvoiced_words_json, unvoiced_ci_json, unvoiced_listening_json, unvoiced_grammar_json,
            updated_at, deleted_at
        ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19, ?20, ?21, ?22, ?23, ?24, ?25, ?26, ?27, ?28)
        ON CONFLICT(id) DO UPDATE SET
            due_date = excluded.due_date,
            ease = excluded.ease,
            interval = excluded.interval,
            revision = excluded.revision,
            word = excluded.word,
            ci = excluded.ci,
            grammar = excluded.grammar,
            listening = excluded.listening,
            speaking_time = excluded.speaking_time,
            listening_time = excluded.listening_time,
            vocab_done = excluded.vocab_done,
            ci_done = excluded.ci_done,
            listening_done = excluded.listening_done,
            speaking_done = excluded.speaking_done,
            grammar_done = excluded.grammar_done,
            srs_vision_done = excluded.srs_vision_done,
            srs_listen_done = excluded.srs_listen_done,
            srs_write_done = excluded.srs_write_done,
            revisions_done = excluded.revisions_done,
            unvoiced_words_json = excluded.unvoiced_words_json,
            unvoiced_ci_json = excluded.unvoiced_ci_json,
            unvoiced_listening_json = excluded.unvoiced_listening_json,
            unvoiced_grammar_json = excluded.unvoiced_grammar_json,
            updated_at = excluded.updated_at,
            deleted_at = excluded.deleted_at
        WHERE excluded.updated_at >= daily_logs.updated_at;",
        params![
            id, lang_code, log_date, due_date, ease, interval, revision,
            word, ci, grammar, listening, speaking_time, listening_time,
            vocab_done, ci_done, listening_done, speaking_done, grammar_done,
            srs_vision_done, srs_listen_done, srs_write_done, revisions_done,
            unvoiced_words, unvoiced_ci, unvoiced_listening, unvoiced_grammar,
            updated_at, deleted_at
        ],
    ).map_err(|e| {
        error!(target: "sync", error = %e, "Failed upserting daily_log");
        (StatusCode::INTERNAL_SERVER_ERROR, e.to_string())
    })?;

    Ok(())
}

fn upsert_word(tx: &Transaction, data: &Value) -> Result<(), (StatusCode, String)> {
    let id = data["id"].as_str().ok_or((StatusCode::BAD_REQUEST, "Missing word id".into()))?;
    let lang_code = extract_str(&data["lang_code"], "");
    let log_date = extract_str(&data["log_date"], "");
    let word_index = extract_i64(&data["word_index"]).max(1);
    let native_script = extract_str(&data["native_script"], "");
    let pronunciation = extract_str(&data["pronunciation"], "");
    let link = extract_opt_str(&data["link"]);
    let audio_duration = extract_f64(&data["audio_duration"]);
    let updated_at = match extract_i64(&data["updated_at"]) {
        0 => Utc::now().timestamp_millis(),
        ts => ts,
    };
    let deleted_at = data["deleted_at"].as_i64();

    tx.execute(
        "INSERT INTO words (id, lang_code, log_date, word_index, native_script, pronunciation, \
                            link, audio_duration, updated_at, deleted_at) \
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10) \
         ON CONFLICT(id) DO UPDATE SET \
            word_index = excluded.word_index, \
            native_script = excluded.native_script, \
            pronunciation = excluded.pronunciation, \
            link = excluded.link, \
            audio_duration = excluded.audio_duration, \
            updated_at = excluded.updated_at, \
            deleted_at = excluded.deleted_at \
         WHERE excluded.updated_at >= words.updated_at;",
        params![
            id, lang_code, log_date, word_index, native_script, pronunciation,
            link, audio_duration, updated_at, deleted_at
        ],
    ).map_err(|e| {
        error!(target: "sync", error = %e, "Failed upserting word");
        (StatusCode::INTERNAL_SERVER_ERROR, e.to_string())
    })?;

    Ok(())
}

fn upsert_activity(tx: &Transaction, data: &Value) -> Result<(), (StatusCode, String)> {
    let id = data["id"].as_str().ok_or((StatusCode::BAD_REQUEST, "Missing activity id".into()))?;
    let lang_code = extract_str(&data["lang_code"], "");
    let log_date = extract_str(&data["log_date"], "");
    let activity_type = extract_str(&data["activity_type"], "ci");
    let item_index = extract_i64(&data["item_index"]).max(1);
    let link = extract_opt_str(&data["link"]);
    let link_duration = extract_f64(if !data["link_duration"].is_null() {
        &data["link_duration"]
    } else {
        &data["durationSec"]
    });
    let audio_duration = extract_f64(&data["audio_duration"]);
    let metadata_json = extract_json_str(data, "metadata", "metadata_json", "{}");
    let updated_at = match extract_i64(&data["updated_at"]) {
        0 => Utc::now().timestamp_millis(),
        ts => ts,
    };
    let deleted_at = data["deleted_at"].as_i64();

    tx.execute(
        "INSERT INTO activities (id, lang_code, log_date, activity_type, item_index, link, \
                                link_duration, audio_duration, metadata_json, updated_at, deleted_at) \
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11) \
         ON CONFLICT(id) DO UPDATE SET \
            activity_type = excluded.activity_type, \
            item_index = excluded.item_index, \
            link = excluded.link, \
            link_duration = excluded.link_duration, \
            audio_duration = excluded.audio_duration, \
            metadata_json = excluded.metadata_json, \
            updated_at = excluded.updated_at, \
            deleted_at = excluded.deleted_at \
         WHERE excluded.updated_at >= activities.updated_at;",
        params![
            id, lang_code, log_date, activity_type, item_index, link,
            link_duration, audio_duration, metadata_json, updated_at, deleted_at
        ],
    ).map_err(|e| {
        error!(target: "sync", error = %e, "Failed upserting activity");
        (StatusCode::INTERNAL_SERVER_ERROR, e.to_string())
    })?;

    Ok(())
}

fn upsert_word_srs(tx: &Transaction, data: &Value) -> Result<(), (StatusCode, String)> {
    let card_key = data["card_key"].as_str().ok_or((StatusCode::BAD_REQUEST, "Missing card_key".into()))?;
    let lang_code = extract_str(&data["lang_code"], "");
    let word_id = extract_str(&data["word_id"], "");
    let card_type = extract_str(&data["card_type"], "visual");
    let native_script = extract_str(&data["native_script"], "");
    let pronunciation = extract_opt_str(&data["pronunciation"]);
    
    let today_str = Utc::now().format("%Y-%m-%d").to_string();
    let due_date = data["due_date"].as_str().unwrap_or(&today_str);

    let interval = extract_i64(&data["interval"]);
    let ease = if data["ease"].is_null() { 2.50 } else { extract_f64(&data["ease"]) };
    let reps = extract_i64(&data["reps"]);
    let lapses = extract_i64(&data["lapses"]);
    let last_reviewed = extract_opt_str(&data["last_reviewed"]);
    let updated_at = match extract_i64(&data["updated_at"]) {
        0 => Utc::now().timestamp_millis(),
        ts => ts,
    };
    let deleted_at = data["deleted_at"].as_i64();

    tx.execute(
        "INSERT INTO word_srs (
            card_key, lang_code, word_id, card_type, native_script, pronunciation,
            due_date, interval, ease, reps, lapses, last_reviewed, updated_at, deleted_at
        ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14)
        ON CONFLICT(card_key) DO UPDATE SET
            native_script = excluded.native_script,
            pronunciation = excluded.pronunciation,
            due_date = excluded.due_date,
            interval = excluded.interval,
            ease = excluded.ease,
            reps = excluded.reps,
            lapses = excluded.lapses,
            last_reviewed = excluded.last_reviewed,
            updated_at = excluded.updated_at,
            deleted_at = excluded.deleted_at
        WHERE excluded.updated_at >= word_srs.updated_at;",
        params![
            card_key, lang_code, word_id, card_type, native_script, pronunciation,
            due_date, interval, ease, reps, lapses, last_reviewed, updated_at, deleted_at
        ],
    ).map_err(|e| {
        error!(target: "sync", error = %e, "Failed upserting word_srs");
        (StatusCode::INTERNAL_SERVER_ERROR, e.to_string())
    })?;

    Ok(())
}

fn fetch_table_deltas<F>(
    conn: &Connection,
    sql: &str,
    lang: &str,
    since: i64,
    map_fn: F,
) -> Result<Vec<Value>, (StatusCode, String)>
where
    F: Fn(&rusqlite::Row) -> Result<Value, rusqlite::Error>,
{
    let mut stmt = conn.prepare(sql).map_err(|e| {
        error!(target: "sync", sql = %sql, error = %e, "Query prepare failed in pull");
        (StatusCode::INTERNAL_SERVER_ERROR, e.to_string())
    })?;

    let rows = stmt
        .query_map(params![lang, since], |row| map_fn(row))
        .map_err(|e| {
            error!(target: "sync", error = %e, "query_map execution failed in pull");
            (StatusCode::INTERNAL_SERVER_ERROR, e.to_string())
        })?;

    let mut results = Vec::new();
    for row in rows {
        match row {
            Ok(val) => results.push(val),
            Err(e) => {
                warn!(target: "sync", error = %e, "Row decode warning in delta pull; skipping entry");
            }
        }
    }
    Ok(results)
}