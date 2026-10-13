use axum::{
    extract::{Path, State},
    http::StatusCode,
    Json,
};
use chrono::Utc;
use rusqlite::params;
use serde::{Deserialize, Deserializer, Serialize};
use serde_json::{json, Value};
use std::collections::HashMap;
use std::sync::Arc;

use crate::state::{AppState, InvalidationMessage};

// -----------------------------------------------------------------------------
// Serde Coercion Helpers
// -----------------------------------------------------------------------------

/// Coerces either a JSON Number (e.g. 1791881033972) or String ("abc-123") into Some(String)
fn deserialize_id_as_string<'de, D>(deserializer: D) -> Result<Option<String>, D::Error>
where
    D: Deserializer<'de>,
{
    let opt = Option::<Value>::deserialize(deserializer)?;
    match opt {
        Some(Value::String(s)) => {
            if s.trim().is_empty() {
                Ok(None)
            } else {
                Ok(Some(s))
            }
        }
        Some(Value::Number(n)) => Ok(Some(n.to_string())),
        _ => Ok(None),
    }
}

/// Coerces either numbers or string numbers into Option<i64>
fn deserialize_optional_i64<'de, D>(deserializer: D) -> Result<Option<i64>, D::Error>
where
    D: Deserializer<'de>,
{
    let opt = Option::<Value>::deserialize(deserializer)?;
    match opt {
        Some(Value::Number(n)) => Ok(n.as_i64()),
        Some(Value::String(s)) => Ok(s.parse::<i64>().ok()),
        _ => Ok(None),
    }
}

// -----------------------------------------------------------------------------
// Request / Response Payloads
// -----------------------------------------------------------------------------

#[derive(Serialize, Deserialize, Debug)]
pub struct WordInput {
    #[serde(default, deserialize_with = "deserialize_id_as_string")]
    pub id: Option<String>,
    #[serde(default)]
    pub word_index: i64,
    #[serde(default)]
    pub native_script: String,
    #[serde(default)]
    pub pronunciation: String,
    pub link: Option<String>,
    #[serde(default, deserialize_with = "deserialize_optional_i64")]
    pub audio_duration: Option<i64>,
    #[serde(default, deserialize_with = "deserialize_optional_i64")]
    pub updated_at: Option<i64>,
}

#[derive(Serialize, Deserialize, Debug)]
pub struct ActivityInput {
    #[serde(default, deserialize_with = "deserialize_id_as_string")]
    pub id: Option<String>,
    #[serde(default)]
    pub activity_type: String,
    #[serde(default)]
    pub item_index: i64,
    pub link: Option<String>,
    #[serde(default, deserialize_with = "deserialize_optional_i64")]
    pub link_duration: Option<i64>,
    #[serde(default, deserialize_with = "deserialize_optional_i64")]
    pub audio_duration: Option<i64>,
    pub metadata: Option<Value>,
    #[serde(default, deserialize_with = "deserialize_optional_i64")]
    pub updated_at: Option<i64>,
}

#[derive(Serialize, Deserialize, Debug)]
pub struct DayPayload {
    pub date: String,
    pub words: Vec<Value>,
    pub activities: Vec<Value>,
    pub session: Value,
}

#[derive(Serialize, Deserialize, Debug)]
pub struct SessionUpdateInput {
    #[serde(default, deserialize_with = "deserialize_optional_i64")]
    pub vocab_done: Option<i64>,
    #[serde(default, deserialize_with = "deserialize_optional_i64")]
    pub ci_done: Option<i64>,
    #[serde(default, deserialize_with = "deserialize_optional_i64")]
    pub listening_done: Option<i64>,
    #[serde(default, deserialize_with = "deserialize_optional_i64")]
    pub speaking_done: Option<i64>,
    #[serde(default, deserialize_with = "deserialize_optional_i64")]
    pub grammar_done: Option<i64>,
    pub due_date: Option<String>,
    pub last_reviewed: Option<String>,
    pub ease: Option<f64>,
    #[serde(default, deserialize_with = "deserialize_optional_i64")]
    pub interval: Option<i64>,
    #[serde(default, deserialize_with = "deserialize_optional_i64")]
    pub revision: Option<i64>,
    #[serde(default, deserialize_with = "deserialize_optional_i64")]
    pub updated_at: Option<i64>,
}

#[derive(Serialize, Deserialize, Debug)]
pub struct LanguageInput {
    pub code: String,
    #[serde(default)]
    pub name: Option<String>,
    #[serde(default)]
    pub config: Option<Value>,
}

