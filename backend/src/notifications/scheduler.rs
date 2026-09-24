use crate::db::load_blob_for_room;
use crate::notifications::{broadcast_push, NotificationEvent};
use crate::state::AppState;
use chrono::{Local, Timelike};
use serde_json::Value as JsonValue;
use std::collections::HashMap;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::Mutex;
use tracing::{error, info};
use yrs::updates::decoder::Decode;
use yrs::{Array, Doc, Map, ReadTxn, Transact, Update};

pub fn start_notification_worker(state: Arc<AppState>) {
    tokio::spawn(async move {
        info!(target: "scheduler", "Yjs notification rule engine background worker started");

        let sent_tracker = Arc::new(Mutex::new(HashMap::<String, i64>::new()));
        let mut last_clean_date = String::new();

        let mut interval = tokio::time::interval(Duration::from_secs(15 * 60)); // Check every 15 mins

        loop {
            interval.tick().await;

            let now = Local::now();
            let current_hour = now.hour();
            let current_minute = now.minute();
            let today_str = now.format("%Y-%m-%d").to_string();
            let now_ts = now.timestamp();

            if today_str != last_clean_date {
                let mut tracker = sent_tracker.lock().await;
                tracker.clear();
                last_clean_date = today_str.clone();
            }

            if let Err(e) = evaluate_and_notify(&state, &today_str, current_hour, current_minute, now_ts, &sent_tracker).await {
                error!(target: "scheduler", error = %e, "Notification evaluation failed");
            }
        }
    });
}

async fn can_send(
    tracker: &Arc<Mutex<HashMap<String, i64>>>,
    key: &str,
    now_ts: i64,
    cooldown_minutes: i64,
) -> bool {
    let mut map = tracker.lock().await;
    if let Some(&last_sent) = map.get(key) {
        if now_ts - last_sent < cooldown_minutes * 60 {
            return false;
        }
    }
    map.insert(key.to_string(), now_ts);
    true
}

/// Helper to read a room's doc either from in-memory state.rooms or SQLite snapshot
async fn get_or_load_room_doc(state: &Arc<AppState>, room_name: &str) -> Option<Doc> {
    // 1. In-memory fast path
    {
        let rooms = state.rooms.read().await;
        if let Some(room) = rooms.get(room_name) {
            let doc_guard = room.doc.read().await;
            let doc = Doc::new();
            let update = doc_guard.transact().encode_diff_v1(&yrs::StateVector::default());
            if let Ok(u) = Update::decode_v1(&update) {
                {
                    let mut txn = doc.transact_mut();
                    let _ = txn.apply_update(u);
                }
                return Some(doc);
            }
        }
    }

    // 2. Fallback to SQLite blob storage
    let state_db = state.clone();
    let name_owned = room_name.to_string();
    let blob_opt = tokio::task::spawn_blocking(move || {
        let conn = state_db.db_conn.lock().unwrap();
        load_blob_for_room(&conn, &name_owned)
    })
    .await
    .ok()?;

    if let Some(blob) = blob_opt {
        if let Ok(update) = Update::decode_v1(&blob) {
            let doc = Doc::new();
            {
                let mut txn = doc.transact_mut();
                let _ = txn.apply_update(update);
            }
            return Some(doc);
        }
    }

    None
}

struct LanguageSnapshot {
    lang_code: String,
    current_streak: u32,
    revisions_done: u32,
    words_count: u32,
    ci_count: u32,
    listening_items: u32,
    media_listening_mins: u32,
    recorded_speaking_mins: u32,
    past_debt_dates: Vec<String>,
    visual_srs_due: usize,
    audio_srs_due: usize,
    missing_voice_sessions: Vec<(String, u32, Vec<String>, usize)>,
    unread_words: Vec<String>,
    incomplete_activities: Vec<String>,
    leech_words: Vec<String>,
}

