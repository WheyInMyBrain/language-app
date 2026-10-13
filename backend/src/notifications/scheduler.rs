use crate::notifications::{broadcast_push, NotificationEvent};
use crate::state::AppState;
use chrono::{Local, Timelike};
use rusqlite::params;
use serde_json::Value as JsonValue;
use std::collections::HashMap;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::Mutex;
use tracing::{error, info};

pub fn start_notification_worker(state: Arc<AppState>) {
    tokio::spawn(async move {
        info!(target: "scheduler", "Adaptive Momentum Notification worker started");

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

// 🌟 Half-Life EMA Calculation mirroring momentumEngine.js 🌟
fn calculate_ema(history: &[f64], baseline: f64, half_life_days: f64) -> f64 {
    if history.is_empty() {
        return baseline;
    }
    let alpha = 1.0 - (-std::f64::consts::LN_2 / half_life_days.max(0.5)).exp();
    let mut ema = history[0];
    for &val in &history[1..] {
        ema = alpha * val + (1.0 - alpha) * ema;
    }
    ema
}

struct LanguageSnapshot {
    lang_code: String,
    current_streak: u32,

    // Dynamic Goals for Today
    target_vocab: u32,
    target_listening_mins: u32,
    target_speaking_mins: u32,
    target_ci: u32,

    // Current Today Progress
    words_count: u32,
    ci_count: u32,
    listening_mins: u32,
    speaking_mins: u32,
    revisions_done_today: u32,

    // Completion Flags from daily_logs
    vocab_done: bool,
    ci_done: bool,
    listening_done: bool,
    speaking_done: bool,
    grammar_done: bool,

    // Tri-Deck SRS Backlog Counts
    visual_srs_due: usize,
    audio_srs_due: usize,
    write_srs_due: usize,
    leech_words: Vec<String>,

    // Prioritized Overdue Revisions (< today_str)
    overdue_revisions_count: usize,
    urgent_pass_zero_or_one_dates: Vec<String>,

    // Catch-Up Siphon Counts
    unvoiced_words_pending: usize,
}

async fn collect_snapshots(
    state: &Arc<AppState>,
    today_str: &str,
) -> Vec<LanguageSnapshot> {
    let state_clone = state.clone();
    let today = today_str.to_string();

    tokio::task::spawn_blocking(move || {
        let conn = state_clone.db_conn.lock().unwrap();
        let mut snapshots = Vec::new();

        // 1. Fetch all active languages
        let mut lang_stmt = match conn.prepare(
            "SELECT code, goals_json, momentum_json, current_streak \
             FROM languages WHERE deleted_at IS NULL",
        ) {
            Ok(stmt) => stmt,
            Err(_) => return snapshots,
        };

        let lang_rows = lang_stmt
            .query_map([], |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, String>(1)?,
                    row.get::<_, String>(2)?,
                    row.get::<_, u32>(3)?,
                ))
            })
            .ok();

        let languages: Vec<(String, String, String, u32)> = match lang_rows {
            Some(rows) => rows.filter_map(Result::ok).collect(),
            None => return snapshots,
        };

        for (lang_code, goals_json, momentum_json, current_streak) in languages {
            let goals: Option<JsonValue> = serde_json::from_str(&goals_json).ok();
            let mom: Option<JsonValue> = serde_json::from_str(&momentum_json).ok();

            let listen_base = mom.as_ref().and_then(|m| m.get("listening")).and_then(|l| l.get("baseline")).and_then(|v| v.as_f64())
                .or_else(|| goals.as_ref().and_then(|g| g.get("listening_minutes")).and_then(|v| v.as_f64())).unwrap_or(45.0);
            let listen_floor = mom.as_ref().and_then(|m| m.get("listening")).and_then(|l| l.get("floor")).and_then(|v| v.as_f64()).unwrap_or(20.0);
            let listen_ceil = mom.as_ref().and_then(|m| m.get("listening")).and_then(|l| l.get("ceiling")).and_then(|v| v.as_f64()).unwrap_or(90.0);

            let speak_base = mom.as_ref().and_then(|m| m.get("speaking")).and_then(|s| s.get("baseline")).and_then(|v| v.as_f64())
                .or_else(|| goals.as_ref().and_then(|g| g.get("speaking_minutes")).and_then(|v| v.as_f64())).unwrap_or(10.0);
            let speak_floor = mom.as_ref().and_then(|m| m.get("speaking")).and_then(|s| s.get("floor")).and_then(|v| v.as_f64()).unwrap_or(5.0);
            let speak_ceil = mom.as_ref().and_then(|m| m.get("speaking")).and_then(|s| s.get("ceiling")).and_then(|v| v.as_f64()).unwrap_or(25.0);

            let vocab_base = mom.as_ref().and_then(|m| m.get("vocab")).and_then(|w| w.get("baseline")).and_then(|v| v.as_f64())
                .or_else(|| goals.as_ref().and_then(|g| g.get("vocab")).and_then(|v| v.as_f64())).unwrap_or(5.0);
            let vocab_floor = mom.as_ref().and_then(|m| m.get("vocab")).and_then(|w| w.get("floor")).and_then(|v| v.as_f64()).unwrap_or(2.0);
            let vocab_ceil = mom.as_ref().and_then(|m| m.get("vocab")).and_then(|w| w.get("ceiling")).and_then(|v| v.as_f64()).unwrap_or(10.0).min(10.0);

            // 2. Fetch past daily logs for history and debt calculations
            let mut past_listen_history = Vec::new();
            let mut past_speak_history = Vec::new();
            let mut past_vocab_history = Vec::new();

            let mut unvoiced_words_pending = 0;
            let mut overdue_revisions_count = 0;
            let mut urgent_pass_zero_or_one_dates = Vec::new();

            if let Ok(mut logs_stmt) = conn.prepare(
                "SELECT log_date, due_date, revision, unvoiced_words_json \
                 FROM daily_logs \
                 WHERE lang_code = ?1 AND log_date < ?2 AND deleted_at IS NULL \
                 ORDER BY log_date DESC",
            ) {
                if let Ok(rows) = logs_stmt.query_map(params![lang_code, today], |row| {
                    Ok((
                        row.get::<_, String>(0)?,
                        row.get::<_, Option<String>>(1)?,
                        row.get::<_, u32>(2)?,
                        row.get::<_, String>(3)?,
                    ))
                }) {
                    for (date_str, due_date_opt, rev, unvoiced_json) in rows.flatten() {
                        let due_date = due_date_opt.unwrap_or_else(|| date_str.clone());
                        if due_date <= today || rev == 0 {
                            overdue_revisions_count += 1;
                            if rev <= 1 && urgent_pass_zero_or_one_dates.len() < 3 {
                                urgent_pass_zero_or_one_dates.push(date_str);
                            }
                        }

                        if let Ok(arr) = serde_json::from_str::<Vec<JsonValue>>(&unvoiced_json) {
                            unvoiced_words_pending += arr.len();
                        }
                    }
                }
            }

            // Gather recent audio/word counts from words & activities for EMA inputs
            if let Ok(mut words_hist_stmt) = conn.prepare(
                "SELECT COUNT(*) FROM words \
                 WHERE lang_code = ?1 AND log_date < ?2 AND deleted_at IS NULL \
                 GROUP BY log_date ORDER BY log_date DESC LIMIT 14",
            ) {
                if let Ok(rows) = words_hist_stmt.query_map(params![lang_code, today], |row| row.get::<_, f64>(0)) {
                    past_vocab_history = rows.flatten().collect();
                }
            }

            if let Ok(mut act_hist_stmt) = conn.prepare(
                "SELECT activity_type, SUM(link_duration), SUM(audio_duration) \
                 FROM activities \
                 WHERE lang_code = ?1 AND log_date < ?2 AND deleted_at IS NULL \
                 GROUP BY log_date, activity_type ORDER BY log_date DESC LIMIT 28",
            ) {
                if let Ok(rows) = act_hist_stmt.query_map(params![lang_code, today], |row| {
                    Ok((
                        row.get::<_, String>(0)?,
                        row.get::<_, f64>(1)?,
                        row.get::<_, f64>(2)?,
                    ))
                }) {
                    for (act_type, link_dur, audio_dur) in rows.flatten() {
                        if act_type == "ci" || act_type == "listening" {
                            past_listen_history.push(link_dur / 60.0);
                        }
                        if audio_dur > 0.0 {
                            past_speak_history.push(audio_dur / 60.0);
                        }
                    }
                }
            }

            // Calculate dynamic targets
            let ema_listen = calculate_ema(&past_listen_history, listen_base, 2.5);
            let ema_speak = calculate_ema(&past_speak_history, speak_base, 2.5);
            let ema_vocab = calculate_ema(&past_vocab_history, vocab_base, 2.5);

            let target_listening_mins = (ema_listen.round() as u32).clamp(listen_floor as u32, listen_ceil as u32);
            let target_speaking_mins = (ema_speak.round() as u32).clamp(speak_floor as u32, speak_ceil as u32);
            let target_vocab = (ema_vocab.round() as u32).clamp(vocab_floor as u32, vocab_ceil as u32);
            let target_ci = goals.as_ref().and_then(|g| g.get("ci")).and_then(|v| v.as_u64()).unwrap_or(1) as u32;

            // 3. Today's current progress from daily_logs, words, and activities
            let (revisions_done_today, vocab_done, ci_done, listening_done, speaking_done, grammar_done) = conn
                .query_row(
                    "SELECT revisions_done, vocab_done, ci_done, listening_done, speaking_done, grammar_done \
                     FROM daily_logs WHERE lang_code = ?1 AND log_date = ?2",
                    params![lang_code, today],
                    |row| {
                        Ok((
                            row.get::<_, u32>(0)?,
                            row.get::<_, i64>(1)? > 0,
                            row.get::<_, i64>(2)? > 0,
                            row.get::<_, i64>(3)? > 0,
                            row.get::<_, i64>(4)? > 0,
                            row.get::<_, i64>(5)? > 0,
                        ))
                    },
                )
                .unwrap_or((0, false, false, false, false, false));

            let words_count: u32 = conn
                .query_row(
                    "SELECT COUNT(*) FROM words WHERE lang_code = ?1 AND log_date = ?2 AND deleted_at IS NULL",
                    params![lang_code, today],
                    |row| row.get(0),
                )
                .unwrap_or(0);

            let ci_count: u32 = conn
                .query_row(
                    "SELECT COUNT(*) FROM activities WHERE lang_code = ?1 AND log_date = ?2 AND activity_type = 'ci' AND deleted_at IS NULL",
                    params![lang_code, today],
                    |row| row.get(0),
                )
                .unwrap_or(0);

            let listening_sec: f64 = conn
                .query_row(
                    "SELECT COALESCE(SUM(link_duration), 0.0) FROM activities \
                     WHERE lang_code = ?1 AND log_date = ?2 AND (activity_type = 'listening' OR activity_type = 'ci') AND deleted_at IS NULL",
                    params![lang_code, today],
                    |row| row.get(0),
                )
                .unwrap_or(0.0);

            let speaking_sec: f64 = conn
                .query_row(
                    "SELECT COALESCE( \
                        (SELECT SUM(audio_duration) FROM words WHERE lang_code = ?1 AND log_date = ?2 AND deleted_at IS NULL), 0.0 \
                     ) + COALESCE( \
                        (SELECT SUM(audio_duration) FROM activities WHERE lang_code = ?1 AND log_date = ?2 AND deleted_at IS NULL), 0.0 \
                     )",
                    params![lang_code, today],
                    |row| row.get(0),
                )
                .unwrap_or(0.0);

            // 4. Tri-Deck SRS Backlog & Leeches from `word_srs` table
            let mut visual_srs_due = 0;
            let mut audio_srs_due = 0;
            let mut write_srs_due = 0;
            let mut leech_words = Vec::new();

            if let Ok(mut srs_stmt) = conn.prepare(
                "SELECT card_type, native_script, lapses \
                 FROM word_srs \
                 WHERE lang_code = ?1 AND due_date <= ?2 AND deleted_at IS NULL",
            ) {
                if let Ok(rows) = srs_stmt.query_map(params![lang_code, today], |row| {
                    Ok((
                        row.get::<_, String>(0)?,
                        row.get::<_, String>(1)?,
                        row.get::<_, u32>(2)?,
                    ))
                }) {
                    for (card_type, native, lapses) in rows.flatten() {
                        match card_type.as_str() {
                            "listening" | "audio" => audio_srs_due += 1,
                            "writing" => write_srs_due += 1,
                            _ => visual_srs_due += 1,
                        }

                        if lapses >= 3 && !native.is_empty() && leech_words.len() < 3 {
                            leech_words.push(native);
                        }
                    }
                }
            }

            snapshots.push(LanguageSnapshot {
                lang_code,
                current_streak,
                target_vocab,
                target_listening_mins,
                target_speaking_mins,
                target_ci,
                words_count,
                ci_count,
                listening_mins: (listening_sec / 60.0).round() as u32,
                speaking_mins: (speaking_sec / 60.0).round() as u32,
                revisions_done_today,
                vocab_done: vocab_done || words_count >= target_vocab,
                ci_done: ci_done || ci_count >= target_ci,
                listening_done: listening_done || (listening_sec / 60.0) >= target_listening_mins as f64,
                speaking_done: speaking_done || (speaking_sec / 60.0) >= target_speaking_mins as f64,
                grammar_done,
                visual_srs_due,
                audio_srs_due,
                write_srs_due,
                leech_words,
                overdue_revisions_count,
                urgent_pass_zero_or_one_dates,
                unvoiced_words_pending,
            });
        }

        snapshots
    })
    .await
    .unwrap_or_default()
}

