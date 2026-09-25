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
   * Recalculates and updates calendar_index for a specific day
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

    // 3. Write directly to root calendar_index
    const calendarMap = this.#docHandle.doc.getMap('calendar_index');
    const key = `${langCode}:${date}`;
    const existing = calendarMap.get(key) || { date };

    const updatedEntry = {
      ...existing,
      date,
      revision,
      word: words.length,
      ci: ciCount,
      grammar: grammarCount,
      listening: listeningCount,
      speaking_time: totalSpeakingSec,
      listening_time: totalListeningSec,
      due_date: session.due_date || existing.due_date || null
    };

    this.#docHandle.doc.transact(() => {
      calendarMap.set(key, updatedEntry);
    });

    // Explicitly update reactive state so dashboard re-renders instantly
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