async fn collect_snapshots(
    state: &Arc<AppState>,
    today_str: &str,
    current_hour: u32,
) -> Vec<LanguageSnapshot> {
    let mut snapshots = Vec::new();

    // 1. Load global:metadata room
    let meta_doc = match get_or_load_room_doc(state, "global:metadata").await {
        Some(doc) => doc,
        None => return snapshots,
    };

    let (languages_map, cal_index_map) = {
        let langs_map = meta_doc.get_or_insert_map("languages");
        let cal_map = meta_doc.get_or_insert_map("calendar_index");
        let txn = meta_doc.transact();

        let mut langs_json = HashMap::new();
        for (k, v) in langs_map.iter(&txn) {
            let json_str = v.to_string(&txn);
            if let Ok(parsed) = serde_json::from_str::<JsonValue>(&json_str) {
                langs_json.insert(k.to_string(), parsed);
            }
        }

        let mut cal_json = HashMap::new();
        for (k, v) in cal_map.iter(&txn) {
            let json_str = v.to_string(&txn);
            if let Ok(parsed) = serde_json::from_str::<JsonValue>(&json_str) {
                cal_json.insert(k.to_string(), parsed);
            }
        }

        (langs_json, cal_json)
    };

    for (lang_code, lang_val) in languages_map {
        let current_streak = lang_val.get("current_streak").and_then(|v| v.as_u64()).unwrap_or(1) as u32;

        let today_cal_key = format!("{lang_code}:{today_str}");
        let today_cal = cal_index_map.get(&today_cal_key);

        let revisions_done = today_cal.and_then(|c| c.get("revision")).and_then(|v| v.as_u64()).unwrap_or(0) as u32;
        let words_count = today_cal.and_then(|c| c.get("word")).and_then(|v| v.as_u64()).unwrap_or(0) as u32;
        let ci_count = today_cal.and_then(|c| c.get("ci")).and_then(|v| v.as_u64()).unwrap_or(0) as u32;
        let listening_items = today_cal.and_then(|c| c.get("listening")).and_then(|v| v.as_u64()).unwrap_or(0) as u32;
        let listening_sec = today_cal.and_then(|c| c.get("listening_time")).and_then(|v| v.as_u64()).unwrap_or(0) as u32;
        let speaking_sec = today_cal.and_then(|c| c.get("speaking_time")).and_then(|v| v.as_u64()).unwrap_or(0) as u32;

        let media_listening_mins = listening_sec / 60;
        let recorded_speaking_mins = speaking_sec / 60;

        let mut past_debt_dates = Vec::new();
        for (cal_key, cal_obj) in &cal_index_map {
            if cal_key.starts_with(&format!("{lang_code}:")) {
                if let Some(date_str) = cal_obj.get("date").and_then(|d| d.as_str()) {
                    if date_str < today_str {
                        let rev = cal_obj.get("revision").and_then(|r| r.as_u64()).unwrap_or(0);
                        if rev == 0 {
                            past_debt_dates.push(date_str.to_string());
                        }
                    }
                }
            }
        }
        past_debt_dates.sort();

        // 2. Load {lang_code}:srs room
        let srs_room_name = format!("{lang_code}:srs");
        let (visual_srs_due, audio_srs_due, leech_words) = if let Some(srs_doc) = get_or_load_room_doc(state, &srs_room_name).await {
            let queue_map = srs_doc.get_or_insert_map("queue");
            let txn = srs_doc.transact();

            let mut vis_count = 0;
            let mut aud_count = 0;
            let mut leeches = Vec::new();

            for (_k, v) in queue_map.iter(&txn) {
                let json_str = v.to_string(&txn);
                if let Ok(card) = serde_json::from_str::<JsonValue>(&json_str) {
                    let card_type = card.get("card_type").and_then(|c| c.as_str()).unwrap_or("visual");
                    let due_date = card.get("due_date").and_then(|d| d.as_str()).unwrap_or("");
                    let ease = card.get("ease").and_then(|e| e.as_f64()).unwrap_or(2.5);
                    let native = card.get("native").and_then(|n| n.as_str()).unwrap_or("").to_string();

                    if due_date <= today_str && !due_date.is_empty() {
                        if card_type == "visual" {
                            vis_count += 1;
                        } else {
                            aud_count += 1;
                        }
                    }

                    if ease < 1.6 && !native.is_empty() && leeches.len() < 3 {
                        leeches.push(native);
                    }
                }
            }
            (vis_count, aud_count, leeches)
        } else {
            (0, 0, Vec::new())
        };

        // 3. Database Audits (After 15:00)
        let mut missing_voice_sessions = Vec::new();
        let mut unread_words = Vec::new();
        let mut incomplete_activities = Vec::new();

        if current_hour >= 15 && current_hour < 23 {
            // Check today's day room
            let today_room_name = format!("{lang_code}:{today_str}");
            if let Some(day_doc) = get_or_load_room_doc(state, &today_room_name).await {
                let words_arr = day_doc.get_or_insert_array("words");
                let acts_arr = day_doc.get_or_insert_array("activities");
                let txn = day_doc.transact();

                for v in words_arr.iter(&txn) {
                    let json_str = v.to_string(&txn);
                    if let Ok(val) = serde_json::from_str::<JsonValue>(&json_str) {
                        let word_items: Vec<JsonValue> = if val.is_array() {
                            val.as_array().cloned().unwrap_or_default()
                        } else {
                            vec![val]
                        };

                        for w in word_items {
                            let native = w.get("native_script").and_then(|s| s.as_str()).unwrap_or("");
                            let pron = w.get("pronunciation").and_then(|s| s.as_str()).unwrap_or("");
                            if !native.is_empty() && (pron.is_empty() || pron == native) && unread_words.len() < 3 {
                                unread_words.push(native.to_string());
                            }
                        }
                    }
                }

                for v in acts_arr.iter(&txn) {
                    let json_str = v.to_string(&txn);
                    if let Ok(val) = serde_json::from_str::<JsonValue>(&json_str) {
                        let act_items: Vec<JsonValue> = if val.is_array() {
                            val.as_array().cloned().unwrap_or_default()
                        } else {
                            vec![val]
                        };

                        for a in act_items {
                            let act_type = a.get("activity_type").and_then(|t| t.as_str()).unwrap_or("");
                            let link = a.get("link").and_then(|l| l.as_str()).unwrap_or("");
                            let link_dur = a.get("link_duration").and_then(|d| d.as_u64()).unwrap_or(0);

                            if act_type == "listening" && (link.is_empty() || link_dur == 0) && incomplete_activities.len() < 2 {
                                let idx = a.get("item_index").and_then(|i| i.as_u64()).unwrap_or(1);
                                incomplete_activities.push(format!("Listening #{idx}"));
                            }
                        }
                    }
                }
            }

            // Check past revisions >= 3 missing audio
            for (cal_key, cal_obj) in &cal_index_map {
                if cal_key.starts_with(&format!("{lang_code}:")) {
                    let rev = cal_obj.get("revision").and_then(|r| r.as_u64()).unwrap_or(0) as u32;
                    let date_str = cal_obj.get("date").and_then(|d| d.as_str()).unwrap_or("");
                    if rev >= 3 && !date_str.is_empty() && date_str < today_str {
                        let past_room = format!("{lang_code}:{date_str}");
                        if let Some(p_doc) = get_or_load_room_doc(state, &past_room).await {
                            let words_arr = p_doc.get_or_insert_array("words");
                            let txn = p_doc.transact();
                            let mut unvoiced = Vec::new();

                            for v in words_arr.iter(&txn) {
                                let json_str = v.to_string(&txn);
                                if let Ok(val) = serde_json::from_str::<JsonValue>(&json_str) {
                                    let word_items: Vec<JsonValue> = if val.is_array() {
                                        val.as_array().cloned().unwrap_or_default()
                                    } else {
                                        vec![val]
                                    };

                                    for w in word_items {
                                        let native = w.get("native_script").and_then(|s| s.as_str()).unwrap_or("");
                                        let audio_dur = w.get("audio_duration").and_then(|d| d.as_u64()).unwrap_or(0);
                                        if !native.is_empty() && audio_dur == 0 && unvoiced.len() < 4 {
                                            unvoiced.push(native.to_string());
                                        }
                                    }
                                }
                            }

                            if !unvoiced.is_empty() && missing_voice_sessions.len() < 2 {
                                missing_voice_sessions.push((date_str.to_string(), rev, unvoiced, 0));
                            }
                        }
                    }
                }
            }
        }

        snapshots.push(LanguageSnapshot {
            lang_code,
            current_streak,
            revisions_done,
            words_count,
            ci_count,
            listening_items,
            media_listening_mins,
            recorded_speaking_mins,
            past_debt_dates,
            visual_srs_due,
            audio_srs_due,
            missing_voice_sessions,
            unread_words,
            incomplete_activities,
            leech_words,
        });
    }

    snapshots
}

