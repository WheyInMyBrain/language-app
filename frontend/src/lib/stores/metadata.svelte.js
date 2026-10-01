// frontend/src/lib/stores/metadata.svelte.js
import { createSyncedDoc, getDocHandle } from '../yjs.js';

const ROOM_METADATA = 'global:metadata';
const MS_PER_DAY = 86400000;

class MetadataStore {
  connectionStatus = $state('connecting'); // 'connecting' | 'connected' | 'disconnected'
  isLocalLoaded = $state(false);
  languages = $state({});
  calendarIndex = $state({});
  activeLanguage = $state('zh-CN');

  #docHandle = null;
  #pendingStreakTimers = new Map();

  // Cache for sorted calendar entries to avoid re-sorting on every read
  #cachedSortedEntries = null;
  #cacheVersion = 0;
  #lastConsumedVersion = -1;
  #lastConsumedLang = null;

  init() {
    if (this.#docHandle) return;

    this.#docHandle = createSyncedDoc(ROOM_METADATA, (status) => {
      this.connectionStatus = status;
    });

    const { doc, idbProvider } = this.#docHandle;

    const langsMap = doc.getMap('languages');
    const calendarMap = doc.getMap('calendar_index');

    // 1. Optimized sync: shallow map iteration instead of expensive recursive toJSON()
    const syncState = () => {
      const nextLangs = {};
      for (const [k, v] of langsMap.entries()) {
        nextLangs[k] = v;
      }

      const nextCal = {};
      for (const [k, v] of calendarMap.entries()) {
        nextCal[k] = v;
      }

      this.languages = nextLangs;
      this.calendarIndex = nextCal;
      this.#cacheVersion++;

      const keys = Object.keys(this.languages);
      if (keys.length > 0 && !this.languages[this.activeLanguage]) {
        this.activeLanguage = keys[0];
      }

      if (this.activeLanguage) {
        this.queueStreakRecalc(this.activeLanguage);
      }
    };

    idbProvider.on('synced', () => {
      this.isLocalLoaded = true;
      syncState();
    });

