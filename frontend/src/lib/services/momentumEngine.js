// frontend/src/lib/services/momentumEngine.js
import { metadataStore } from '../stores/metadata.svelte.js';
import { srsStore } from '../stores/srs.svelte.js';

// Technical mapping strictly for DB field lookups & quantization steps
const METRIC_SCHEMA = {
  listening: { field: 'listening_time', isTime: true, step: 5 },
  speaking:  { field: 'speaking_time',  isTime: true, step: 5 },
  vocab:     { field: 'word',           isTime: false, step: 1 }
};

function calculateAlpha(halfLifeDays = 2.5) {
  return 1 - Math.exp(-Math.LN2 / Math.max(halfLifeDays, 0.5));
}

function calculateEMA(history = [], baseline = 0, alpha = 0.25) {
  if (!history || history.length === 0) return baseline;

  let ema = Number(history[0]) || 0;
  for (let i = 1; i < history.length; i++) {
    const actual = Math.max(0, Number(history[i]) || 0);
    ema = alpha * actual + (1 - alpha) * ema;
  }
  return ema;
}

function evaluateTargetZone(mt, baseline, floor, ceiling) {
  const ratio = baseline > 0 ? mt / baseline : 1;
  let rawTarget = baseline;
  let zone = 'homeostasis';

  if (ratio < 0.60) {
    zone = 'recovery';
    rawTarget = Math.max(floor, mt * 1.25);
  } else if (ratio > 1.15) {
    zone = 'overdrive';
    rawTarget = Math.min(ceiling, baseline * Math.pow(ratio, 0.65));
  } else {
    zone = 'homeostasis';
    rawTarget = 0.70 * baseline + 0.30 * mt;
  }

  return { rawTarget, zone, ratio };
}

function getRecent7DayHistory(metricField, isTimeMetric, langCode) {
  const cal = metadataStore.calendarIndex || {};
  const history = [];
  const today = new Date();

  for (let i = 7; i >= 1; i--) {
    const d = new Date(today);
    d.setDate(d.getDate() - i);
    const dateStr = d.toISOString().slice(0, 10);
    const key = `${langCode}:${dateStr}`;

    let log = null;
    if (cal instanceof Map) {
      log = cal.get(key);
    } else if (typeof cal === 'object') {
      log = cal[key];
    }

    const rawVal = log?.[metricField] || 0;
    const val = isTimeMetric ? Math.round(rawVal / 60) : Number(rawVal) || 0;
    history.push(val);
  }

  return history;
}

/**
 * Extracts trailing 7-day history of completed review actions from reviews_completed
 */
function getRecent7DayReviewHistory(subType, langCode) {
  const cal = metadataStore.calendarIndex || {};
  const history = [];
  const today = new Date();

  for (let i = 7; i >= 1; i--) {
    const d = new Date(today);
    d.setDate(d.getDate() - i);
    const dateStr = d.toISOString().slice(0, 10);
    const key = `${langCode}:${dateStr}`;

    let log = null;
    if (cal instanceof Map) {
      log = cal.get(key);
    } else if (typeof cal === 'object') {
      log = cal[key];
    }

    const reviews = log?.reviews_completed || {};
    const val = Number(reviews[subType] ?? 0);
    history.push(val);
  }

  return history;
}

/**
 * Resolves boundaries strictly from the language profile (e.g. zh-CN.js)
 */
export function getMetricConfig(metricType, langCode) {
  const schema = METRIC_SCHEMA[metricType];
  if (!schema) throw new Error(`Unknown metricType: "${metricType}"`);

  const langConfig = metadataStore.languages?.[langCode] || {};
  const momentum = langConfig.momentum?.[metricType] || {};
  const goals = langConfig.goals || {};

  let baseline = momentum.baseline;
  if (baseline === undefined || baseline === null) {
    if (metricType === 'listening') baseline = goals.listening_minutes ?? 0;
    else if (metricType === 'speaking') baseline = goals.speaking_minutes ?? 0;
    else if (metricType === 'vocab') baseline = goals.vocab ?? 0;
    else baseline = 0;
  }

  const floor = Number(momentum.floor ?? 0);
  const maxCeilingAllowed = metricType === 'vocab' ? 10 : Infinity;
  const ceiling = Math.min(
    maxCeilingAllowed, 
    Number(momentum.ceiling ?? (metricType === 'vocab' ? 10 : baseline))
  );

  return {
    ...schema,
    baseline: Number(baseline),
    floor,
    ceiling,
    halfLifeDays: Number(momentum.halfLifeDays ?? 2.5),
    maxSlewRate: Number(momentum.maxSlewRate ?? (schema.isTime ? 15 : 2))
  };
}