#[derive(Serialize, Deserialize, Debug)]
pub struct SRSRateInput {
    #[serde(default)]
    pub card_type: String,
    #[serde(default)]
    pub due_date: String,
    #[serde(default)]
    pub interval: i64,
    #[serde(default)]
    pub ease: f64,
    #[serde(default)]
    pub lapses: i64,
    pub last_reviewed: Option<String>,
    #[serde(default, deserialize_with = "deserialize_optional_i64")]
    pub updated_at: Option<i64>,
}

// -----------------------------------------------------------------------------
// Database Internal Helpers
// -----------------------------------------------------------------------------

fn ensure_log_id(
    conn: &rusqlite::Connection,
    lang: &str,
    date: &str,
    now_ms: i64,
) -> Result<String, StatusCode> {
    // 1. Guarantee language exists in languages table
    let _ = conn.execute(
        "INSERT INTO languages (code, name) VALUES (?1, ?1) ON CONFLICT(code) DO NOTHING",
        params![lang],
    );

    let log_id = format!("{}_{}", lang, date);

    // 2. Guarantee daily_logs row exists
    conn.execute(
        "INSERT INTO daily_logs (id, language_code, log_date, updated_at)
         VALUES (?1, ?2, ?3, ?4)
         ON CONFLICT(language_code, log_date) DO UPDATE SET updated_at = excluded.updated_at",
        params![log_id, lang, date, now_ms],
    )
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok(log_id)
}

// -----------------------------------------------------------------------------
// API Handlers
// -----------------------------------------------------------------------------

/// GET /api/day/{lang}/{date}
pub async fn get_day_data(
    State(state): State<Arc<AppState>>,
    Path((lang, date)): Path<(String, String)>,
) -> Result<Json<DayPayload>, StatusCode> {
    let conn = state.db_conn.lock().unwrap();
    let log_id = format!("{}_{}", lang, date);

    // 1. Fetch Words
    let mut words_stmt = conn
        .prepare(
            "SELECT id, word_index, native_script, pronunciation, link, audio_duration, updated_at
             FROM words
             WHERE log_id = ?1 AND deleted_at IS NULL
             ORDER BY word_index ASC",
        )
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let words = words_stmt
        .query_map(params![log_id], |row| {
            Ok(json!({
                "id": row.get::<_, String>(0)?,
                "word_index": row.get::<_, i64>(1)?,
                "native_script": row.get::<_, String>(2)?,
                "pronunciation": row.get::<_, String>(3)?,
                "link": row.get::<_, Option<String>>(4)?,
                "audio_duration": row.get::<_, Option<i64>>(5)?,
                "updated_at": row.get::<_, i64>(6)?
            }))
        })
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        .filter_map(|r| r.ok())
        .collect::<Vec<_>>();

    // 2. Fetch Activities
    let mut act_stmt = conn
        .prepare(
            "SELECT id, activity_type, item_index, link, link_duration, audio_duration, metadata, updated_at
             FROM activities
             WHERE log_id = ?1 AND deleted_at IS NULL
             ORDER BY item_index ASC",
        )
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let activities = act_stmt
        .query_map(params![log_id], |row| {
            let meta_raw: Option<String> = row.get(6)?;
            let meta_val = meta_raw
                .and_then(|s| serde_json::from_str::<Value>(&s).ok())
                .unwrap_or(Value::Null);

            Ok(json!({
                "id": row.get::<_, String>(0)?,
                "activity_type": row.get::<_, String>(1)?,
                "item_index": row.get::<_, i64>(2)?,
                "link": row.get::<_, Option<String>>(3)?,
                "link_duration": row.get::<_, Option<i64>>(4)?,
                "audio_duration": row.get::<_, Option<i64>>(5)?,
                "metadata": meta_val,
                "updated_at": row.get::<_, i64>(7)?
            }))
        })
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        .filter_map(|r| r.ok())
        .collect::<Vec<_>>();

    // 3. Fetch Session SRS Metadata
    let session_res = conn.query_row(
        "SELECT due_date, ease, interval, vocab_done, ci_done, listening_done, speaking_done, grammar_done, updated_at
         FROM daily_logs
         WHERE id = ?1 AND deleted_at IS NULL",
        params![log_id],
        |row| {
            Ok(json!({
                "due_date": row.get::<_, Option<String>>(0)?,
                "ease": row.get::<_, f64>(1)?,
                "interval": row.get::<_, i64>(2)?,
                "vocab_done": row.get::<_, i64>(3)?,
                "ci_done": row.get::<_, i64>(4)?,
                "listening_done": row.get::<_, i64>(5)?,
                "speaking_done": row.get::<_, i64>(6)?,
                "grammar_done": row.get::<_, i64>(7)?,
                "updated_at": row.get::<_, i64>(8)?
            }))
        },
    );

    let session = session_res.unwrap_or_else(|_| {
        json!({
            "due_date": null,
            "ease": 2.50,
            "interval": 0,
            "vocab_done": 0,
            "ci_done": 0,
            "listening_done": 0,
            "speaking_done": 0,
            "grammar_done": 0,
            "updated_at": Utc::now().timestamp_millis()
        })
    });

    Ok(Json(DayPayload {
        date,
        words,
        activities,
        session,
    }))
}