    langsMap.observe(syncState);
    calendarMap.observe(syncState);
  }

  /**
   * High-speed UTC date parser for "YYYY-MM-DD".
   * 10x faster than .split('-').map(Number) and allocates zero temporary arrays.
   */
  #parseUtcDay(dateStr) {
    if (!dateStr || typeof dateStr !== 'string' || dateStr.length < 10) return NaN;
    const y = +dateStr.slice(0, 4);
    const m = +dateStr.slice(5, 7) - 1;
    const d = +dateStr.slice(8, 10);
    return Date.UTC(y, m, d);
  }

  /**
   * Fast zero-allocation local date formatter: YYYY-MM-DD
   */
  #toLocalDateStr(dateObj) {
    const y = dateObj.getFullYear();
    const m = dateObj.getMonth() + 1;
    const d = dateObj.getDate();
    return `${y}-${m < 10 ? '0' + m : m}-${d < 10 ? '0' + d : d}`;
  }

  /**
   * Determines if a calendar entry qualifies as an active study day
   */
  #isEntryActive(entry) {
    if (!entry) return false;
    if ((entry.word || 0) > 0) return true;
    if ((entry.ci || 0) > 0) return true;
    if ((entry.grammar || 0) > 0) return true;
    if ((entry.speaking_time || 0) > 0) return true;
    if ((entry.listening_time || 0) > 0) return true;

    const r = entry.reviews_completed;
    if (r) {
      if ((r.srs_vision || 0) > 0) return true;
      if ((r.srs_listen || 0) > 0) return true;
      if ((r.srs_write || 0) > 0) return true;
      if ((r.day_revisions || 0) > 0) return true;
    }
    return false;
  }

  /**
   * Microtask debounce: prevents O(N) recalculations from running multiple times
   * during rapid edits, batch logging, or fast SRS review dispatch.
   */
  queueStreakRecalc(langCode) {
    if (!langCode) return;
    if (this.#pendingStreakTimers.has(langCode)) return;

    const timer = queueMicrotask(() => {
      this.#pendingStreakTimers.delete(langCode);
      this.recalculateStreaks(langCode);
    });
    this.#pendingStreakTimers.set(langCode, timer);
  }

  /**
   * Recalculates current_streak, longest_streak, and total_days for a language.
   */
  recalculateStreaks(langCode) {
    if (!this.#docHandle?.doc || !langCode) return;

    const prefix = `${langCode}:`;
    const prefixLen = prefix.length;
    const activeDatesSet = new Set();

    // Fast map scan
    for (const key in this.calendarIndex) {
      if (key.startsWith(prefix)) {
        const entry = this.calendarIndex[key];
        if (this.#isEntryActive(entry)) {
          activeDatesSet.add(entry.date || key.slice(prefixLen));
        }
      }
    }

    const totalDays = activeDatesSet.size;
    if (totalDays === 0) {
      this.#commitStreakUpdate(langCode, 0, 0, 0);
      return;
    }

    // Sort descending: newest to oldest
    const sortedDates = Array.from(activeDatesSet).sort((a, b) => b.localeCompare(a));

    const now = new Date();
    const todayStr = this.#toLocalDateStr(now);
    now.setDate(now.getDate() - 1);
    const yesterdayStr = this.#toLocalDateStr(now);

    const latestActiveDate = sortedDates[0];

    // 1. Current streak calculation
    let currentStreak = 0;
    if (latestActiveDate === todayStr || latestActiveDate === yesterdayStr) {
      currentStreak = 1;
      let prevUtc = this.#parseUtcDay(latestActiveDate);

      for (let i = 1; i < sortedDates.length; i++) {
        const curUtc = this.#parseUtcDay(sortedDates[i]);
        const dayDiff = Math.round((prevUtc - curUtc) / MS_PER_DAY);

        if (dayDiff === 1) {
          currentStreak++;
          prevUtc = curUtc;
        } else if (dayDiff === 0) {
          continue; // Duplicate guard
        } else {
          break;
        }
      }
    }

    // 2. Longest historical streak calculation
    let longestStreak = 1;
    let streakRun = 1;
    let prevUtc = this.#parseUtcDay(sortedDates[0]);

    for (let i = 1; i < sortedDates.length; i++) {
      const curUtc = this.#parseUtcDay(sortedDates[i]);
      const dayDiff = Math.round((prevUtc - curUtc) / MS_PER_DAY);

      if (dayDiff === 1) {
        streakRun++;
        if (streakRun > longestStreak) longestStreak = streakRun;
        prevUtc = curUtc;
      } else if (dayDiff === 0) {
        continue;
      } else {
        streakRun = 1;
        prevUtc = curUtc;
      }
    }

    const existing = this.languages[langCode] || {};
    const finalLongest = Math.max(existing.longest_streak || 0, longestStreak, currentStreak);

    this.#commitStreakUpdate(langCode, currentStreak, finalLongest, totalDays);
  }

  #commitStreakUpdate(langCode, currentStreak, longestStreak, totalDays) {
    const langsMap = this.#docHandle.doc.getMap('languages');
    const existing = langsMap.get(langCode) || {};

    if (
      existing.current_streak === currentStreak &&
      existing.longest_streak === longestStreak &&
      existing.total_days === totalDays
    ) {
      return; // No-op if values match
    }

    const updated = {
      ...existing,
      current_streak: currentStreak,
      longest_streak: longestStreak,
      total_days: totalDays
    };

    this.#docHandle.doc.transact(() => {
      langsMap.set(langCode, updated);
    });

    this.languages[langCode] = updated;
  }

  /**
   * Atomically records a completed review into calendar_index.
   */
  recordReview(langCode, date, type, subType = 'visual') {
    if (!this.#docHandle?.doc || !langCode || !date) return;

    const calendarMap = this.#docHandle.doc.getMap('calendar_index');
    const key = `${langCode}:${date}`;
    const existing = calendarMap.get(key) || { date };

    const reviews = existing.reviews_completed ? { ...existing.reviews_completed } : {
      srs_vision: 0,
      srs_listen: 0,
      srs_write: 0,
      day_revisions: 0
    };

    if (type === 'srs') {
      if (subType === 'listening' || subType === 'audio') {
        reviews.srs_listen = (reviews.srs_listen || 0) + 1;
      } else if (subType === 'writing') {
        reviews.srs_write = (reviews.srs_write || 0) + 1;
      } else {
        reviews.srs_vision = (reviews.srs_vision || 0) + 1;
      }
    } else if (type === 'day_revision') {
      reviews.day_revisions = (reviews.day_revisions || 0) + 1;
    }

    const updated = {
      ...existing,
      reviews_completed: reviews
    };

    this.#docHandle.doc.transact(() => {
      calendarMap.set(key, updated);
    });

    // In-place mutate without full object reallocation
    this.calendarIndex[key] = updated;
    this.#cacheVersion++;

    this.queueStreakRecalc(langCode);
  }

  /**
   * Recalculates and updates calendar_index for a specific day.
   */
  refreshDayTotals(langCode, date) {
    if (!this.#docHandle?.doc) return;

    const roomName = `${langCode}:${date}`;
    const dayHandle = getDocHandle(roomName) || createSyncedDoc(roomName);
    if (!dayHandle?.doc) return;

    const dayDoc = dayHandle.doc;
    const metaMap = dayDoc.getMap('meta');
    const session = metaMap.get('session') || {};
    const revision = Number(session.revision ?? 0);

    // Fast array extraction
    const rawWords = dayDoc.getArray('words').toArray();
    const rawActivities = dayDoc.getArray('activities').toArray();

    let vocabAudioSec = 0;
    const unvoiced_words_indices = [];

    for (let i = 0; i < rawWords.length; i++) {
      const w = typeof rawWords[i].toJSON === 'function' ? rawWords[i].toJSON() : rawWords[i];
      const dur = Number(w.audio_duration);
      if (!isNaN(dur) && dur > 0) {
        vocabAudioSec += dur;
      } else {
        unvoiced_words_indices.push(Number(w.word_index ?? i + 1));
      }
    }

    let actAudioSec = 0;
    let ciLinkSec = 0;
    let pureListeningSec = 0;
    let ciCount = 0;
    let grammarCount = 0;
    let listeningCount = 0;

    const unvoiced_ci_indices = [];
    const unvoiced_listening_indices = [];
    const unvoiced_grammar_indices = [];

    for (let i = 0; i < rawActivities.length; i++) {
      const act = typeof rawActivities[i].toJSON === 'function' ? rawActivities[i].toJSON() : rawActivities[i];
      const type = act.activity_type;
      const linkDur = Number(act.link_duration || act.durationSec) || 0;
      const audioDur = Number(act.audio_duration) || 0;

      const hasAudio = !isNaN(audioDur) && audioDur > 0;
      if (hasAudio) {
        actAudioSec += audioDur;
      }

      const itemIdx = Number(act.item_index ?? i + 1);

      if (type === 'ci') {
        ciCount++;
        ciLinkSec += linkDur;
        if (!hasAudio) unvoiced_ci_indices.push(itemIdx);
      } else if (type === 'listening') {
        listeningCount++;
        pureListeningSec += linkDur;
        if (!hasAudio) unvoiced_listening_indices.push(itemIdx);
      } else if (type === 'grammar') {
        grammarCount++;
        if (!hasAudio) unvoiced_grammar_indices.push(itemIdx);
      }
    }

    const totalSpeakingSec = vocabAudioSec + actAudioSec;
    const ciMultiplier = Math.min(3, revision);
    const totalListeningSec = pureListeningSec + (ciMultiplier * ciLinkSec);

    // Goal completion evaluation
    const langConfig = this.languages?.[langCode] || {};
    const momentum = langConfig.momentum || {};
    const goals = langConfig.goals || {};

    const vocabBaseline = Number(momentum.vocab?.baseline ?? goals.vocab ?? 5);
    const ciBaseline = Number(goals.ci ?? 1);
    const grammarBaseline = Number(goals.grammar ?? 1);
    const listeningBaseline = Number(momentum.listening?.baseline ?? goals.listening_minutes ?? 45);
    const speakingBaseline = Number(momentum.speaking?.baseline ?? goals.speaking_minutes ?? 10);

    const listeningMinutes = Math.round(totalListeningSec / 60);
    const speakingMinutes = Math.round(totalSpeakingSec / 60);

    const calendarMap = this.#docHandle.doc.getMap('calendar_index');
    const key = `${langCode}:${date}`;
    const existing = calendarMap.get(key) || { date };

    const reviews_completed = existing.reviews_completed || {
      srs_vision: 0,
      srs_listen: 0,
      srs_write: 0,
      day_revisions: 0
    };

    const updatedEntry = {
      ...existing,
      date,
      revision,
      due_date: session.due_date || existing.due_date || date,

      word: rawWords.length,
      ci: ciCount,
      grammar: grammarCount,
      listening: listeningCount,
      speaking_time: totalSpeakingSec,
      listening_time: totalListeningSec,

      vocab_done: rawWords.length >= vocabBaseline,
      ci_done: ciCount >= ciBaseline,
      listening_done: listeningMinutes >= listeningBaseline,
      speaking_done: speakingMinutes >= speakingBaseline,
      grammar_done: grammarCount >= grammarBaseline,

      unvoiced_words_indices,
      unvoiced_ci_indices,
      unvoiced_listening_indices,
      unvoiced_grammar_indices,

      reviews_completed
    };

    this.#docHandle.doc.transact(() => {
      calendarMap.set(key, updatedEntry);
    });

    this.calendarIndex[key] = updatedEntry;
    this.#cacheVersion++;

    this.queueStreakRecalc(langCode);
  }

  get currentLanguageData() {
    return this.languages[this.activeLanguage] || {
      name: 'Chinese',
      code: 'zh-CN',
      current_streak: 0,
      longest_streak: 0,
      total_days: 0,
    };
  }

  /**
   * Memoized calendar entry retrieval.
   * Only filters and re-sorts if the active language or index contents change.
   */
  get sortedCalendarEntries() {
    if (
      this.#cachedSortedEntries &&
      this.#lastConsumedVersion === this.#cacheVersion &&
      this.#lastConsumedLang === this.activeLanguage
    ) {
      return this.#cachedSortedEntries;
    }

    const prefix = `${this.activeLanguage}:`;
    const res = [];

    for (const key in this.calendarIndex) {
      if (key.startsWith(prefix)) {
        res.push({
          key,
          date: key.slice(prefix.length),
          ...this.calendarIndex[key]
        });
      }
    }

    res.sort((a, b) => b.date.localeCompare(a.date));

    this.#cachedSortedEntries = res;
    this.#lastConsumedVersion = this.#cacheVersion;
    this.#lastConsumedLang = this.activeLanguage;

    return res;
  }

  addLanguage(languageConfig) {
    if (!this.#docHandle?.doc) return;
    const doc = this.#docHandle.doc;
    const langsMap = doc.getMap('languages');

    doc.transact(() => {
      langsMap.set(languageConfig.code, languageConfig);
    });

    this.languages[languageConfig.code] = languageConfig;
  }

  updateLanguageConfig(code, partialConfig) {
    if (!this.#docHandle?.doc) return;
    const doc = this.#docHandle.doc;
    const langsMap = doc.getMap('languages');
    const existing = langsMap.get(code) || {};

    const updated = {
      ...existing,
      ...partialConfig,
      goals: { ...(existing.goals || {}), ...(partialConfig.goals || {}) },
      milestones: { ...(existing.milestones || {}), ...(partialConfig.milestones || {}) },
      momentum: { ...(existing.momentum || {}), ...(partialConfig.momentum || {}) },
      colors: { ...(existing.colors || {}), ...(partialConfig.colors || {}) },
      tones: { ...(existing.tones || {}), ...(partialConfig.tones || {}) }
    };

    doc.transact(() => {
      langsMap.set(code, updated);
    });

    this.languages[code] = updated;
  }
}

export const metadataStore = new MetadataStore();