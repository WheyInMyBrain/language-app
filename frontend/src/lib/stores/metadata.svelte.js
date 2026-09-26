// frontend/src/lib/stores/metadata.svelte.js
import { createSyncedDoc, getDocHandle } from '../yjs.js';

const ROOM_METADATA = 'global:metadata';

class MetadataStore {
  connectionStatus = $state('connecting'); // 'connecting' | 'connected' | 'disconnected'
  isLocalLoaded = $state(false);
  languages = $state({});
  calendarIndex = $state({});
  activeLanguage = $state('zh-CN');

  #docHandle = null;

  init() {
    if (this.#docHandle) return;

    this.#docHandle = createSyncedDoc(ROOM_METADATA, (status) => {
      this.connectionStatus = status;
    });

    const { doc, idbProvider } = this.#docHandle;

    const langsMap = doc.getMap('languages');
    const calendarMap = doc.getMap('calendar_index');

    const syncState = () => {
      this.languages = langsMap.toJSON();
      this.calendarIndex = calendarMap.toJSON();

      // Default to first available language if activeLanguage isn't present
      const keys = Object.keys(this.languages);
      if (keys.length > 0 && !this.languages[this.activeLanguage]) {
        this.activeLanguage = keys[0];
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
   * Atomically records a completed review (SRS card or Day Revision) into calendar_index.
   *
   * @param {string} langCode - Language code (e.g. 'zh-CN')
   * @param {string} date - Date of review (YYYY-MM-DD)
   * @param {'srs' | 'day_revision'} type
   * @param {'visual' | 'listening' | 'writing'} [subType] - SRS deck type
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

    this.calendarIndex = {
      ...this.calendarIndex,
      [key]: updated
    };
  }

  /**
   * Recalculates and updates calendar_index for a specific day,
   * preserving reviews_completed while auditing unvoiced items and completion flags.
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

    // Deep-extract items to safely handle plain objects or Y.Maps
    const rawWords = dayDoc.getArray('words').toArray();
    const words = rawWords.map(w => (typeof w.toJSON === 'function' ? w.toJSON() : w)).flat();

    const rawActivities = dayDoc.getArray('activities').toArray();
    const activities = rawActivities.map(a => (typeof a.toJSON === 'function' ? a.toJSON() : a)).flat();

    // 1. Calculate Speaking Time (Sum of all audio durations)
    let vocabAudioSec = 0;
    for (const w of words) {
      const dur = Number(w.audio_duration);
      if (!isNaN(dur) && dur > 0) vocabAudioSec += dur;
    }

    let actAudioSec = 0;
    let ciLinkSec = 0;
    let pureListeningSec = 0;
    let ciCount = 0;
    let grammarCount = 0;
    let listeningCount = 0;

    for (const act of activities) {
      const type = act.activity_type;
      const linkDur = Number(act.link_duration || act.durationSec) || 0;
      const audioDur = Number(act.audio_duration) || 0;

      if (!isNaN(audioDur) && audioDur > 0) {
        actAudioSec += audioDur;
      }

      if (type === 'ci') {
        ciCount++;
        ciLinkSec += linkDur;
      } else if (type === 'listening') {
        listeningCount++;
        pureListeningSec += linkDur;
      } else if (type === 'grammar') {
        grammarCount++;
      }
    }

    const totalSpeakingSec = vocabAudioSec + actAudioSec;

    // 2. Calculate Listening Time: min(3, rev) * CI + listening
    const ciMultiplier = Math.min(3, revision);
    const totalListeningSec = pureListeningSec + (ciMultiplier * ciLinkSec);

    // 3. Extract Unvoiced Indices (audio_duration missing or <= 0)
    const unvoiced_words_indices = words
      .filter((w) => !w.audio_duration || Number(w.audio_duration) <= 0)
      .map((w, idx) => Number(w.word_index ?? idx + 1));

    const unvoiced_ci_indices = activities
      .filter((a) => a.activity_type === 'ci' && (!a.audio_duration || Number(a.audio_duration) <= 0))
      .map((a, idx) => Number(a.item_index ?? idx + 1));

    const unvoiced_listening_indices = activities
      .filter((a) => a.activity_type === 'listening' && (!a.audio_duration || Number(a.audio_duration) <= 0))
      .map((a, idx) => Number(a.item_index ?? idx + 1));

    const unvoiced_grammar_indices = activities
      .filter((a) => a.activity_type === 'grammar' && (!a.audio_duration || Number(a.audio_duration) <= 0))
      .map((a, idx) => Number(a.item_index ?? idx + 1));

    // 4. Evaluate Goal Completion Flags
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

    const vocab_done = words.length >= vocabBaseline;
    const ci_done = ciCount >= ciBaseline;
    const grammar_done = grammarCount >= grammarBaseline;
    const listening_done = listeningMinutes >= listeningBaseline;
    const speaking_done = speakingMinutes >= speakingBaseline;

    // 5. Write directly to root calendar_index (preserving reviews_completed)
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

      // Quantities
      word: words.length,
      ci: ciCount,
      grammar: grammarCount,
      listening: listeningCount,
      speaking_time: totalSpeakingSec,
      listening_time: totalListeningSec,

      // Completion flags
      vocab_done,
      ci_done,
      listening_done,
      speaking_done,
      grammar_done,

      // Unvoiced audit indices for Siphon Engine
      unvoiced_words_indices,
      unvoiced_ci_indices,
      unvoiced_listening_indices,
      unvoiced_grammar_indices,

      // Preserved reviews completed telemetry
      reviews_completed
    };

    this.#docHandle.doc.transact(() => {
      calendarMap.set(key, updatedEntry);
    });

    this.calendarIndex = {
      ...this.calendarIndex,
      [key]: updatedEntry
    };
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

  get sortedCalendarEntries() {
    return Object.entries(this.calendarIndex)
      .filter(([key]) => key.startsWith(`${this.activeLanguage}:`))
      .map(([key, data]) => ({
        key,
        date: key.split(':')[1],
        ...data,
      }))
      .sort((a, b) => b.date.localeCompare(a.date));
  }

  /**
   * Adds a new language document to the global registry
   */
  addLanguage(languageConfig) {
    if (!this.#docHandle?.doc) return;
    const doc = this.#docHandle.doc;
    const langsMap = doc.getMap('languages');

    doc.transact(() => {
      langsMap.set(languageConfig.code, languageConfig);
    });

    this.languages = langsMap.toJSON();
  }

  /**
   * Updates an existing language configuration (goals, colors, tones)
   */
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
      colors: { ...(existing.colors || {}), ...(partialConfig.colors || {}) },
      tones: { ...(existing.tones || {}), ...(partialConfig.tones || {}) }
    };

    doc.transact(() => {
      langsMap.set(code, updated);
    });

    this.languages = langsMap.toJSON();
  }
}

export const metadataStore = new MetadataStore();