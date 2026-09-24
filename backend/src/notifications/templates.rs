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
    // PHASE 1: Morning Focus (Deadline: 12:00 PM)
    // 1 Rev, 2 Listening (>= 15m), 10 Vocab, 1 CI
    // =========================================================================
    MorningKickoff {
        language: String,
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
    // PHASE 2: Afternoon Momentum & Debt (Deadline: 06:00 PM)
    // 2nd Rev, +2 Listening (+15m -> 30m), 10m Speaking, Past Debt = 0
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
    // PHASE 3: Night Closeout (Deadline: 11:00 PM)
    // 3rd Rev, +2 Listening (+15m -> 45m), Visual SRS Queue = 0
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
    // DATABASE AUDITS (Strictly Active After 03:00 PM)
    // Voice attachments, readings, ghost activity entries, leeches
    // =========================================================================
    MissingVoiceAudit {
        language: String,
        date: String,
        revision_number: u32,
        missing_words: Vec<String>,
        missing_activities_count: usize,
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
            // Morning Kickoff
            // -----------------------------------------------------------------
            Self::MorningKickoff { language } => {
                let titles = [
                    format!("Morning Blueprint: {language} 🌅"),
                    format!("12:00 PM Target Window Open ({language}) 🎯"),
                    "Daybreak Quota Active ⏱️".to_string(),
                    format!("Rise & Input: {language} ☕"),
                ];
                let bodies = [
                    "Morning target due by 12:00 PM: 1 revision, 10 vocab, 1 CI session, and 15m media listening.",
                    "Frontload your day: clear today's 1st revision, 10 words, 1 CI entry, and 15m input before noon.",
                    "Peak morning cognitive window. Knock out 1 revision, 10 words, and 15m audio before lunch.",
                    "Morning sprint begins: 4 items to check off before 12:00 PM. Let's get moving!",
                ];

                NotificationPayload {
                    title: titles.choose(&mut rng).cloned().unwrap(),
                    body: bodies.choose(&mut rng).copied().unwrap().to_string(),
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
                    format!("{mins_until_noon}m to Noon Deadline ⏳"),
                    format!("Morning Quota Check ({language}) 📋"),
                    "Pacing Check: 12:00 PM Window ⏱️".to_string(),
                    "Keep the Morning Running 🏃".to_string(),
                ];

                let bodies = [
                    format!("Still needed before 12:00 PM: {delta_str}. Knock this out now!"),
                    format!("{mins_until_noon} minutes remain to clear noon targets: {delta_str}."),
                    format!("Maintain flow before lunch. Pending morning items: {delta_str}."),
                    format!("Tick-tock: {delta_str} remaining. A quick session clears the morning block."),
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
                    format!("12:00 PM Deadline Missed ({language}) ⚠️"),
                    "Morning Quota Unfinished 🚨".to_string(),
                    "Debt Carried into Afternoon 📉".to_string(),
                ];
                let bodies = [
                    format!("Morning block ended with backlog: {items_str}. Clear this before afternoon tasks stack up!"),
                    format!("Noon has passed, but {items_str} remain open. Don't let morning debt compound!"),
                    format!("Morning targets incomplete ({items_str}). Complete them now to protect your daily schedule."),
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
                    format!(" Also note: you have past revisions across {past_debt_days} day(s) that must be cleared by 6:00 PM.")
                } else {
                    "".to_string()
                };

                let titles = [
                    format!("Afternoon Block Active: {language} ⚡"),
                    "6:00 PM Deadline Countdown 🎯".to_string(),
                    format!("Phase 2 Underway ({language}) 🚀"),
                ];
                let bodies = [
                    format!("Afternoon targets due by 6:00 PM: 2nd revision, +15m listening (30m total), and 10m speaking practice.{debt_msg}"),
                    format!("Time for vocal output! Record your 10m speech, 2nd revision, and afternoon listening before 6:00 PM.{debt_msg}"),
                    format!("Maintain cadence. 3 core goals before 6 PM: Rev #2, 10m speaking, 30m total input.{debt_msg}"),
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
                    tasks.push("Today's Rev #2".to_string());
                }
                if missing_speaking_mins > 0 {
                    tasks.push(format!("{missing_speaking_mins}m speech recording"));
                }
                if missing_listening_mins > 0 {
                    tasks.push(format!("{missing_listening_mins}m video/audio"));
                }
                if !past_debt_dates.is_empty() {
                    let first_date = &past_debt_dates[0];
                    let more = past_debt_dates.len().saturating_sub(1);
                    if more > 0 {
                        tasks.push(format!("debt from {first_date} (+{more} days)"));
                    } else {
                        tasks.push(format!("debt from {first_date}"));
                    }
                }
                let tasks_str = tasks.join(", ");

                let titles = [
                    format!("{mins_until_six}m Until 6:00 PM Deadline ⏳"),
                    format!("Afternoon Check ({language}) 📊"),
                    "Clear Debt Before 6 PM 🛡️".to_string(),
                ];
                let bodies = [
                    format!("Outstanding before 6:00 PM: {tasks_str}. Record speech and clear past debt now!"),
                    format!("{mins_until_six} minutes left in Phase 2. Pending items: {tasks_str}."),
                    format!("Don't let yesterday's backlog linger: {tasks_str} required before 6:00 PM."),
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
                    debt_items.push(format!("{missing_speaking_mins}m speaking recording"));
                }
                if missing_listening_mins > 0 {
                    debt_items.push(format!("{missing_listening_mins}m listening"));
                }
                if !past_debt_dates.is_empty() {
                    debt_items.push(format!("revisions for {}", past_debt_dates.join(", ")));
                }
                let debt_str = debt_items.join(" + ");

                let titles = [
                    format!("6:00 PM Deadline Passed ({language}) 🚨"),
                    "Phase 2 Targets Overdue ⚠️".to_string(),
                    "Backlog Alert: Immediate Action Needed 🛑".to_string(),
                ];
                let bodies = [
                    format!("6:00 PM passed with unresolved debt: {debt_str}. Clear this before night closeout!"),
                    format!("Overdue backlog: {debt_str}. Unfinished past sessions cannot roll over to tomorrow!"),
                    format!("Stop debt accumulation: {debt_str} must be resolved immediately."),
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
            // Output Imbalance (Lots of YouTube input, zero speech recording)
            // -----------------------------------------------------------------
            Self::OutputImbalanceWarning {
                language,
                listening_mins,
                speaking_mins,
                target_speaking_mins,
            } => {
                let titles = [
                    format!("Output Deficit Detected ({language}) 🎙️"),
                    "Input / Output Imbalance ⚖️".to_string(),
                    "Vocal Tract Activation Needed 🗣️".to_string(),
                ];
                let bodies = [
                    format!("You logged {listening_mins}m of media listening, but only {speaking_mins}/{target_speaking_mins}m of recorded speech. Record your shadowing now!"),
                    format!("Passive input is high ({listening_mins}m), but active vocalization is lacking. Record {target_speaking_mins}m speech to balance your neural loops."),
                    format!("Don't just listen! Record your {target_speaking_mins}m speaking practice before the 6:00 PM deadline."),
                ];

                NotificationPayload {
                    title: titles.choose(&mut rng).cloned().unwrap(),
                    body: bodies.choose(&mut rng).cloned().unwrap(),
                    url: format!("/log/{language}"),
                    tag: format!("output-imbalance-{language}"),
                }
            }

            // -----------------------------------------------------------------
            // Missing Voice Audit (Strictly After 03:00 PM)
            // Checks words and activities (item_index) past Revision 3
            // -----------------------------------------------------------------
            Self::MissingVoiceAudit {
                language,
                date,
                revision_number,
                missing_words,
                missing_activities_count,
            } => {
                let titles = [
                    format!("Voice Audit: {language} ({date}) 🎙️"),
                    format!("Missing Audio Recordings ({date}) 🔊"),
                    "Voice is Mandatory for Recall 🧠".to_string(),
                    format!("Rev #{revision_number} Audio Required 🎙️"),
                ];

                let mut details = Vec::new();
                if !missing_words.is_empty() {
                    let word_preview = if missing_words.len() <= 3 {
                        missing_words.join(", ")
                    } else {
                        format!("{}, +{} more", missing_words[..2].join(", "), missing_words.len() - 2)
                    };
                    details.push(format!("Words: [{word_preview}]"));
                }
                if missing_activities_count > 0 {
                    details.push(format!("{missing_activities_count} activities lacking voice note"));
                }
                let detail_text = details.join(" & ");

                let bodies = [
                    format!("Session {date} (Rev #{revision_number}) has matured items lacking voice recordings: {detail_text}. Tap to record."),
                    format!("Every matured entry needs your voice attached. Missing audio on {date}: {detail_text}."),
                    format!("Lock in phonetics and muscle memory: add voice for {detail_text} from {date}."),
                    format!("Voice check: {detail_text} lack recorded audio on {date}. Complete them now!"),
                ];

                NotificationPayload {
                    title: titles.choose(&mut rng).cloned().unwrap(),
                    body: bodies.choose(&mut rng).cloned().unwrap(),
                    url: format!("/log/{language}/{date}?filter=missing-audio"),
                    tag: format!("voice-audit-{language}-{date}"),
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
                let preview = if untranscribed_words.len() <= 3 {
                    untranscribed_words.join(", ")
                } else {
                    format!("{}, +{} more", untranscribed_words[..2].join(", "), untranscribed_words.len() - 2)
                };

                let titles = [
                    format!("Phonetic Gap: {language} ({date}) 🔤"),
                    "Missing Pronunciation / IPA Readings 📝".to_string(),
                    "Incomplete Word Definitions ⚠️".to_string(),
                ];
                let bodies = [
                    format!("Words logged on {date} lack phonetic readings: [{preview}]. Add readings before SRS cards activate!"),
                    format!("Script without readings won't stick! Fill in pronunciation for [{preview}] on {date}."),
                    format!("Phonetic transcription missing for [{preview}]. Complete the vocabulary card data now."),
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
                    "Activity Audit Warning ⚠️".to_string(),
                ];
                let bodies = [
                    format!("Activities logged on {date} ({preview}) are missing source URLs or video durations. Fill them in to track true input!"),
                    format!("Log integrity check: {preview} has no link duration attached. Update your session log."),
                    format!("Track legitimate input volume: add the media link and duration for {preview} on {date}."),
                ];

                NotificationPayload {
                    title: titles.choose(&mut rng).cloned().unwrap(),
                    body: bodies.choose(&mut rng).cloned().unwrap(),
                    url: format!("/log/{language}/{date}"),
                    tag: format!("activity-link-audit-{language}-{date}"),
                }
            }

            // -----------------------------------------------------------------
            // SRS Leech Warning
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
                    format!("Words [{preview}] have fallen below 1.6 ease. Add fresh context sentences, mnemonics, or a new audio sample!"),
                    format!("High failure rate detected for [{preview}]. Reinforce these words before they drain your review time."),
                    format!("Leech alert: [{preview}] are stuck at low intervals. Restructure their notes or voice recordings."),
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
                    format!("Ear-Training Backlog: {language} 🎧"),
                    format!("{audio_cards_due} Audio Cards Pending 🔊"),
                    "Listening Queue Accumulating 👂".to_string(),
                ];
                let bodies = [
                    format!("Visual reviews are clean, but you have {audio_cards_due} ear-training cards pending. Schedule a listening recall session!"),
                    format!("Don't let listening decay: {audio_cards_due} audio cards are waiting in {language}. Put on headphones and clear them!"),
                    format!("Acoustic comprehension check: {audio_cards_due} audio cards due. Clear a quick batch right now."),
                ];

                NotificationPayload {
                    title: titles.choose(&mut rng).cloned().unwrap(),
                    body: bodies.choose(&mut rng).cloned().unwrap(),
                    url: format!("/srs/{language}?type=audio"),
                    tag: format!("audio-queue-backlog-{language}"),
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
                    format!("Final goals by 11:00 PM: 3rd revision, 45m total media audio, and zero out {visual_srs_due} visual flashcards."),
                    format!("Evening sprint: complete today's final revision, final 15m input, and clear all {visual_srs_due} visual SRS cards."),
                    format!("11:00 PM deadline ahead. Clear your {visual_srs_due} visual cards and 3rd revision to seal today's progress."),
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
                    pend.push(format!("{visual_srs_due} visual cards"));
                }
                if missing_revisions > 0 {
                    pend.push("3rd revision".to_string());
                }
                if missing_listening_mins > 0 {
                    pend.push(format!("{missing_listening_mins}m media listening"));
                }
                let pend_str = pend.join(", ");

                let titles = [
                    format!("{mins_until_eleven}m Until 11:00 PM Deadline ⏳"),
                    format!("Final Wrap-Up ({language}) ⏱️"),
                    "Visual Test & Closeout Required 📚".to_string(),
                ];
                let bodies = [
                    format!("Clock is ticking: {pend_str} remaining before 11:00 PM."),
                    format!("{mins_until_eleven} minutes left! Clear {pend_str} to complete today's targets."),
                    format!("Finish strong before 11 PM: {pend_str} standing between you and full completion."),
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
                    format!("11:00 PM Deadline Passed! Streak in Jeopardy 🔥"),
                    format!("Critical Warning: Day Not Complete ({language}) 🚨"),
                    "Midnight Approaching ⏳".to_string(),
                ];
                let bodies = [
                    format!("11:00 PM has passed! You still have {visual_srs_due} visual cards and targets open. Don't lose your {current_streak}-day streak!"),
                    format!("{current_streak} days on the line. Clear your visual reviews immediately before midnight resets your progress!"),
                    format!("Final urgent alert: Complete open reviews now to safeguard your {current_streak}-day record!"),
                ];

                NotificationPayload {
                    title: titles.choose(&mut rng).cloned().unwrap(),
                    body: bodies.choose(&mut rng).cloned().unwrap(),
                    url: format!("/srs/{language}"),
                    tag: format!("night-overdue-{language}"),
                }
            }

            // -----------------------------------------------------------------
            // Victory Lap
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
                    format!("Every revision, listening block, vocab goal, speaking drill, and visual card in {language} cleared!"),
                    format!("Outstanding consistency. {current_streak} consecutive days locked in. Neural pathways reinforced!"),
                    format!("Zero debt, zero missing audio, and full quotas achieved for {language}. Excellent work today!"),
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