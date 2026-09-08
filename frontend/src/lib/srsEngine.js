/**
 * frontend/src/lib/srsEngine.js
 * Universal, language-agnostic SM-2 Spaced Repetition Engine.
 * Usable for Day Sessions, Visual Word Cards, and Audio Word Cards.
 */

export const GRADE_CONFIG = {
  again: { intMultiplier: null, easeDelta: -0.20 },
  hard:  { intMultiplier: 1.20, easeDelta: -0.15 },
  good:  { intMultiplier: 1.00, easeDelta:  0.00 }, // seed * ease
  easy:  { intMultiplier: 1.30, easeDelta: +0.15 }  // seed * ease * 1.30
};

/**
 * Calculates the next interval in days based on previous interval, ease, and grade.
 */
export function calculateNextInterval(curInt, curEase, grade) {
  const seed = Math.max(1, Number(curInt) || 0);
  const ease = Number(curEase) || 2.50;

  switch (grade) {
    case 'again':
      return 1;
    case 'hard':
      return Math.max(1, Math.round(seed * GRADE_CONFIG.hard.intMultiplier));
    case 'good':
      return Math.max(1, Math.round(seed * ease));
    case 'easy':
      return Math.max(1, Math.round(seed * ease * GRADE_CONFIG.easy.intMultiplier));
    default:
      return 1;
  }
}

/**
 * Returns a quick preview string (e.g., "1d", "4d", "12d") for UI buttons.
 */
export function getIntervalPreview({ interval = 0, ease = 2.50, grade }) {
  const nextInt = calculateNextInterval(interval, ease, grade);
  return `${nextInt}d`;
}

/**
 * Adds N days to a "YYYY-MM-DD" string and returns a new "YYYY-MM-DD" string.
 */
export function addDaysToDate(dateStr, days) {
  const [year, month, day] = dateStr.split('-').map(Number);
  const date = new Date(Date.UTC(year, month - 1, day));
  date.setUTCDate(date.getUTCDate() + Number(days));
  return date.toISOString().substring(0, 10);
}

/**
 * Computes next SRS state (revision, interval, ease, due_date) from current values.
 */
export function calculateNextSRSState({
  currentRev = 0,
  currentInterval = 0,
  currentEase = 2.50,
  grade,
  todayStr = new Date().toISOString().substring(0, 10)
}) {
  const rev = (Number(currentRev) || 0) + 1;
  let ease = Number(currentEase) || 2.50;
  let interval = 0;

  if (grade === 'increment_initial') {
    interval = 0;
    ease = 2.50;
  } else {
    const delta = GRADE_CONFIG[grade]?.easeDelta || 0;
    ease = Math.max(1.30, Number((ease + delta).toFixed(2)));
    interval = calculateNextInterval(currentInterval, ease, grade);
  }

  const dueDate = addDaysToDate(todayStr, interval);

  return {
    revision: rev,
    interval,
    ease,
    last_reviewed: todayStr,
    due_date: dueDate
  };
}

/**
 * Computes the total weighted listening time in seconds based on revision number:
 * totalListening = pure_listening + (min(3, revision) * ci_duration)
 */
export function calculateWeightedListeningTime(activities = [], revisionCount = 1) {
  const ciMultiplier = Math.min(Math.max(1, revisionCount), 3);
  let pureListeningSec = 0;
  let ciDurationSec = 0;

  for (const act of activities) {
    const dur = Number(act.link_duration) || 0;
    if (act.activity_type === 'ci') {
      ciDurationSec += dur;
    } else if (act.activity_type === 'listening') {
      pureListeningSec += dur;
    }
  }

  return (ciDurationSec * ciMultiplier) + pureListeningSec;
}