/// POST /api/day/{lang}/{date}/word
pub async fn add_word(
    State(state): State<Arc<AppState>>,
    Path((lang, date)): Path<(String, String)>,
    Json(payload): Json<WordInput>,
) -> Result<StatusCode, StatusCode> {
    let now_ms = payload.updated_at.unwrap_or_else(|| Utc::now().timestamp_millis());
    let word_id = payload
        .id
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| uuid::Uuid::new_v4().to_string());

    {
        let conn = state.db_conn.lock().unwrap();
        let log_id = ensure_log_id(&conn, &lang, &date, now_ms)?;

        conn.execute(
            "INSERT INTO words (id, log_id, word_index, native_script, pronunciation, link, audio_duration, updated_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
             ON CONFLICT(id) DO UPDATE SET
                word_index = excluded.word_index,
                native_script = excluded.native_script,
                pronunciation = excluded.pronunciation,
                link = excluded.link,
                audio_duration = excluded.audio_duration,
                updated_at = excluded.updated_at
             WHERE excluded.updated_at >= words.updated_at",
            params![
                word_id,
                log_id,
                payload.word_index,
                payload.native_script,
                payload.pronunciation,
                payload.link,
                payload.audio_duration,
                now_ms
            ],
        )
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

        // Auto-update vocab_done if words exist
        let _ = conn.execute(
            "UPDATE daily_logs 
             SET vocab_done = (CASE WHEN (SELECT COUNT(*) FROM words WHERE log_id = ?1 AND deleted_at IS NULL) >= 1 THEN 1 ELSE 0 END),
                 updated_at = ?2
             WHERE id = ?1",
            params![log_id, now_ms],
        );

        // Ensure word_srs rows exist for this word across all tri-decks
        for card_type in ["visual", "listening", "writing"] {
            let srs_id = format!("{}_{}", word_id, card_type);
            let _ = conn.execute(
                "INSERT INTO word_srs (id, word_id, card_type, due_date, updated_at)
                 VALUES (?1, ?2, ?3, ?4, ?5)
                 ON CONFLICT(id) DO NOTHING",
                params![srs_id, word_id, card_type, date, now_ms],
            );
        }
    }

    let _ = state.sync_bcast.send(InvalidationMessage {
        language_code: lang,
        log_date: date,
        entity: "words".to_string(),
        updated_at: now_ms,
    });

    Ok(StatusCode::CREATED)
}