async fn evaluate_and_notify(
    state: &Arc<AppState>,
    today_str: &str,
    current_hour: u32,
    current_minute: u32,
    now_ts: i64,
    tracker: &Arc<Mutex<HashMap<String, i64>>>,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let snapshots = collect_snapshots(state, today_str, current_hour).await;

    for snap in snapshots {
        let lang_code = &snap.lang_code;

        // =====================================================================
        // PHASE 1: Morning Focus (Deadline: 12:00 PM)
        // Targets: 1 Rev, 10 Vocab, 1 CI, 2 Listening (>= 15m media listening)
        // =====================================================================
        if (7..12).contains(&current_hour) {
            if current_hour == 7 && current_minute >= 30 {
                let key = format!("{today_str}:morning_kickoff:{lang_code}");
                if can_send(tracker, &key, now_ts, 12 * 60).await {
                    let ev = NotificationEvent::MorningKickoff { language: lang_code.clone() };
                    broadcast_push(state, &ev.into_payload()).await;
                }
            }

            if current_hour >= 9 {
                let missing_rev = if snap.revisions_done >= 1 { 0 } else { 1 };
                let missing_vocab = 10u32.saturating_sub(snap.words_count);
                let missing_ci = if snap.ci_count >= 1 { 0 } else { 1 };
                let missing_listen_items = 2u32.saturating_sub(snap.listening_items);
                let missing_listen_mins = 15u32.saturating_sub(snap.media_listening_mins);

                if missing_rev > 0 || missing_vocab > 0 || missing_ci > 0 || missing_listen_mins > 0 {
                    let mins_until_noon = ((12 - current_hour) * 60).saturating_sub(current_minute);
                    let key = format!("{today_str}:morning_delta:{lang_code}");
                    if can_send(tracker, &key, now_ts, 45).await {
                        let ev = NotificationEvent::MorningProgressDelta {
                            language: lang_code.clone(),
                            missing_revisions: missing_rev,
                            missing_vocab,
                            missing_ci,
                            missing_listening_items: missing_listen_items,
                            missing_listening_mins: missing_listen_mins,
                            mins_until_noon,
                        };
                        broadcast_push(state, &ev.into_payload()).await;
                    }
                }
            }
        }

        // Post-12:00 PM Morning Debt Escalation
        if (12..14).contains(&current_hour) {
            let missing_vocab = 10u32.saturating_sub(snap.words_count);
            let missing_ci = if snap.ci_count >= 1 { 0 } else { 1 };
            let missing_listen_mins = 15u32.saturating_sub(snap.media_listening_mins);

            if missing_vocab > 0 || missing_ci > 0 || missing_listen_mins > 0 {
                let key = format!("{today_str}:morning_overdue:{lang_code}");
                if can_send(tracker, &key, now_ts, 60).await {
                    let ev = NotificationEvent::MorningOverdueDebt {
                        language: lang_code.clone(),
                        missing_vocab,
                        missing_ci,
                        missing_listening_mins: missing_listen_mins,
                    };
                    broadcast_push(state, &ev.into_payload()).await;
                }
            }
        }

        // =====================================================================
        // PHASE 2: Afternoon Momentum & Debt (Deadline: 06:00 PM)
        // Targets: 2nd Rev, +15m listening (>= 30m total), 10m speaking, Past Debt = 0
        // =====================================================================
        if (12..18).contains(&current_hour) {
            if current_hour == 13 && current_minute >= 30 {
                let key = format!("{today_str}:afternoon_kickoff:{lang_code}");
                if can_send(tracker, &key, now_ts, 12 * 60).await {
                    let ev = NotificationEvent::AfternoonKickoff {
                        language: lang_code.clone(),
                        past_debt_days: snap.past_debt_dates.len(),
                    };
                    broadcast_push(state, &ev.into_payload()).await;
                }
            }

            if (current_hour == 14 && current_minute >= 30) || current_hour >= 15 {
                let missing_rev = if snap.revisions_done >= 2 { 0 } else { 2 - snap.revisions_done };
                let missing_speaking = 10u32.saturating_sub(snap.recorded_speaking_mins);
                let missing_listening = 30u32.saturating_sub(snap.media_listening_mins);
                let has_past_debt = !snap.past_debt_dates.is_empty();

                if missing_rev > 0 || missing_speaking > 0 || missing_listening > 0 || has_past_debt {
                    let mins_until_six = ((18 - current_hour) * 60).saturating_sub(current_minute);
                    let key = format!("{today_str}:afternoon_delta:{lang_code}");
                    if can_send(tracker, &key, now_ts, 50).await {
                        let ev = NotificationEvent::AfternoonProgressDelta {
                            language: lang_code.clone(),
                            missing_revisions: missing_rev,
                            missing_speaking_mins: missing_speaking,
                            missing_listening_mins: missing_listening,
                            past_debt_dates: snap.past_debt_dates.clone(),
                            mins_until_six,
                        };
                        broadcast_push(state, &ev.into_payload()).await;
                    }
                }
            }

            // Output Imbalance Check
            if (16..=17).contains(&current_hour) && snap.media_listening_mins >= 30 && snap.recorded_speaking_mins < 10 {
                let key = format!("{today_str}:output_imbalance:{lang_code}");
                if can_send(tracker, &key, now_ts, 90).await {
                    let ev = NotificationEvent::OutputImbalanceWarning {
                        language: lang_code.clone(),
                        listening_mins: snap.media_listening_mins,
                        speaking_mins: snap.recorded_speaking_mins,
                        target_speaking_mins: 10,
                    };
                    broadcast_push(state, &ev.into_payload()).await;
                }
            }
        }

        // Post-6:00 PM Afternoon Debt Escalation
        if (18..20).contains(&current_hour) {
            let missing_speaking = 10u32.saturating_sub(snap.recorded_speaking_mins);
            let missing_listening = 30u32.saturating_sub(snap.media_listening_mins);
            let has_past_debt = !snap.past_debt_dates.is_empty();

            if missing_speaking > 0 || missing_listening > 0 || has_past_debt {
                let key = format!("{today_str}:afternoon_overdue:{lang_code}");
                if can_send(tracker, &key, now_ts, 60).await {
                    let ev = NotificationEvent::AfternoonOverdueDebt {
                        language: lang_code.clone(),
                        missing_speaking_mins: missing_speaking,
                        missing_listening_mins: missing_listening,
                        past_debt_dates: snap.past_debt_dates.clone(),
                    };
                    broadcast_push(state, &ev.into_payload()).await;
                }
            }
        }

        // =====================================================================
        // DATABASE AUDITS (Strictly Active After 03:00 PM / 15:00)
        // =====================================================================
        if current_hour >= 15 && current_hour < 23 {
            // 1. Missing Voice Audit
            for (date, rev, words, acts) in snap.missing_voice_sessions {
                let key = format!("{today_str}:voice_audit:{lang_code}:{date}");
                if can_send(tracker, &key, now_ts, 90).await {
                    let ev = NotificationEvent::MissingVoiceAudit {
                        language: lang_code.clone(),
                        date,
                        revision_number: rev,
                        missing_words: words,
                        missing_activities_count: acts,
                    };
                    broadcast_push(state, &ev.into_payload()).await;
                }
            }

            // 2. Missing Pronunciation Audit
            if !snap.unread_words.is_empty() {
                let key = format!("{today_str}:pron_audit:{lang_code}");
                if can_send(tracker, &key, now_ts, 120).await {
                    let ev = NotificationEvent::MissingPronunciationAudit {
                        language: lang_code.clone(),
                        date: today_str.to_string(),
                        untranscribed_words: snap.unread_words,
                    };
                    broadcast_push(state, &ev.into_payload()).await;
                }
            }

            // 3. Incomplete Activity Link Audit
            if !snap.incomplete_activities.is_empty() {
                let key = format!("{today_str}:link_audit:{lang_code}");
                if can_send(tracker, &key, now_ts, 120).await {
                    let ev = NotificationEvent::IncompleteActivityLinkAudit {
                        language: lang_code.clone(),
                        date: today_str.to_string(),
                        incomplete_items: snap.incomplete_activities,
                    };
                    broadcast_push(state, &ev.into_payload()).await;
                }
            }

            // 4. SRS Leech Word Warning
            if !snap.leech_words.is_empty() {
                let key = format!("{today_str}:leech_warning:{lang_code}");
                if can_send(tracker, &key, now_ts, 4 * 60).await {
                    let ev = NotificationEvent::SrsLeechWarning {
                        language: lang_code.clone(),
                        leech_words: snap.leech_words,
                    };
                    broadcast_push(state, &ev.into_payload()).await;
                }
            }

            // 5. Audio SRS Queue Backlog
            if snap.audio_srs_due >= 30 {
                let key = format!("{today_str}:audio_queue_backlog:{lang_code}");
                if can_send(tracker, &key, now_ts, 3 * 60).await {
                    let ev = NotificationEvent::AudioQueueBacklogNudge {
                        language: lang_code.clone(),
                        audio_cards_due: snap.audio_srs_due,
                    };
                    broadcast_push(state, &ev.into_payload()).await;
                }
            }
        }

        // =====================================================================
        // PHASE 3: Night Closeout (Deadline: 11:00 PM / 23:00)
        // Targets: 3rd Rev, 45m listening total, Visual SRS Queue = 0
        // =====================================================================
        if (18..23).contains(&current_hour) {
            if current_hour == 19 && current_minute >= 30 {
                let key = format!("{today_str}:night_kickoff:{lang_code}");
                if can_send(tracker, &key, now_ts, 12 * 60).await {
                    let ev = NotificationEvent::NightKickoff {
                        language: lang_code.clone(),
                        visual_srs_due: snap.visual_srs_due,
                    };
                    broadcast_push(state, &ev.into_payload()).await;
                }
            }

            if (current_hour == 20 && current_minute >= 30) || current_hour >= 21 {
                let missing_rev = if snap.revisions_done >= 3 { 0 } else { 3 - snap.revisions_done };
                let missing_listening = 45u32.saturating_sub(snap.media_listening_mins);

                if snap.visual_srs_due > 0 || missing_rev > 0 || missing_listening > 0 {
                    let mins_until_eleven = ((23 - current_hour) * 60).saturating_sub(current_minute);
                    let key = format!("{today_str}:night_delta:{lang_code}");
                    if can_send(tracker, &key, now_ts, 45).await {
                        let ev = NotificationEvent::NightProgressDelta {
                            language: lang_code.clone(),
                            missing_revisions: missing_rev,
                            missing_listening_mins: missing_listening,
                            visual_srs_due: snap.visual_srs_due,
                            mins_until_eleven,
                        };
                        broadcast_push(state, &ev.into_payload()).await;
                    }
                }
            }
        }

        // Post-11:00 PM Urgent Streak Warning
        if current_hour >= 23 && (snap.visual_srs_due > 0 || snap.revisions_done < 3) {
            let key = format!("{today_str}:night_overdue:{lang_code}");
            if can_send(tracker, &key, now_ts, 40).await {
                let ev = NotificationEvent::NightOverdueWarning {
                    language: lang_code.clone(),
                    visual_srs_due: snap.visual_srs_due,
                    current_streak: snap.current_streak,
                };
                broadcast_push(state, &ev.into_payload()).await;
            }
        }

        // Victory Lap (All 3 phases and visual queue cleared)
        let is_fully_completed = snap.revisions_done >= 3
            && snap.words_count >= 10
            && snap.ci_count >= 1
            && snap.media_listening_mins >= 45
            && snap.recorded_speaking_mins >= 10
            && snap.past_debt_dates.is_empty()
            && snap.visual_srs_due == 0;

        if is_fully_completed {
            let key = format!("{today_str}:victory_lap:{lang_code}");
            if can_send(tracker, &key, now_ts, 24 * 60).await {
                let ev = NotificationEvent::VictoryLap {
                    language: lang_code.clone(),
                    current_streak: snap.current_streak,
                };
                broadcast_push(state, &ev.into_payload()).await;
            }
        }
    }

    Ok(())
}