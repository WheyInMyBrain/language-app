use rand::seq::IndexedRandom;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NotificationPayload {
    pub title: String,
    pub body: String,
    pub url: String,
    pub tag: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", content = "data")]
pub enum NotificationEvent {
    // =========================================================================
    // PHASE 1: Morning Focus (Kickoff & Momentum Guidance)
    // =========================================================================
    MorningKickoff {
        language: String,
        target_vocab: u32,
        target_ci: u32,
        target_listening_mins: u32,
    },
    MorningProgressDelta {
        language: String,
        missing_revisions: u32,
        missing_vocab: u32,
        missing_ci: u32,
        missing_listening_items: u32,
        missing_listening_mins: u32,
        mins_until_noon: u32,
    },
    MorningOverdueDebt {
        language: String,
        missing_vocab: u32,
        missing_ci: u32,
        missing_listening_mins: u32,
    },

    // =========================================================================
    // PHASE 2: Afternoon Momentum & Siphon Alert (12:00 - 18:00)
    // =========================================================================
    AfternoonKickoff {
        language: String,
        past_debt_days: usize,
    },
    AfternoonProgressDelta {
        language: String,
        missing_revisions: u32,
        missing_speaking_mins: u32,
        missing_listening_mins: u32,
        past_debt_dates: Vec<String>,
        mins_until_six: u32,
    },
    AfternoonOverdueDebt {
        language: String,
        missing_speaking_mins: u32,
        missing_listening_mins: u32,
        past_debt_dates: Vec<String>,
    },
    OutputImbalanceWarning {
        language: String,
        listening_mins: u32,
        speaking_mins: u32,
        target_speaking_mins: u32,
    },

    // =========================================================================
    // AUDITS & SIPHON ALERTS (Strictly After 03:00 PM)
    // =========================================================================
    MissingVoiceAudit {
        language: String,
        date: String,
        revision_number: u32,
        missing_words: Vec<String>,
        missing_activities_count: usize,
    },
    VocalSiphonBatchNudge {
        language: String,
        surfaced_count: usize,
        buffered_count: usize,
    },
    MissingPronunciationAudit {
        language: String,
        date: String,
        untranscribed_words: Vec<String>,
    },
    IncompleteActivityLinkAudit {
        language: String,
        date: String,
        incomplete_items: Vec<String>,
    },
    SrsLeechWarning {
        language: String,
        leech_words: Vec<String>,
    },
    AudioQueueBacklogNudge {
        language: String,
        audio_cards_due: usize,
    },
    WritingQueueBacklogNudge {
        language: String,
        writing_cards_due: usize,
    },

    // =========================================================================
    // PHASE 3: Night Closeout (18:00 - 23:00)
    // =========================================================================
    NightKickoff {
        language: String,
        visual_srs_due: usize,
    },
    NightProgressDelta {
        language: String,
        missing_revisions: u32,
        missing_listening_mins: u32,
        visual_srs_due: usize,
        mins_until_eleven: u32,
    },
    NightOverdueWarning {
        language: String,
        visual_srs_due: usize,
        current_streak: u32,
    },

    // =========================================================================
    // MILESTONES & SYSTEM
    // =========================================================================
    VictoryLap {
        language: String,
        current_streak: u32,
    },
    SystemPing {
        message: String,
    },
}

impl NotificationEvent {
    pub fn into_payload(self) -> NotificationPayload {
        let mut rng = rand::rng();

        match self {
            // -----------------------------------------------------------------
            // Morning Kickoff (Adaptive targets injected)
            // -----------------------------------------------------------------
            Self::MorningKickoff {
                language,
                target_vocab,
                target_ci,
                target_listening_mins,
            } => {
                let titles = [
                    format!("Morning Blueprint: {language} 🌅"),
                    format!("Today's Adaptive Target ({language}) 🎯"),
                    "Daybreak Quota Active ⏱️".to_string(),
                    format!("Rise & Input: {language} ☕"),
                ];
                let bodies = [
                    format!("Today's focus: {target_vocab} new words, {target_ci} CI session, and {target_listening_mins}m immersion audio."),
                    format!("Frontload your morning: knock out {target_vocab} vocab and your {target_listening_mins}m listening target before lunch!"),
                    format!("Cognitive window open: aim for {target_vocab} words, {target_ci} CI pass, and {target_listening_mins}m audio today."),
                    format!("Fresh day ahead: complete your morning batch ({target_vocab} words, {target_ci} CI entry)."),
                ];

                NotificationPayload {
                    title: titles.choose(&mut rng).cloned().unwrap(),
                    body: bodies.choose(&mut rng).cloned().unwrap(),
                    url: format!("/log/{language}"),
                    tag: format!("morning-kickoff-{language}"),
                }
            }

            // -----------------------------------------------------------------
            // Morning Progress Delta
            // -----------------------------------------------------------------
            Self::MorningProgressDelta {
                language,
                missing_revisions,
                missing_vocab,
                missing_ci,
                missing_listening_items: _,
                missing_listening_mins,
                mins_until_noon,
            } => {
                let mut delta_parts = Vec::new();
                if missing_revisions > 0 {
                    delta_parts.push(format!("{missing_revisions} rev"));
                }
                if missing_vocab > 0 {
                    delta_parts.push(format!("{missing_vocab} vocab"));
                }
                if missing_ci > 0 {
                    delta_parts.push(format!("{missing_ci} CI"));
                }
                if missing_listening_mins > 0 {
                    delta_parts.push(format!("{missing_listening_mins}m media listening"));
                }
                let delta_str = delta_parts.join(", ");

                let titles = [
                    format!("{mins_until_noon}m to Midday Target ⏳"),
                    format!("Pacing Check ({language}) 📋"),
                    "Keep the Morning Rolling 🏃".to_string(),
                ];

                let bodies = [
                    format!("Still needed for your morning block: {delta_str}. Knock this out now!"),
                    format!("{mins_until_noon} minutes remain before noon: {delta_str} pending."),
                    format!("Protect your afternoon momentum. Complete: {delta_str}."),
                ];

                NotificationPayload {
                    title: titles.choose(&mut rng).cloned().unwrap(),
                    body: bodies.choose(&mut rng).cloned().unwrap(),
                    url: format!("/log/{language}"),
                    tag: format!("morning-delta-{language}"),
                }
            }

            // -----------------------------------------------------------------
            // Morning Overdue Debt
            // -----------------------------------------------------------------
            Self::MorningOverdueDebt {
                language,
                missing_vocab,
                missing_ci,
                missing_listening_mins,
            } => {
                let mut items = Vec::new();
                if missing_vocab > 0 {
                    items.push(format!("{missing_vocab} vocab"));
                }
                if missing_ci > 0 {
                    items.push(format!("{missing_ci} CI"));
                }
                if missing_listening_mins > 0 {
                    items.push(format!("{missing_listening_mins}m listening"));
                }
                let items_str = items.join(", ");

                let titles = [
                    format!("Midday Quota Check ({language}) ⚠️"),
                    "Morning Input Unfinished 🚨".to_string(),
                    "Pending Morning Tasks 📉".to_string(),
                ];
                let bodies = [
                    format!("Morning session still open: {items_str}. Clear this before afternoon output begins!"),
                    format!("Don't let targets stack up: {items_str} remain open."),
                ];

                NotificationPayload {
                    title: titles.choose(&mut rng).cloned().unwrap(),
                    body: bodies.choose(&mut rng).cloned().unwrap(),
                    url: format!("/log/{language}"),
                    tag: format!("morning-overdue-{language}"),
                }
            }

            // -----------------------------------------------------------------
            // Afternoon Kickoff
            // -----------------------------------------------------------------
            Self::AfternoonKickoff {
                language,
                past_debt_days,
            } => {
                let debt_msg = if past_debt_days > 0 {
                    format!(" Note: you have {past_debt_days} prioritized overdue revision(s) due today.")
                } else {
                    "".to_string()
                };

                let titles = [
                    format!("Afternoon Block Active: {language} ⚡"),
                    "Vocal Activation Window 🎙️".to_string(),
                    format!("Phase 2 Underway ({language}) 🚀"),
                ];
                let bodies = [
                    format!("Afternoon targets: vocal shadowing and priority DayPage reviews.{debt_msg}"),
                    format!("Time for vocal output! Record your speech and clear overdue revisions.{debt_msg}"),
                ];

                NotificationPayload {
                    title: titles.choose(&mut rng).cloned().unwrap(),
                    body: bodies.choose(&mut rng).cloned().unwrap(),
                    url: format!("/log/{language}"),
                    tag: format!("afternoon-kickoff-{language}"),
                }
            }

            // -----------------------------------------------------------------
            // Afternoon Progress Delta
            // -----------------------------------------------------------------
            Self::AfternoonProgressDelta {
                language,
                missing_revisions,
                missing_speaking_mins,
                missing_listening_mins,
                past_debt_dates,
                mins_until_six,
            } => {
                let mut tasks = Vec::new();
                if missing_revisions > 0 {
                    tasks.push("Today's Day Revision".to_string());
                }
                if missing_speaking_mins > 0 {
                    tasks.push(format!("{missing_speaking_mins}m speech recording"));
                }
                if missing_listening_mins > 0 {
                    tasks.push(format!("{missing_listening_mins}m listening"));
                }
                if !past_debt_dates.is_empty() {
                    let first_date = &past_debt_dates[0];
                    let more = past_debt_dates.len().saturating_sub(1);
                    if more > 0 {
                        tasks.push(format!("overdue {first_date} (+{more} days)"));
                    } else {
                        tasks.push(format!("overdue {first_date}"));
                    }
                }
                let tasks_str = tasks.join(", ");

                let titles = [
                    format!("{mins_until_six}m to Evening Pacing Mark ⏳"),
                    format!("Afternoon Check ({language}) 📊"),
                    "Prioritize Acute Revisions 🛡️".to_string(),
                ];
                let bodies = [
                    format!("Pending items before evening: {tasks_str}. Record speech and clear Pass 0/1 revisions!"),
                    format!("{mins_until_six} minutes left in afternoon block: {tasks_str} remaining."),
                ];

                let target_url = if let Some(old_date) = past_debt_dates.first() {
                    format!("/log/{language}/{old_date}")
                } else {
                    format!("/log/{language}")
                };

                NotificationPayload {
                    title: titles.choose(&mut rng).cloned().unwrap(),
                    body: bodies.choose(&mut rng).cloned().unwrap(),
                    url: target_url,
                    tag: format!("afternoon-delta-{language}"),
                }
            }

            // -----------------------------------------------------------------
            // Afternoon Overdue Debt
            // -----------------------------------------------------------------
            Self::AfternoonOverdueDebt {
                language,
                missing_speaking_mins,
                missing_listening_mins,
                past_debt_dates,
            } => {
                let mut debt_items = Vec::new();
                if missing_speaking_mins > 0 {
                    debt_items.push(format!("{missing_speaking_mins}m speech"));
                }
                if missing_listening_mins > 0 {
                    debt_items.push(format!("{missing_listening_mins}m listening"));
                }
                if !past_debt_dates.is_empty() {
                    debt_items.push(format!("revisions: {}", past_debt_dates.join(", ")));
                }
                let debt_str = debt_items.join(" + ");

                let titles = [
                    format!("Evening Approaching: Open Tasks ({language}) 🚨"),
                    "Phase 2 Outstanding Tasks ⚠️".to_string(),
                ];
                let bodies = [
                    format!("Outstanding items: {debt_str}. Complete them to keep your evening light!"),
                    format!("Pending backlog: {debt_str}. A short sprint clears this before night reviews."),
                ];

                let target_url = if let Some(old_date) = past_debt_dates.first() {
                    format!("/log/{language}/{old_date}")
                } else {
                    format!("/log/{language}")
                };

                NotificationPayload {
                    title: titles.choose(&mut rng).cloned().unwrap(),
                    body: bodies.choose(&mut rng).cloned().unwrap(),
                    url: target_url,
                    tag: format!("afternoon-overdue-{language}"),
                }
            }

            // -----------------------------------------------------------------
            // Output Imbalance Warning
            // -----------------------------------------------------------------
            Self::OutputImbalanceWarning {
                language,
                listening_mins,
                speaking_mins,
                target_speaking_mins,
            } => {
                let titles = [
                    format!("Output Deficit: {language} 🎙️"),
                    "Input / Output Imbalance ⚖️".to_string(),
                    "Vocal Activation Needed 🗣️".to_string(),
                ];
                let bodies = [
                    format!("You logged {listening_mins}m of media listening, but only {speaking_mins}/{target_speaking_mins}m speaking. Record your shadowing now!"),
                    format!("Passive input is high ({listening_mins}m), but active voice is lagging. Complete {target_speaking_mins}m recording to balance your loop."),
                ];

                NotificationPayload {
                    title: titles.choose(&mut rng).cloned().unwrap(),
                    body: bodies.choose(&mut rng).cloned().unwrap(),
                    url: format!("/log/{language}"),
                    tag: format!("output-imbalance-{language}"),
                }
            }

            // -----------------------------------------------------------------
            // Missing Voice Audit (Legacy fallback)
            // -----------------------------------------------------------------
            Self::MissingVoiceAudit {
                language,
                date,
                revision_number,
                missing_words,
                missing_activities_count: _,
            } => {
                let titles = [
                    format!("Vocal Catch-Up: {language} 🎙️"),
                    "Audio Siphon Sprint Available 🔊".to_string(),
                ];
                let word_info = missing_words.first().cloned().unwrap_or_else(|| "Words pending audio".to_string());
                let bodies = [
                    format!("Daily Catch-Up batch: {word_info}. Clear them in a 60-second vocal sprint!"),
                    format!("Audio artifacts pending for {date} (Pass #{revision_number}): {word_info}."),
                ];

                NotificationPayload {
                    title: titles.choose(&mut rng).cloned().unwrap(),
                    body: bodies.choose(&mut rng).cloned().unwrap(),
                    url: format!("/log/{language}/{date}"),
                    tag: format!("voice-audit-{language}-{date}"),
                }
            }

            // -----------------------------------------------------------------
            // 🌟 NEW: Vocal Siphon Batch Nudge (Engine 2 Metered Catch-Up) 🌟
            // -----------------------------------------------------------------
            Self::VocalSiphonBatchNudge {
                language,
                surfaced_count,
                buffered_count,
            } => {
                let buffer_str = if buffered_count > 0 {
                    format!(" (+{buffered_count} buffered in background)")
                } else {
                    "".to_string()
                };

                let titles = [
                    format!("🎙️ Vocal Sprint: {surfaced_count} Words Ready ({language})"),
                    "Quick Audio Catch-Up ⚡".to_string(),
                    "60-Second Pronunciation Siphon 🗣️".to_string(),
                ];
                let bodies = [
                    format!("Your adaptive siphon surfaced {surfaced_count} unvoiced words{buffer_str}. Tap to record audio and clear the batch!"),
                    format!("Quick vocal sprint: {surfaced_count} words need audio recordings{buffer_str}. Knock them out in 1 minute!"),
                ];

                NotificationPayload {
                    title: titles.choose(&mut rng).cloned().unwrap(),
                    body: bodies.choose(&mut rng).cloned().unwrap(),
                    url: format!("/log/{language}"),
                    tag: format!("vocal-siphon-{language}"),
                }
            }

            // -----------------------------------------------------------------
            // Missing Pronunciation / Reading Audit
            // -----------------------------------------------------------------
            Self::MissingPronunciationAudit {
                language,
                date,
                untranscribed_words,
            } => {
                let preview = untranscribed_words.join(", ");
                let titles = [
                    format!("Phonetic Gap: {language} ({date}) 🔤"),
                    "Missing Pronunciation Readings 📝".to_string(),
                ];
                let bodies = [
                    format!("Words logged on {date} lack readings: [{preview}]. Add phonetic transcriptions to activate SRS cards!"),
                    format!("Complete vocabulary card data: [{preview}] missing pronunciation on {date}."),
                ];

                NotificationPayload {
                    title: titles.choose(&mut rng).cloned().unwrap(),
                    body: bodies.choose(&mut rng).cloned().unwrap(),
                    url: format!("/log/{language}/{date}"),
                    tag: format!("pronunciation-audit-{language}-{date}"),
                }
            }

            // -----------------------------------------------------------------
            // Incomplete Activity Link / Duration Audit
            // -----------------------------------------------------------------
            Self::IncompleteActivityLinkAudit {
                language,
                date,
                incomplete_items,
            } => {
                let preview = incomplete_items.join(", ");
                let titles = [
                    format!("Incomplete Activity Log ({date}) 🔗"),
                    "Missing Media Link / Duration ⏱️".to_string(),
                ];
                let bodies = [
                    format!("Activities logged on {date} ({preview}) are missing source URLs or durations. Fill them in to track true input!"),
                    format!("Log integrity check: {preview} has no link duration attached. Update your session log."),
                ];

                NotificationPayload {
                    title: titles.choose(&mut rng).cloned().unwrap(),
                    body: bodies.choose(&mut rng).cloned().unwrap(),
                    url: format!("/log/{language}/{date}"),
                    tag: format!("activity-link-audit-{language}-{date}"),
                }
            }

            // -----------------------------------------------------------------
            // SRS Leech Warning (Lapses >= 3)
            // -----------------------------------------------------------------
            Self::SrsLeechWarning {
                language,
                leech_words,
            } => {
                let preview = leech_words.join(", ");
                let titles = [
                    format!("SRS Leech Alert ({language}) 🩹"),
                    "Memory Decay Warning 📉".to_string(),
                    "Struggling Cards Need Context 🧠".to_string(),
                ];
                let bodies = [
                    format!("Words [{preview}] have 3+ review lapses. Add a fresh context sentence, mnemonic, or audio sample!"),
                    format!("High lapse count for [{preview}]. Restructure these cards before they drain review time."),
                ];

                NotificationPayload {
                    title: titles.choose(&mut rng).cloned().unwrap(),
                    body: bodies.choose(&mut rng).cloned().unwrap(),
                    url: format!("/srs/{language}"),
                    tag: format!("srs-leech-{language}"),
                }
            }

            // -----------------------------------------------------------------
            // Audio Queue Backlog Nudge
            // -----------------------------------------------------------------
            Self::AudioQueueBacklogNudge {
                language,
                audio_cards_due,
            } => {
                let titles = [
                    format!("Ear-Training Due: {language} 🎧"),
                    format!("{audio_cards_due} Audio Cards Pending 🔊"),
                ];
                let bodies = [
                    format!("Acoustic recall check: {audio_cards_due} ear-training cards due in {language}. Plug in headphones and clear a batch!"),
                    format!("Don't let ear-training decay: {audio_cards_due} audio cards are waiting. Knock out a quick set!"),
                ];

                NotificationPayload {
                    title: titles.choose(&mut rng).cloned().unwrap(),
                    body: bodies.choose(&mut rng).cloned().unwrap(),
                    url: format!("/srs/{language}?type=audio"),
                    tag: format!("audio-queue-backlog-{language}"),
                }
            }

            // -----------------------------------------------------------------
            // 🌟 NEW: Writing Queue Backlog Nudge 🌟
            // -----------------------------------------------------------------
            Self::WritingQueueBacklogNudge {
                language,
                writing_cards_due,
            } => {
                let titles = [
                    format!("Calligraphy Practice Due ({language}) ✍️"),
                    format!("{writing_cards_due} Stroke Recall Cards Pending 🖋️"),
                ];
                let bodies = [
                    format!("Motor recall session: {writing_cards_due} writing cards are due. Practice your stroke order today!"),
                    format!("Kinesthetic recall check: {writing_cards_due} calligraphy cards ready for review."),
                ];

                NotificationPayload {
                    title: titles.choose(&mut rng).cloned().unwrap(),
                    body: bodies.choose(&mut rng).cloned().unwrap(),
                    url: format!("/srs/{language}?type=writing"),
                    tag: format!("writing-queue-backlog-{language}"),
                }
            }

            // -----------------------------------------------------------------
            // Night Kickoff
            // -----------------------------------------------------------------
            Self::NightKickoff {
                language,
                visual_srs_due,
            } => {
                let titles = [
                    format!("Night Closeout: {language} 🌙"),
                    "Final Stretch to 11:00 PM 🏁".to_string(),
                    format!("Streak Defense Active ({language}) 🛡️"),
                ];
                let bodies = [
                    format!("Evening closeout: complete your final immersion targets and clear your {visual_srs_due} pending SRS cards."),
                    format!("11:00 PM deadline ahead. Clear your {visual_srs_due} due cards to secure today's progress!"),
                ];

                NotificationPayload {
                    title: titles.choose(&mut rng).cloned().unwrap(),
                    body: bodies.choose(&mut rng).cloned().unwrap(),
                    url: if visual_srs_due > 0 {
                        format!("/srs/{language}")
                    } else {
                        format!("/log/{language}")
                    },
                    tag: format!("night-kickoff-{language}"),
                }
            }

            // -----------------------------------------------------------------
            // Night Progress Delta
            // -----------------------------------------------------------------
            Self::NightProgressDelta {
                language,
                missing_revisions,
                missing_listening_mins,
                visual_srs_due,
                mins_until_eleven,
            } => {
                let mut pend = Vec::new();
                if visual_srs_due > 0 {
                    pend.push(format!("{visual_srs_due} SRS cards"));
                }
                if missing_revisions > 0 {
                    pend.push("Day Revision".to_string());
                }
                if missing_listening_mins > 0 {
                    pend.push(format!("{missing_listening_mins}m media listening"));
                }
                let pend_str = pend.join(", ");

                let titles = [
                    format!("{mins_until_eleven}m Until 11:00 PM Deadline ⏳"),
                    format!("Final Wrap-Up ({language}) ⏱️"),
                    "Seal Today's Targets 📚".to_string(),
                ];
                let bodies = [
                    format!("Clock is ticking: {pend_str} remaining before 11:00 PM."),
                    format!("{mins_until_eleven} minutes left! Clear {pend_str} to complete today's targets."),
                ];

                NotificationPayload {
                    title: titles.choose(&mut rng).cloned().unwrap(),
                    body: bodies.choose(&mut rng).cloned().unwrap(),
                    url: if visual_srs_due > 0 {
                        format!("/srs/{language}")
                    } else {
                        format!("/log/{language}")
                    },
                    tag: format!("night-delta-{language}"),
                }
            }

            // -----------------------------------------------------------------
            // Night Overdue Warning (Past 11:00 PM)
            // -----------------------------------------------------------------
            Self::NightOverdueWarning {
                language,
                visual_srs_due,
                current_streak,
            } => {
                let titles = [
                    "11:00 PM Deadline Passed! Streak in Jeopardy 🔥".to_string(),
                    format!("Critical Warning: Day Not Complete ({language}) 🚨"),
                    "Midnight Approaching ⏳".to_string(),
                ];
                let bodies = [
                    format!("11:00 PM has passed! You still have {visual_srs_due} cards and open targets. Don't lose your {current_streak}-day streak!"),
                    format!("{current_streak} days on the line. Clear your reviews before midnight resets the day!"),
                ];

                NotificationPayload {
                    title: titles.choose(&mut rng).cloned().unwrap(),
                    body: bodies.choose(&mut rng).cloned().unwrap(),
                    url: format!("/srs/{language}"),
                    tag: format!("night-overdue-{language}"),
                }
            }

            // -----------------------------------------------------------------
            // Victory Lap (All targets and queues cleared)
            // -----------------------------------------------------------------
            Self::VictoryLap {
                language,
                current_streak,
            } => {
                let titles = [
                    "Flawless Execution: All Targets Crushed! 🏆".to_string(),
                    format!("Day Secured! {current_streak}-Day Streak Active ✨"),
                    "100% Complete: Rest Easy 🌟".to_string(),
                ];
                let bodies = [
                    format!("Every revision, listening goal, vocab target, and SRS deck in {language} cleared!"),
                    format!("Outstanding consistency. {current_streak} consecutive days locked in. Neural pathways reinforced!"),
                    format!("Zero debt, zero missing audio, and full quotas achieved for {language}. Rest up!"),
                ];

                NotificationPayload {
                    title: titles.choose(&mut rng).cloned().unwrap(),
                    body: bodies.choose(&mut rng).cloned().unwrap(),
                    url: format!("/log/{language}"),
                    tag: format!("victory-lap-{language}"),
                }
            }

            // -----------------------------------------------------------------
            // System Ping
            // -----------------------------------------------------------------
            Self::SystemPing { message } => NotificationPayload {
                title: "Language Vault 🔔".to_string(),
                body: message,
                url: "/".to_string(),
                tag: "system-ping".to_string(),
            },
        }
    }
}