/// POST /api/day/{lang}/{date}/activity
pub async fn add_activity(
    State(state): State<Arc<AppState>>,
    Path((lang, date)): Path<(String, String)>,
    Json(payload): Json<ActivityInput>,
) -> Result<StatusCode, StatusCode> {
    let now_ms = payload.updated_at.unwrap_or_else(|| Utc::now().timestamp_millis());
    let act_id = payload
        .id
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| uuid::Uuid::new_v4().to_string());
    let meta_str = payload.metadata.map(|m| m.to_string());

    {
        let conn = state.db_conn.lock().unwrap();
        let log_id = ensure_log_id(&conn, &lang, &date, now_ms)?;

        conn.execute(
            "INSERT INTO activities (id, log_id, activity_type, item_index, link, link_duration, audio_duration, metadata, updated_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)
             ON CONFLICT(id) DO UPDATE SET
                activity_type = excluded.activity_type,
                item_index = excluded.item_index,
                link = excluded.link,
                link_duration = excluded.link_duration,
                audio_duration = excluded.audio_duration,
                metadata = excluded.metadata,
                updated_at = excluded.updated_at
             WHERE excluded.updated_at >= activities.updated_at",
            params![
                act_id,
                log_id,
                payload.activity_type,
                payload.item_index,
                payload.link,
                payload.link_duration,
                payload.audio_duration,
                meta_str,
                now_ms
            ],
        )
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

        // Auto-update ci_done, listening_done, grammar_done
        let _ = conn.execute(
            "UPDATE daily_logs 
             SET ci_done = (CASE WHEN (SELECT COUNT(*) FROM activities WHERE log_id = ?1 AND activity_type = 'ci' AND deleted_at IS NULL) >= 1 THEN 1 ELSE ci_done END),
                 listening_done = (CASE WHEN (SELECT COUNT(*) FROM activities WHERE log_id = ?1 AND activity_type = 'listening' AND deleted_at IS NULL) >= 1 THEN 1 ELSE listening_done END),
                 grammar_done = (CASE WHEN (SELECT COUNT(*) FROM activities WHERE log_id = ?1 AND activity_type = 'grammar' AND deleted_at IS NULL) >= 1 THEN 1 ELSE grammar_done END),
                 updated_at = ?2
             WHERE id = ?1",
            params![log_id, now_ms],
        );
    }

    let _ = state.sync_bcast.send(InvalidationMessage {
        language_code: lang,
        log_date: date,
        entity: "activities".to_string(),
        updated_at: now_ms,
    });

    Ok(StatusCode::CREATED)
}

/// POST /api/day/{lang}/{date}/session
pub async fn update_day_session(
    State(state): State<Arc<AppState>>,
    Path((lang, date)): Path<(String, String)>,
    Json(payload): Json<SessionUpdateInput>,
) -> Result<StatusCode, StatusCode> {
    let now_ms = payload.updated_at.unwrap_or_else(|| Utc::now().timestamp_millis());
    let conn = state.db_conn.lock().unwrap();

    let log_id = ensure_log_id(&conn, &lang, &date, now_ms)?;

    conn.execute(
        "UPDATE daily_logs SET
            vocab_done = COALESCE(?1, vocab_done),
            ci_done = COALESCE(?2, ci_done),
            listening_done = COALESCE(?3, listening_done),
            speaking_done = COALESCE(?4, speaking_done),
            grammar_done = COALESCE(?5, grammar_done),
            due_date = COALESCE(?6, due_date),
            ease = COALESCE(?7, ease),
            interval = COALESCE(?8, interval),
            updated_at = ?9
         WHERE id = ?10",
        params![
            payload.vocab_done,
            payload.ci_done,
            payload.listening_done,
            payload.speaking_done,
            payload.grammar_done,
            payload.due_date,
            payload.ease,
            payload.interval,
            now_ms,
            log_id
        ],
    )
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let _ = state.sync_bcast.send(InvalidationMessage {
        language_code: lang,
        log_date: date,
        entity: "daily_logs".to_string(),
        updated_at: now_ms,
    });

    Ok(StatusCode::OK)
}

