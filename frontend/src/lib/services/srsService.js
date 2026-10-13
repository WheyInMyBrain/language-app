import { initLocalDatabase, stageLocalMutation } from '../db.js';
import { calculateNextSRSState, calculateWeightedListeningTime } from '../srsEngine.js';
import { metadataStore } from '../stores/metadata.svelte.js';

export async function processSessionSRSReview({
  langCode,
  dateStr,
  grade,
  todayStr = new Date().toISOString().substring(0, 10)
}) {
  const db = await initLocalDatabase();
  const calKey = `${langCode}:${dateStr}`;

  // 1. Fetch current daily_log record (or read from metadataStore cache)
  const existingRecord = (await db.get('daily_logs', calKey)) || metadataStore.calendarIndex[calKey] || {
    id: calKey,
    lang_code: langCode,
    log_date: dateStr,
    revision: 0,
    interval: 0,
    ease: 2.50,
    due_date: dateStr,
    last_reviewed: null
  };

  const currentRev = Number(existingRecord.revision ?? 0);
  const currentInterval = Number(existingRecord.interval ?? 0);
  const currentEase = Number(existingRecord.ease ?? 2.50);

  // 2. Calculate next SRS state
  const nextState = calculateNextSRSState({
    currentRev,
    currentInterval,
    currentEase,
    grade,
    todayStr
  });

  // 3. Load activities for this day to recalculate weighted listening duration
  const activities = await db.getAllFromIndex('activities', 'by_lang_date', [langCode, dateStr]);
  const activeActivities = activities.filter((a) => !a.deleted_at);
  const newListeningTime = calculateWeightedListeningTime(activeActivities, nextState.revision);

  // 4. Construct updated daily_log entry
  const updatedEntry = {
    ...existingRecord,
    id: calKey,
    lang_code: langCode,
    log_date: dateStr,
    revision: nextState.revision,
    interval: nextState.interval,
    ease: nextState.ease,
    due_date: nextState.due_date,
    last_reviewed: nextState.last_reviewed,
    listening_time: newListeningTime
  };

  // 5. Stage write locally and enqueue for sync
  await stageLocalMutation('daily_logs', calKey, updatedEntry);

  // 6. Update in-memory metadataStore state and trigger streak re-evaluation
  metadataStore.calendarIndex[calKey] = updatedEntry;
  metadataStore.queueStreakRecalc(langCode);

  return nextState;
}