async fn evaluate_and_notify(
    state: &Arc<AppState>,
    today_str: &str,
    current_hour: u32,
    current_minute: u32,
    now_ts: i64,
    tracker: &Arc<Mutex<HashMap<String, i64>>>,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let snapshots = collect_snapshots(state, today_str).await;

    for snap in snapshots {
        let lang_code = &snap.lang_code;

        // =====================================================================
        // PHASE 1: Morning Focus (Kickoff & Momentum Guidance)
        // =====================================================================
        if (7..12).contains(&current_hour) {
            if current_hour == 7 && current_minute >= 30 {
                let key = format!("{today_str}:morning_kickoff:{lang_code}");
                if can_send(tracker, &key, now_ts, 12 * 60).await {
                    let ev = NotificationEvent::MorningKickoff {
                        language: lang_code.clone(),
                        target_vocab: snap.target_vocab,
                        target_ci: snap.target_ci,
                        target_listening_mins: snap.target_listening_mins,
                    };
                    broadcast_push(state, &ev.into_payload()).await;
                }
            }

            if current_hour >= 9 {
                let missing_vocab = snap.target_vocab.saturating_sub(snap.words_count);
                let missing_ci = snap.target_ci.saturating_sub(snap.ci_count);
                let half_listening = (snap.target_listening_mins / 2).max(10);
                let missing_listen_mins = half_listening.saturating_sub(snap.listening_mins);

                if !snap.vocab_done || !snap.ci_done || missing_listen_mins > 0 {
                    let mins_until_noon = ((12 - current_hour) * 60).saturating_sub(current_minute);
                    let key = format!("{today_str}:morning_delta:{lang_code}");
                    if can_send(tracker, &key, now_ts, 45).await {
                        let ev = NotificationEvent::MorningProgressDelta {
                            language: lang_code.clone(),
                            missing_revisions: if snap.revisions_done_today > 0 { 0 } else { 1 },
                            missing_vocab,
                            missing_ci,
                            missing_listening_items: 1,
                            missing_listening_mins: missing_listen_mins,
                            mins_until_noon,
                        };
                        broadcast_push(state, &ev.into_payload()).await;
                    }
                }
            }
        }

        // =====================================================================
        // PHASE 2: Afternoon Momentum & Siphon Alert (12:00 - 18:00)
        // =====================================================================
        if (12..18).contains(&current_hour) {
            if current_hour == 13 && current_minute >= 30 {
                let key = format!("{today_str}:afternoon_kickoff:{lang_code}");
                if can_send(tracker, &key, now_ts, 12 * 60).await {
                    let ev = NotificationEvent::AfternoonKickoff {
                        language: lang_code.clone(),
                        past_debt_days: snap.overdue_revisions_count,
                    };
                    broadcast_push(state, &ev.into_payload()).await;
                }
            }

            if current_hour >= 15 {
                let missing_speaking = snap.target_speaking_mins.saturating_sub(snap.speaking_mins);
                let missing_listening = snap.target_listening_mins.saturating_sub(snap.listening_mins);

                if !snap.speaking_done || !snap.listening_done || snap.overdue_revisions_count > 0 {
                    let mins_until_six = ((18 - current_hour) * 60).saturating_sub(current_minute);
                    let key = format!("{today_str}:afternoon_delta:{lang_code}");
                    if can_send(tracker, &key, now_ts, 50).await {
                        let ev = NotificationEvent::AfternoonProgressDelta {
                            language: lang_code.clone(),
                            missing_revisions: if snap.revisions_done_today >= 1 { 0 } else { 1 },
                            missing_speaking_mins: missing_speaking,
                            missing_listening_mins: missing_listening,
                            past_debt_dates: snap.urgent_pass_zero_or_one_dates.clone(),
                            mins_until_six,
                        };
                        broadcast_push(state, &ev.into_payload()).await;
                    }
                }
            }

            // Output Imbalance Check (Listening is high, but speaking is neglected)
            if (16..=17).contains(&current_hour) && snap.listening_mins >= (snap.target_listening_mins / 2) && !snap.speaking_done {
                let key = format!("{today_str}:output_imbalance:{lang_code}");
                if can_send(tracker, &key, now_ts, 90).await {
                    let ev = NotificationEvent::OutputImbalanceWarning {
                        language: lang_code.clone(),
                        listening_mins: snap.listening_mins,
                        speaking_mins: snap.speaking_mins,
                        target_speaking_mins: snap.target_speaking_mins,
                    };
                    broadcast_push(state, &ev.into_payload()).await;
                }
            }
        }

        // =====================================================================
        // AUDITS & SIPHON ALERTS (Strictly After 15:00)
        // =====================================================================
        if current_hour >= 15 && current_hour < 23 {
            // 1. Unvoiced Words Siphon Alert
            if snap.unvoiced_words_pending > 0 {
                let key = format!("{today_str}:voice_siphon:{lang_code}");
                if can_send(tracker, &key, now_ts, 120).await {
                    let surfaced = snap.unvoiced_words_pending.min(5);
                    let buffered = snap.unvoiced_words_pending.saturating_sub(surfaced);
                    let ev = NotificationEvent::VocalSiphonBatchNudge {
                        language: lang_code.clone(),
                        surfaced_count: surfaced,
                        buffered_count: buffered,
                    };
                    broadcast_push(state, &ev.into_payload()).await;
                }
            }

            // 2. SRS Leech Word Warning (Persistent lapses >= 3)
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

            // 3. Audio SRS Backlog Nudge
            if snap.audio_srs_due >= 20 {
                let key = format!("{today_str}:audio_queue_backlog:{lang_code}");
                if can_send(tracker, &key, now_ts, 3 * 60).await {
                    let ev = NotificationEvent::AudioQueueBacklogNudge {
                        language: lang_code.clone(),
                        audio_cards_due: snap.audio_srs_due,
                    };
                    broadcast_push(state, &ev.into_payload()).await;
                }
            }

            // 4. Writing SRS Backlog Nudge
            if snap.write_srs_due >= 5 {
                let key = format!("{today_str}:write_queue_backlog:{lang_code}");
                if can_send(tracker, &key, now_ts, 4 * 60).await {
                    let ev = NotificationEvent::WritingQueueBacklogNudge {
                        language: lang_code.clone(),
                        writing_cards_due: snap.write_srs_due,
                    };
                    broadcast_push(state, &ev.into_payload()).await;
                }
            }
        }

        // =====================================================================
        // PHASE 3: Night Closeout (18:00 - 23:00)
        // =====================================================================
        if (18..23).contains(&current_hour) {
            let total_srs_due = snap.visual_srs_due + snap.audio_srs_due + snap.write_srs_due;

            if current_hour == 19 && current_minute >= 30 {
                let key = format!("{today_str}:night_kickoff:{lang_code}");
                if can_send(tracker, &key, now_ts, 12 * 60).await {
                    let ev = NotificationEvent::NightKickoff {
                        language: lang_code.clone(),
                        visual_srs_due: total_srs_due,
                    };
                    broadcast_push(state, &ev.into_payload()).await;
                }
            }

            if (current_hour == 20 && current_minute >= 30) || current_hour >= 21 {
                let missing_listening = snap.target_listening_mins.saturating_sub(snap.listening_mins);
                let missing_speaking = snap.target_speaking_mins.saturating_sub(snap.speaking_mins);

                if total_srs_due > 0 || missing_listening > 0 || missing_speaking > 0 || !snap.vocab_done {
                    let mins_until_eleven = ((23 - current_hour) * 60).saturating_sub(current_minute);
                    let key = format!("{today_str}:night_delta:{lang_code}");
                    if can_send(tracker, &key, now_ts, 45).await {
                        let ev = NotificationEvent::NightProgressDelta {
                            language: lang_code.clone(),
                            missing_revisions: if snap.revisions_done_today > 0 { 0 } else { 1 },
                            missing_listening_mins: missing_listening,
                            visual_srs_due: total_srs_due,
                            mins_until_eleven,
                        };
                        broadcast_push(state, &ev.into_payload()).await;
                    }
                }
            }
        }

        // Urgent Streak Closeout (Past 23:00)
        if current_hour >= 23 {
            let total_srs_due = snap.visual_srs_due + snap.audio_srs_due + snap.write_srs_due;
            if total_srs_due > 0 || !snap.listening_done || !snap.vocab_done {
                let key = format!("{today_str}:night_overdue:{lang_code}");
                if can_send(tracker, &key, now_ts, 40).await {
                    let ev = NotificationEvent::NightOverdueWarning {
                        language: lang_code.clone(),
                        visual_srs_due: total_srs_due,
                        current_streak: snap.current_streak,
                    };
                    broadcast_push(state, &ev.into_payload()).await;
                }
            }
        }

        // 🌟 VICTORY LAP 🌟
        let all_goals_met = snap.vocab_done 
            && snap.ci_done 
            && snap.listening_done 
            && snap.speaking_done 
            && snap.grammar_done;

        let srs_clear = (snap.visual_srs_due + snap.audio_srs_due + snap.write_srs_due) == 0;

        if all_goals_met && srs_clear {
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