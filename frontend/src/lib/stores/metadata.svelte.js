// frontend/src/lib/stores/metadata.svelte.js
import { initLocalDatabase, stageLocalMutation } from '../db.js';

const MS_PER_DAY = 86400000;

function triggerSyncFlush() {
  if (typeof window === 'undefined') return;
  import('../syncCoordinator.js')
    .then((m) => {
      if (m?.syncCoordinator?.scheduleFlush) {
        m.syncCoordinator.scheduleFlush();
      }
    })
    .catch(() => {});
}

class MetadataStore {
  connectionStatus = $state('connected');
  isLocalLoaded = $state(false);
  languages = $state({});
  calendarIndex = $state({});
  activeLanguage = $state('zh-CN');

  #pendingStreakTimers = new Map();

  #cachedSortedEntries = null;
  #cacheVersion = 0;
  #lastConsumedVersion = -1;
  #lastConsumedLang = null;

  async init(forceReload = false) {
    if (this.isLocalLoaded && !forceReload) return;

    const db = await initLocalDatabase();

    const [langsList, dailyLogsList, allWords, allActs] = await Promise.all([
      db.getAll('languages').catch(() => []),
      db.getAll('daily_logs').catch(() => []),
      db.getAll('words').catch(() => []),
      db.getAll('activities').catch(() => [])
    ]);

    const langs = {};
    for (const l of langsList) {
      if (!l.deleted_at) {
        langs[l.code] = {
          ...l,
          // Deserialize JSON strings if raw from SQLite
          goals: typeof l.goals_json === 'string' ? JSON.parse(l.goals_json || '{}') : (l.goals || {}),
          milestones: typeof l.milestones_json === 'string' ? JSON.parse(l.milestones_json || '{}') : (l.milestones || {}),
          momentum: typeof l.momentum_json === 'string' ? JSON.parse(l.momentum_json || '{}') : (l.momentum || {}),
          colors: typeof l.colors_json === 'string' ? JSON.parse(l.colors_json || '{}') : (l.colors || {}),
          tones: typeof l.tones_json === 'string' ? JSON.parse(l.tones_json || '{}') : (l.tones || {})
        };
      }
    }

    // 1. Direct Ground Truth Aggregation Map
    const dayWordsMap = new Map();
    const dayVocabAudioMap = new Map();

    for (const w of allWords) {
      if (w.deleted_at) continue;
      const key = `${w.lang_code}:${w.log_date}`;
      dayWordsMap.set(key, (dayWordsMap.get(key) || 0) + 1);

      const aDur = Number(w.audio_duration || 0);
      if (!isNaN(aDur) && aDur > 0) {
        dayVocabAudioMap.set(key, (dayVocabAudioMap.get(key) || 0) + aDur);
      }
    }

    const dayActsMap = new Map();
    for (const a of allActs) {
      if (a.deleted_at) continue;
      const key = `${a.lang_code}:${a.log_date}`;
      const cur = dayActsMap.get(key) || {
        ciCount: 0,
        grammarCount: 0,
        listeningCount: 0,
        ciLinkSec: 0,
        pureListeningSec: 0,
        actAudioSec: 0
      };

      const linkDur = Number(a.link_duration || a.durationSec || a.duration || 0);
      const audioDur = Number(a.audio_duration || 0);

      if (a.activity_type === 'ci') {
        cur.ciCount++;
        cur.ciLinkSec += linkDur;
      } else if (a.activity_type === 'listening') {
        cur.listeningCount++;
        cur.pureListeningSec += linkDur;
      } else if (a.activity_type === 'grammar') {
        cur.grammarCount++;
      }

      if (!isNaN(audioDur) && audioDur > 0) {
        cur.actAudioSec += audioDur;
      }

      dayActsMap.set(key, cur);
    }

    // 2. Hydrate calendarIndex
    const cal = {};
    for (const log of dailyLogsList) {
      if (!log.deleted_at) {
        const dateStr = log.log_date || log.date;
        const key = `${log.lang_code}:${dateStr}`;
        const actTotals = dayActsMap.get(key);
        const derivedWords = dayWordsMap.get(key) || 0;
        const derivedVocabAudio = dayVocabAudioMap.get(key) || 0;

        const revision = Number(log.revision ?? 0);
        const ciMultiplier = Math.max(1, Math.min(3, revision || 1));

        const computedListeningSec = actTotals
          ? actTotals.pureListeningSec + (ciMultiplier * actTotals.ciLinkSec)
          : 0;

        const computedSpeakingSec = (actTotals ? actTotals.actAudioSec : 0) + derivedVocabAudio;

        const finalWord = Math.max(Number(log.word || 0), derivedWords);
        const finalCi = Math.max(Number(log.ci || 0), actTotals?.ciCount || 0);
        const finalGrammar = Math.max(Number(log.grammar || 0), actTotals?.grammarCount || 0);
        const finalListening = Math.max(Number(log.listening || 0), actTotals?.listeningCount || 0);
        const finalListeningSec = Math.max(Number(log.listening_time || 0), computedListeningSec);
        const finalSpeakingSec = Math.max(Number(log.speaking_time || 0), computedSpeakingSec);

        cal[key] = {
          ...log,
          date: dateStr,
          word: finalWord,
          ci: finalCi,
          grammar: finalGrammar,
          listening: finalListening,
          speaking_time: finalSpeakingSec,
          listening_time: finalListeningSec
        };
      }
    }

    this.languages = langs;
    this.calendarIndex = cal;
    this.#cachedSortedEntries = null;
    this.#cacheVersion++;
    this.isLocalLoaded = true;

    const keys = Object.keys(this.languages);
    if (keys.length > 0 && !this.languages[this.activeLanguage]) {
      this.activeLanguage = keys[0];
    }

    if (this.activeLanguage) {
      this.queueStreakRecalc(this.activeLanguage);
    }
  }