/// GET /api/metadata
pub async fn get_metadata(
    State(state): State<Arc<AppState>>,
) -> Result<Json<Value>, StatusCode> {
    let conn = state.db_conn.lock().unwrap();

    let mut langs_map = serde_json::Map::new();
    let mut stmt = conn
        .prepare("SELECT code, name FROM languages")
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let lang_rows = stmt
        .query_map([], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
        })
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    for r in lang_rows.flatten() {
        let (code, name) = r;
        langs_map.insert(
            code.clone(),
            json!({
                "code": code,
                "name": name,
                "current_streak": 1,
                "longest_streak": 1,
                "total_days": 1
            }),
        );
    }

    let mut calendar_map = serde_json::Map::new();
    let mut cal_stmt = conn
        .prepare(
            "SELECT d.id, d.language_code, d.log_date, d.due_date, d.ease, d.interval,
                    d.vocab_done, d.ci_done, d.listening_done, d.speaking_done, d.grammar_done,
                    (SELECT COUNT(*) FROM words w WHERE w.log_id = d.id AND w.deleted_at IS NULL) as w_cnt,
                    (SELECT COUNT(*) FROM activities a WHERE a.log_id = d.id AND a.activity_type = 'ci' AND a.deleted_at IS NULL) as ci_cnt,
                    (SELECT COUNT(*) FROM activities a WHERE a.log_id = d.id AND a.activity_type = 'listening' AND a.deleted_at IS NULL) as l_cnt,
                    (SELECT COUNT(*) FROM activities a WHERE a.log_id = d.id AND a.activity_type = 'grammar' AND a.deleted_at IS NULL) as g_cnt,
                    (SELECT COALESCE(SUM(link_duration), 0) FROM activities a WHERE a.log_id = d.id AND a.activity_type = 'listening' AND a.deleted_at IS NULL) as l_sec,
                    (SELECT COALESCE(SUM(audio_duration), 0) FROM activities a WHERE a.log_id = d.id AND a.activity_type = 'speaking' AND a.deleted_at IS NULL) as s_sec
             FROM daily_logs d
             WHERE d.deleted_at IS NULL
             ORDER BY d.log_date DESC",
        )
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let cal_rows = cal_stmt
        .query_map([], |row| {
            let lang_code: String = row.get(1)?;
            let log_date: String = row.get(2)?;
            let key = format!("{}:{}", lang_code, log_date);

            let entry = json!({
                "date": log_date,
                "due_date": row.get::<_, Option<String>>(3)?.unwrap_or_else(|| log_date.clone()),
                "word": row.get::<_, i64>(11)?,
                "ci": row.get::<_, i64>(12)?,
                "listening": row.get::<_, i64>(13)?,
                "grammar": row.get::<_, i64>(14)?,
                "listening_time": row.get::<_, i64>(15)?,
                "speaking_time": row.get::<_, i64>(16)?,
                "vocab_done": row.get::<_, i64>(6)? != 0,
                "ci_done": row.get::<_, i64>(7)? != 0,
                "listening_done": row.get::<_, i64>(8)? != 0,
                "speaking_done": row.get::<_, i64>(9)? != 0,
                "grammar_done": row.get::<_, i64>(10)? != 0,
                "reviews_completed": {
                    "srs_vision": 0,
                    "srs_listen": 0,
                    "srs_write": 0,
                    "day_revisions": 0
                }
            });

            Ok((key, entry))
        })
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    for r in cal_rows.flatten() {
        calendar_map.insert(r.0, r.1);
    }

    Ok(Json(json!({
        "languages": langs_map,
        "calendar_index": calendar_map
    })))
}

/// GET /api/metadata/languages
pub async fn get_languages(
    State(state): State<Arc<AppState>>,
) -> Result<Json<Vec<Value>>, StatusCode> {
    let conn = state.db_conn.lock().unwrap();
    let mut stmt = conn
        .prepare("SELECT code, name FROM languages")
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let langs = stmt
        .query_map([], |row| {
            Ok(json!({
                "code": row.get::<_, String>(0)?,
                "name": row.get::<_, String>(1)?,
            }))
        })
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        .filter_map(|r| r.ok())
        .collect();

    Ok(Json(langs))
}

/// POST /api/metadata/languages
pub async fn add_or_update_language(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<LanguageInput>,
) -> Result<StatusCode, StatusCode> {
    let conn = state.db_conn.lock().unwrap();
    let lang_name = payload.name.unwrap_or_else(|| payload.code.clone());

    conn.execute(
        "INSERT INTO languages (code, name) VALUES (?1, ?2)
         ON CONFLICT(code) DO UPDATE SET name = excluded.name",
        params![payload.code, lang_name],
    )
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let _ = state.sync_bcast.send(InvalidationMessage {
        language_code: payload.code,
        log_date: "metadata".to_string(),
        entity: "languages".to_string(),
        updated_at: Utc::now().timestamp_millis(),
    });

    Ok(StatusCode::OK)
}

/// GET /api/srs/{lang}
pub async fn get_srs_queue(
    State(state): State<Arc<AppState>>,
    Path(lang): Path<String>,
) -> Result<Json<HashMap<String, Value>>, StatusCode> {
    let conn = state.db_conn.lock().unwrap();
    let mut stmt = conn
        .prepare(
            "SELECT s.id, w.native_script, s.card_type, s.due_date, s.interval, s.ease, s.lapses, s.last_reviewed
             FROM word_srs s
             JOIN words w ON s.word_id = w.id
             JOIN daily_logs d ON w.log_id = d.id
             WHERE d.language_code = ?1 AND s.deleted_at IS NULL",
        )
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let mut out = HashMap::new();
    let rows = stmt
        .query_map(params![lang], |r| {
            let id: String = r.get(0)?;
            let native: String = r.get(1)?;
            let card_type: String = r.get(2)?;
            let due_date: String = r.get(3)?;
            let interval: i64 = r.get(4)?;
            let ease: f64 = r.get(5)?;
            let lapses: i64 = r.get(6)?;
            let last_reviewed: Option<String> = r.get(7)?;

            Ok((
                id.clone(),
                json!({
                    "id": id,
                    "native": native,
                    "card_type": card_type,
                    "due_date": due_date,
                    "interval": interval,
                    "ease": ease,
                    "lapses": lapses,
                    "last_reviewed": last_reviewed
                }),
            ))
        })
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    for row in rows.flatten() {
        out.insert(row.0, row.1);
    }

    Ok(Json(out))
}