/**
 * Computes today's dynamic target using only the active language's configured numbers.
 */
export function getAdaptiveGoal(metricType, previousTarget = null) {
  const langCode = metadataStore.activeLanguage || 'zh-CN';
  const config = getMetricConfig(metricType, langCode);

  const history = getRecent7DayHistory(config.field, config.isTime, langCode);
  const alpha = calculateAlpha(config.halfLifeDays);
  const mt = calculateEMA(history, config.baseline, alpha);

  const { rawTarget, zone, ratio } = evaluateTargetZone(mt, config.baseline, config.floor, config.ceiling);

  let clampedTarget = rawTarget;
  if (previousTarget !== null && previousTarget > 0) {
    const maxDelta = config.maxSlewRate;
    clampedTarget = Math.max(previousTarget - maxDelta, Math.min(previousTarget + maxDelta, rawTarget));
  }

  const quantized = Math.round(clampedTarget / config.step) * config.step;
  const finalTarget = Math.max(config.floor, Math.min(config.ceiling, quantized));

  return {
    target: finalTarget,
    baseline: config.baseline,
    floor: config.floor,
    ceiling: config.ceiling,
    momentum: Math.round(mt * 10) / 10,
    zone,
    ratio: Math.round(ratio * 100) / 100,
    history
  };
}

export function getAllAdaptiveGoals() {
  return {
    listening: getAdaptiveGoal('listening'),
    speaking:  getAdaptiveGoal('speaking'),
    vocab:     getAdaptiveGoal('vocab')
  };
}

// -------------------------------------------------------------
// 🌟 UNIFIED DAILY CONDUCTOR & REVISION PRIORITIZER 🌟
// -------------------------------------------------------------

/**
 * Generates the full daily plan:
 * 1. Adaptive Input Targets (Listening, Speaking, Vocab)
 * 2. Uncapped Tri-Deck SRS Due Cards + Paced Recommendations (Vision, Audio, Writing)
 * 3. Prioritized DayPage Revisions (Lowest revision first!)
 * 4. Adaptive Catch-Up Siphon for unvoiced audio artifacts
 */