  #parseUtcDay(dateStr) {
    if (!dateStr || typeof dateStr !== 'string' || dateStr.length < 10) return NaN;
    const y = +dateStr.slice(0, 4);
    const m = +dateStr.slice(5, 7) - 1;
    const d = +dateStr.slice(8, 10);
    return Date.UTC(y, m, d);
  }

  #toLocalDateStr(dateObj) {
    const y = dateObj.getFullYear();
    const m = dateObj.getMonth() + 1;
    const d = dateObj.getDate();
    return `${y}-${m < 10 ? '0' + m : m}-${d < 10 ? '0' + d : d}`;
  }

  #isEntryActive(entry) {
    if (!entry) return false;
    if ((Number(entry.word) || Number(entry.vocab_done) || 0) > 0) return true;
    if ((Number(entry.ci) || Number(entry.ci_done) || 0) > 0) return true;
    if ((Number(entry.grammar) || Number(entry.grammar_done) || 0) > 0) return true;
    if ((Number(entry.speaking_time) || 0) > 0) return true;
    if ((Number(entry.listening_time) || 0) > 0) return true;

    const r = entry.reviews_completed;
    if (r) {
      if ((Number(r.srs_vision) || Number(entry.srs_vision_done) || 0) > 0) return true;
      if ((Number(r.srs_listen) || Number(entry.srs_listen_done) || 0) > 0) return true;
      if ((Number(r.srs_write) || Number(entry.srs_write_done) || 0) > 0) return true;
      if ((Number(r.day_revisions) || Number(entry.revisions_done) || 0) > 0) return true;
    }
    return false;
  }

  queueStreakRecalc(langCode) {
    if (!langCode) return;
    if (this.#pendingStreakTimers.has(langCode)) return;

    const timer = queueMicrotask(() => {
      this.#pendingStreakTimers.delete(langCode);
      this.recalculateStreaks(langCode);
    });
    this.#pendingStreakTimers.set(langCode, timer);
  }

  async recalculateStreaks(langCode) {
    if (!langCode) return;

    const prefix = `${langCode}:`;
    const prefixLen = prefix.length;
    const activeDatesSet = new Set();

    for (const key in this.calendarIndex) {
      if (key.startsWith(prefix)) {
        const entry = this.calendarIndex[key];
        if (this.#isEntryActive(entry)) {
          activeDatesSet.add(entry.date || entry.log_date || key.slice(prefixLen));
        }
      }
    }

    const totalDays = activeDatesSet.size;
    if (totalDays === 0) {
      await this.#commitStreakUpdate(langCode, 0, 0, 0);
      return;
    }

    const sortedDates = Array.from(activeDatesSet).sort((a, b) => b.localeCompare(a));
    const now = new Date();
    const todayStr = this.#toLocalDateStr(now);
    now.setDate(now.getDate() - 1);
    const yesterdayStr = this.#toLocalDateStr(now);

    const latestActiveDate = sortedDates[0];

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
          continue;
        } else {
          break;
        }
      }
    }

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

    await this.#commitStreakUpdate(langCode, currentStreak, finalLongest, totalDays);
  }

  async #commitStreakUpdate(langCode, currentStreak, longestStreak, totalDays) {
    const existing = this.languages[langCode] || { code: langCode, name: langCode };

    if (
      existing.current_streak === currentStreak &&
      existing.longest_streak === longestStreak &&
      existing.total_days === totalDays
    ) {
      return;
    }

    const updated = {
      ...existing,
      current_streak: currentStreak,
      longest_streak: longestStreak,
      total_days: totalDays
    };

    this.languages = {
      ...this.languages,
      [langCode]: updated
    };
    await stageLocalMutation('languages', langCode, updated);
    triggerSyncFlush();
  }

  async recordReview(langCode, date, type, subType = 'visual') {
    if (!langCode || !date) return;

    const db = await initLocalDatabase();
    const key = `${langCode}:${date}`;

    const existing = this.calendarIndex[key] || (await db.get('daily_logs', key)) || {
      id: key,
      lang_code: langCode,
      log_date: date,
      date
    };

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
      id: key,
      lang_code: langCode,
      log_date: date,
      date,
      reviews_completed: reviews,
      srs_vision_done: reviews.srs_vision,
      srs_listen_done: reviews.srs_listen,
      srs_write_done: reviews.srs_write,
      revisions_done: reviews.day_revisions
    };

    this.calendarIndex = {
      ...this.calendarIndex,
      [key]: updated
    };
    this.#cachedSortedEntries = null;
    this.#cacheVersion++;

    await stageLocalMutation('daily_logs', key, updated);
    triggerSyncFlush();
    this.queueStreakRecalc(langCode);
  }

  async refreshDayTotals(langCode, date) {
    const db = await initLocalDatabase();

    const [rawWords, rawActs] = await Promise.all([
      db.getAll('words').catch(() => []),
      db.getAll('activities').catch(() => [])
    ]);

    const allWords = rawWords.filter((w) => w.lang_code === langCode && w.log_date === date && !w.deleted_at);
    const allActs = rawActs.filter((a) => a.lang_code === langCode && a.log_date === date && !a.deleted_at);

    let vocabAudioSec = 0;
    const unvoiced_words_indices = [];

    for (let i = 0; i < allWords.length; i++) {
      const w = allWords[i];
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

    for (let i = 0; i < allActs.length; i++) {
      const act = allActs[i];
      const type = act.activity_type;

      const linkDur = Number(act.link_duration || act.durationSec || act.duration || 0);
      const audioDur = Number(act.audio_duration || 0);

      if (!isNaN(audioDur) && audioDur > 0) {
        actAudioSec += audioDur;
      }

      const itemIdx = Number(act.item_index ?? i + 1);

      if (type === 'ci') {
        ciCount++;
        ciLinkSec += linkDur;
        if (!audioDur) unvoiced_ci_indices.push(itemIdx);
      } else if (type === 'listening') {
        listeningCount++;
        pureListeningSec += linkDur;
        if (!audioDur) unvoiced_listening_indices.push(itemIdx);
      } else if (type === 'grammar') {
        grammarCount++;
        if (!audioDur) unvoiced_grammar_indices.push(itemIdx);
      }
    }

    const key = `${langCode}:${date}`;
    const rawExisting = this.calendarIndex[key] || (await db.get('daily_logs', key)) || {};
    const revision = Number(rawExisting.revision ?? 0);

    const totalSpeakingSec = vocabAudioSec + actAudioSec;

    const ciMultiplier = Math.max(1, Math.min(3, revision || 1));
    const totalListeningSec = pureListeningSec + (ciMultiplier * ciLinkSec);

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

    const existingReviews = rawExisting.reviews_completed || {};
    const reviews_completed = {
      srs_vision: Number(existingReviews.srs_vision || 0),
      srs_listen: Number(existingReviews.srs_listen || 0),
      srs_write: Number(existingReviews.srs_write || 0),
      day_revisions: Number(existingReviews.day_revisions || 0)
    };

    const updatedEntry = {
      id: key,
      lang_code: langCode,
      log_date: date,
      date,
      revision,
      due_date: rawExisting.due_date || date,

      word: allWords.length,
      ci: ciCount,
      grammar: grammarCount,
      listening: listeningCount,
      speaking_time: totalSpeakingSec,
      listening_time: totalListeningSec,

      vocab_done: allWords.length >= vocabBaseline ? 1 : 0,
      ci_done: ciCount >= ciBaseline ? 1 : 0,
      listening_done: listeningMinutes >= listeningBaseline ? 1 : 0,
      speaking_done: speakingMinutes >= speakingBaseline ? 1 : 0,
      grammar_done: grammarCount >= grammarBaseline ? 1 : 0,

      unvoiced_words_indices,
      unvoiced_ci_indices,
      unvoiced_listening_indices,
      unvoiced_grammar_indices,

      reviews_completed
    };

    this.calendarIndex = {
      ...this.calendarIndex,
      [key]: updatedEntry
    };
    this.#cachedSortedEntries = null;
    this.#cacheVersion++;

    await stageLocalMutation('daily_logs', key, updatedEntry);
    triggerSyncFlush();
    this.queueStreakRecalc(langCode);
  }

  get currentLanguageData() {
    return this.languages[this.activeLanguage] || {
      name: 'Chinese',
      code: 'zh-CN',
      current_streak: 0,
      longest_streak: 0,
      total_days: 0
    };
  }

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

  async addLanguage(languageConfig) {
    this.languages = {
      ...this.languages,
      [languageConfig.code]: languageConfig
    };
    await stageLocalMutation('languages', languageConfig.code, languageConfig);
    triggerSyncFlush();
  }

  /**
   * Deeply merges configuration overrides, saves to IndexedDB outbox,
   * and triggers an immediate sync push to the SQLite backend.
   */
  async updateLanguageConfig(code, partialConfig) {
    const existing = this.languages[code] || {};

    const updated = {
      ...existing,
      ...partialConfig,
      code,
      name: partialConfig.name || existing.name || code,
      goals: {
        ...(existing.goals || {}),
        ...(partialConfig.goals || {})
      },
      milestones: {
        ...(existing.milestones || {}),
        ...(partialConfig.milestones || {})
      },
      momentum: {
        ...(existing.momentum || {}),
        ...(partialConfig.momentum || {})
      },
      colors: {
        ...(existing.colors || {}),
        ...(partialConfig.colors || {})
      },
      tones: {
        ...(existing.tones || {}),
        ...(partialConfig.tones || {})
      }
    };

    this.languages = {
      ...this.languages,
      [code]: updated
    };

    await stageLocalMutation('languages', code, updated);
    triggerSyncFlush();
  }
}

export const metadataStore = new MetadataStore();