/// POST /api/srs/{lang}/{card_id}/rate
pub async fn rate_srs_card(
    State(state): State<Arc<AppState>>,
    Path((lang, card_id)): Path<(String, String)>,
    Json(payload): Json<SRSRateInput>,
) -> Result<StatusCode, StatusCode> {
    let now_ms = payload.updated_at.unwrap_or_else(|| Utc::now().timestamp_millis());
    let conn = state.db_conn.lock().unwrap();

    conn.execute(
        "UPDATE word_srs SET
            due_date = ?1,
            interval = ?2,
            ease = ?3,
            lapses = ?4,
            last_reviewed = ?5,
            updated_at = ?6
         WHERE id = ?7",
        params![
            payload.due_date,
            payload.interval,
            payload.ease,
            payload.lapses,
            payload.last_reviewed,
            now_ms,
            card_id
        ],
    )
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let _ = state.sync_bcast.send(InvalidationMessage {
        language_code: lang,
        log_date: "srs".to_string(),
        entity: "word_srs".to_string(),
        updated_at: now_ms,
    });

    Ok(StatusCode::OK)
}

/// GET /api/index/{lang}/ci
pub async fn get_ci_index(
    State(state): State<Arc<AppState>>,
    Path(lang): Path<String>,
) -> Result<Json<Vec<String>>, StatusCode> {
    let conn = state.db_conn.lock().unwrap();
    let mut stmt = conn
        .prepare(
            "SELECT DISTINCT a.link
             FROM activities a
             JOIN daily_logs d ON a.log_id = d.id
             WHERE d.language_code = ?1 AND a.activity_type = 'ci' AND a.link IS NOT NULL AND a.deleted_at IS NULL",
        )
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let links = stmt
        .query_map(params![lang], |r| r.get::<_, String>(0))
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        .filter_map(|r| r.ok())
        .collect();

    Ok(Json(links))
}

/// GET /api/index/{lang}/listening
pub async fn get_listening_index(
    State(state): State<Arc<AppState>>,
    Path(lang): Path<String>,
) -> Result<Json<Vec<Value>>, StatusCode> {
    let conn = state.db_conn.lock().unwrap();
    let mut stmt = conn
        .prepare(
            "SELECT d.log_date, a.link
             FROM activities a
             JOIN daily_logs d ON a.log_id = d.id
             WHERE d.language_code = ?1 AND a.activity_type = 'listening' AND a.link IS NOT NULL AND a.deleted_at IS NULL",
        )
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let entries = stmt
        .query_map(params![lang], |r| {
            Ok(json!({
                "date": r.get::<_, String>(0)?,
                "link": r.get::<_, String>(1)?,
            }))
        })
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        .filter_map(|r| r.ok())
        .collect();

    Ok(Json(entries))
}

/// GET /api/index/{lang}/vocab
pub async fn get_vocab_index(
    State(state): State<Arc<AppState>>,
    Path(lang): Path<String>,
) -> Result<Json<Vec<Value>>, StatusCode> {
    let conn = state.db_conn.lock().unwrap();
    let mut stmt = conn
        .prepare(
            "SELECT w.native_script, w.pronunciation, d.log_date
             FROM words w
             JOIN daily_logs d ON w.log_id = d.id
             WHERE d.language_code = ?1 AND w.deleted_at IS NULL
             ORDER BY d.log_date DESC, w.word_index ASC",
        )
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let entries = stmt
        .query_map(params![lang], |r| {
            Ok(json!({
                "native_script": r.get::<_, String>(0)?,
                "pronunciation": r.get::<_, String>(1)?,
                "date": r.get::<_, String>(2)?,
            }))
        })
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        .filter_map(|r| r.ok())
        .collect();

    Ok(Json(entries))
}