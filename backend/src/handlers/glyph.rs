// backend/src/handlers/glyph.rs
use axum::{
    extract::{Path, State},
    http::StatusCode,
    response::Json,
};
use rusqlite::params;
use serde::Serialize;
use std::sync::Arc;
use crate::state::AppState;

#[derive(Serialize)]
pub struct GlyphResponse {
    pub character: String,
    pub phonetic: String,
    pub definition: String,
    pub component1: String,
    pub component2: String,
    pub mnemonic: String,
    pub strokes: Vec<String>,
    pub medians: Vec<Vec<Vec<f64>>>,
    pub component1_strokes: Vec<usize>,
}

/// Strips Arabic Harakat / Tashkeel diacritics (\u{064B} through \u{065F} and \u{0670})
fn strip_arabic_tashkeel(s: &str) -> String {
    s.chars()
        .filter(|&c| !('\u{064B}'..='\u{065F}').contains(&c) && c != '\u{0670}')
        .collect()
}

pub async fn handle_glyph_lookup(
    Path((lang, ch)): Path<(String, String)>,
    State(state): State<Arc<AppState>>,
) -> Result<Json<GlyphResponse>, StatusCode> {
    // 1. Percent-decode the character if encoded by the browser
    let clean_char = ch.trim().to_string();

    if clean_char.is_empty() {
        return Err(StatusCode::BAD_REQUEST);
    }

    let lang_conn = state.get_lexicon_conn(&lang)
        .ok_or(StatusCode::NOT_FOUND)?;

    let is_arabic = lang.starts_with("ar");
    let bare_arabic = if is_arabic {
        strip_arabic_tashkeel(&clean_char)
    } else {
        String::new()
    };

    let result = tokio::task::spawn_blocking(move || {
        let conn = lang_conn.lock().unwrap();

        // 1. Primary: Exact match (Chinese Hanzi, exact vocalized Arabic)
        let exact_sql = 
            "SELECT character, phonetic, definition, component1, component2, mnemonic, 
                    strokes_json, medians_json, component1_strokes
             FROM glyph_lexicon 
             WHERE character = ?1 
             LIMIT 1";

        if let Ok(mut stmt) = conn.prepare(exact_sql) {
            let direct_match = stmt.query_row(params![clean_char], |row| {
                let character: String = row.get(0)?;
                let phonetic: String = row.get(1)?;
                let definition: String = row.get(2)?;
                let component1: String = row.get(3)?;
                let component2: String = row.get(4)?;
                let mnemonic: String = row.get(5)?;

                let strokes_raw: String = row.get(6)?;
                let medians_raw: String = row.get(7)?;
                let comp1_raw: String = row.get(8)?;

                let strokes: Vec<String> = serde_json::from_str(&strokes_raw).unwrap_or_default();
                let medians: Vec<Vec<Vec<f64>>> = serde_json::from_str(&medians_raw).unwrap_or_default();
                let component1_strokes: Vec<usize> = serde_json::from_str(&comp1_raw).unwrap_or_default();

                Ok(GlyphResponse {
                    character,
                    phonetic,
                    definition,
                    component1,
                    component2,
                    mnemonic,
                    strokes,
                    medians,
                    component1_strokes,
                })
            }).ok();

            if direct_match.is_some() {
                return direct_match;
            }
        }

        // 2. Arabic Fallback: If user searched unvocalized "مكتب", find "مَكْتَب%"
        if is_arabic && !bare_arabic.is_empty() {
            let fallback_sql = 
                "SELECT character, phonetic, definition, component1, component2, mnemonic, 
                        strokes_json, medians_json, component1_strokes
                 FROM glyph_lexicon 
                 WHERE character LIKE ?1
                 LIMIT 1";

            if let Ok(mut stmt) = conn.prepare(fallback_sql) {
                let prefix_query = format!("{}%", bare_arabic);
                return stmt.query_row(params![prefix_query], |row| {
                    let character: String = row.get(0)?;
                    let phonetic: String = row.get(1)?;
                    let definition: String = row.get(2)?;
                    let component1: String = row.get(3)?;
                    let component2: String = row.get(4)?;
                    let mnemonic: String = row.get(5)?;

                    let strokes_raw: String = row.get(6)?;
                    let medians_raw: String = row.get(7)?;
                    let comp1_raw: String = row.get(8)?;

                    let strokes: Vec<String> = serde_json::from_str(&strokes_raw).unwrap_or_default();
                    let medians: Vec<Vec<Vec<f64>>> = serde_json::from_str(&medians_raw).unwrap_or_default();
                    let component1_strokes: Vec<usize> = serde_json::from_str(&comp1_raw).unwrap_or_default();

                    Ok(GlyphResponse {
                        character,
                        phonetic,
                        definition,
                        component1,
                        component2,
                        mnemonic,
                        strokes,
                        medians,
                        component1_strokes,
                    })
                }).ok();
            }
        }

        None
    })
    .await
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    match result {
        Some(glyph) => Ok(Json(glyph)),
        None => Err(StatusCode::NOT_FOUND),
    }
}