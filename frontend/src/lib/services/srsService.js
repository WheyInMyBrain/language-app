// frontend/src/lib/services/srsService.js
import { getDocHandle } from '../yjs.js';
import { calculateNextSRSState, calculateWeightedListeningTime } from '../srsEngine.js';

export async function processSessionSRSReview({
  langCode,
  dateStr,
  dayDocHandle,
  grade,
  todayStr = new Date().toISOString().substring(0, 10)
}) {
  if (!dayDocHandle?.doc) {
    throw new Error('Day document handle is missing.');
  }

  const { doc: dayDoc } = dayDocHandle;
  const metaMap = dayDoc.getMap('meta');
  const activitiesArray = dayDoc.getArray('activities');
  const sessionData = metaMap.get('session') || {};

  // Resolve root calendar entry as fallback for revision count
  const metaHandle = getDocHandle('global:metadata');
  let calendarEntry = null;
  const calKey = `${langCode}:${dateStr}`;

  if (metaHandle?.doc) {
    const calendarIndex = metaHandle.doc.getMap('calendar_index');
    calendarEntry = calendarIndex.get(calKey);
  }

  // Exact fallback resolution matching the migration schema
  const currentRev = Number(sessionData.revision ?? calendarEntry?.revision ?? 0);
  const currentInterval = Number(sessionData.interval ?? 0);
  const currentEase = Number(sessionData.ease ?? 2.50);

  // 1. Calculate next SM-2 state
  const nextState = calculateNextSRSState({
    currentRev,
    currentInterval,
    currentEase,
    grade,
    todayStr
  });

  // 2. Upgrade 'meta.session' in Day Room
  dayDoc.transact(() => {
    metaMap.set('session', {
      ...sessionData,
      revision: nextState.revision,
      interval: nextState.interval,
      ease: nextState.ease,
      due_date: nextState.due_date,
      last_reviewed: nextState.last_reviewed
    });
  });

  // 3. Upgrade 'calendar_index' in Root Catalog
  if (metaHandle?.doc) {
    const calendarIndex = metaHandle.doc.getMap('calendar_index');
    const existingCal = calendarIndex.get(calKey) || {
      revision: 0,
      word: 0,
      ci: 0,
      grammar: 0,
      listening: 0,
      speaking_time: 0,
      listening_time: 0,
      due_date: null
    };

    // Recalculate dynamic weighted listening duration: (min(3, rev) * ci) + listening
    const currentActivities = activitiesArray.toArray();
    const newListeningTime = calculateWeightedListeningTime(currentActivities, nextState.revision);

    calendarIndex.set(calKey, {
      ...existingCal,
      revision: nextState.revision,
      due_date: nextState.due_date,
      listening_time: newListeningTime
    });
  }

  return nextState;
}