export function getDailyMissionManifest(todayStr) {
  const langCode = metadataStore.activeLanguage || 'zh-CN';
  const langConfig = metadataStore.languages?.[langCode] || {};
  const cal = metadataStore.calendarIndex || {};
  const goals = getAllAdaptiveGoals();

  // 1. Calculate Review Velocity from 7-day reviews_completed telemetry
  const srsConfig = langConfig.momentum?.srs || {
    vision: { floor: 10, baseline: 20, ceiling: 35 },
    listen: { floor: 5,  baseline: 10, ceiling: 20 },
    write:  { floor: 1,  baseline: 3,  ceiling: 5 }
  };
  const revConfig = langConfig.momentum?.revisions || { floor: 1, baseline: 1, ceiling: 2 };

  const alpha = calculateAlpha(2.5);

  const visionHistory = getRecent7DayReviewHistory('srs_vision', langCode);
  const listenHistory = getRecent7DayReviewHistory('srs_listen', langCode);
  const writeHistory = getRecent7DayReviewHistory('srs_write', langCode);
  const revHistory = getRecent7DayReviewHistory('day_revisions', langCode);

  const mtVision = calculateEMA(visionHistory, srsConfig.vision.baseline, alpha);
  const mtListen = calculateEMA(listenHistory, srsConfig.listen.baseline, alpha);
  const mtWrite  = calculateEMA(writeHistory, srsConfig.write.baseline, alpha);
  const mtRev    = calculateEMA(revHistory, revConfig.baseline, alpha);

  const zVision = evaluateTargetZone(mtVision, srsConfig.vision.baseline, srsConfig.vision.floor, srsConfig.vision.ceiling);
  const zListen = evaluateTargetZone(mtListen, srsConfig.listen.baseline, srsConfig.listen.floor, srsConfig.listen.ceiling);
  const zWrite  = evaluateTargetZone(mtWrite, srsConfig.write.baseline, srsConfig.write.floor, srsConfig.write.ceiling);
  const zRev    = evaluateTargetZone(mtRev, revConfig.baseline, revConfig.floor, revConfig.ceiling);

  const recVision = Math.round(zVision.rawTarget);
  const recListen = Math.round(zListen.rawTarget);
  const recWrite  = Math.max(1, Math.round(zWrite.rawTarget));
  const recRevs   = Math.max(1, Math.round(zRev.rawTarget));

  // 2. Dynamic Catch-Up Quota for unvoiced words based on overall momentum
  const speakingZone = goals.speaking.zone;
  const speakingRatio = goals.speaking.ratio;

  let voiceWordQuota = 5;
  if (speakingZone === 'recovery' || speakingRatio < 0.60) {
    voiceWordQuota = 2; // Travel/Slump: minimal friction
  } else if (speakingZone === 'overdrive' || speakingRatio > 1.20) {
    voiceWordQuota = 8; // Surge: clear faster
  }

  // 3. Uncapped Tri-Deck SRS Counters (Full mathematical fidelity)
  const rawCards = srsStore.cards || {};
  let srsVision = 0;
  let srsListen = 0;
  let srsWrite = 0;

  for (const item of Object.values(rawCards)) {
    if (!item) continue;
    const isDue = !item.due_date || item.due_date <= todayStr;
    if (isDue) {
      if (item.card_type === 'listening' || item.card_type === 'audio') {
        srsListen++;
      } else if (item.card_type === 'writing') {
        srsWrite++;
      } else {
        srsVision++;
      }
    }
  }

  // 4. DayPage Revisions with Priority Sorting:
  // 🌟 LOWER REVISION NUMBER = HIGHER PRIORITY 🌟
  const entries = metadataStore.sortedCalendarEntries || [];
  const revisionsDue = [];

  for (const entry of entries) {
    const rev = Number(entry.revision ?? 0);
    const dueDate = entry.due_date;
    const date = entry.date;

    // A. Unstarted or Pass 0 Day
    if (rev < 1) {
      if (date < todayStr) {
        const diffDays = Math.max(1, Math.round((new Date(todayStr) - new Date(date)) / (1000 * 60 * 60 * 24)));
        revisionsDue.push({
          date,
          revision: 0,
          statusLabel: `+${diffDays}d LATE`,
          urgencyCategory: 'overdue',
          overdueDays: diffDays,
          priorityScore: -10000 - (diffDays * 10)
        });
      } else if (date === todayStr) {
        revisionsDue.push({
          date,
          revision: 0,
          statusLabel: 'TODAY',
          urgencyCategory: 'today',
          overdueDays: 0,
          priorityScore: -5000
        });
      }
      continue;
    }

    // B. Scheduled SRS Day Sessions
    if (dueDate) {
      if (dueDate < todayStr) {
        const diffDays = Math.max(1, Math.round((new Date(todayStr) - new Date(dueDate)) / (1000 * 60 * 60 * 24)));
        const revWeight = (10 - Math.min(rev, 9)) * 100;
        revisionsDue.push({
          date,
          revision: rev,
          statusLabel: `+${diffDays}d LATE`,
          urgencyCategory: 'overdue',
          overdueDays: diffDays,
          priorityScore: -revWeight - diffDays
        });
      } else if (dueDate === todayStr) {
        revisionsDue.push({
          date,
          revision: rev,
          statusLabel: 'TODAY',
          urgencyCategory: 'today',
          overdueDays: 0,
          priorityScore: 10 + rev
        });
      }
    }
  }

  // Sort: Lowest score = Highest priority (surfaced at the top)
  revisionsDue.sort((a, b) => a.priorityScore - b.priorityScore);

  // 5. Catch-Up Siphon: Collect past unvoiced words (FIFO) up to voiceWordQuota
  const pastEntries = Object.entries(cal)
    .filter(([key]) => key.startsWith(`${langCode}:`))
    .map(([key, data]) => ({ key, date: key.split(':')[1], ...data }))
    .filter(entry => entry.date < todayStr)
    .sort((a, b) => a.date.localeCompare(b.date));

  const unvoicedBatch = [];
  let unvoicedHiddenCount = 0;

  for (const entry of pastEntries) {
    const wordIndices = entry.unvoiced_words_indices || [];
    for (const wIdx of wordIndices) {
      if (unvoicedBatch.length < voiceWordQuota) {
        unvoicedBatch.push({ date: entry.date, wordIndex: wIdx });
      } else {
        unvoicedHiddenCount++;
      }
    }
  }

  return {
    goals, // listening, speaking, vocab targets
    srs: {
      vision: srsVision,
      listen: srsListen,
      write: srsWrite,
      totalDue: srsVision + srsListen + srsWrite,
      recommended: {
        vision: Math.min(srsVision, recVision),
        listen: Math.min(srsListen, recListen),
        write:  Math.min(srsWrite, recWrite)
      }
    },
    revisions: revisionsDue,
    recommendedRevisionsCount: recRevs,
    unvoiced: {
      surfaced: unvoicedBatch,
      quota: voiceWordQuota,
      hiddenCount: unvoicedHiddenCount
    }
  };
}