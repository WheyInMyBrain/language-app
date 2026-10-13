import { initLocalDatabase, stageLocalMutation } from '../db.js';
import { calculateNextSRSState } from '../srsEngine.js';
import { metadataStore } from './metadata.svelte.js';

class SrsStore {
  cards = $state({});
  isLoaded = $state(false);
  activeLang = $state(null);

  async connect(langCode) {
    if (!langCode) return;
    if (this.activeLang === langCode && this.isLoaded) return;

    this.activeLang = langCode;
    const db = await initLocalDatabase();

    // Query IndexedDB directly for word_srs matching active language
    const all = await db.getAllFromIndex('word_srs', 'by_lang', langCode);
    const cardMap = {};

    for (const card of all) {
      if (!card.deleted_at) {
        cardMap[card.card_key] = card;
      }
    }

    this.cards = cardMap;
    this.isLoaded = true;
  }

  getDueItems(todayStr, cardType = null) {
    const results = [];
    for (const [key, card] of Object.entries(this.cards)) {
      if (!card.due_date || card.due_date <= todayStr) {
        if (!cardType || card.card_type === cardType) {
          results.push({ key, ...card });
        }
      }
    }
    return results;
  }

  getDueCount(todayStr, cardType = null) {
    return this.getDueItems(todayStr, cardType).length;
  }

  getVisualDueCount(todayStr) {
    return this.getDueCount(todayStr, 'visual');
  }

  getAudioDueCount(todayStr) {
    return this.getDueCount(todayStr, 'listening');
  }

  getWritingDueCount(todayStr) {
    return this.getDueCount(todayStr, 'writing');
  }

  /**
   * Rates an SRS card, writes locally + outbox, and updates calendar metadata.
   */
  async rateCard(langCode, cardKey, grade) {
    if (!langCode || !cardKey) return null;

    const existing = this.cards[cardKey];
    if (!existing) {
      throw new Error(`Card "${cardKey}" not found in local queue.`);
    }

    const today = new Date().toISOString().slice(0, 10);

    const currentInterval = Number(existing.interval ?? 0);
    const currentEase = Number(existing.ease ?? 2.5);
    const currentReps = Number(existing.reps ?? (currentInterval > 0 ? 1 : 0));
    const currentLapses = Number(existing.lapses ?? 0);

    const nextState = calculateNextSRSState({
      currentRev: currentReps,
      currentInterval,
      currentEase,
      grade,
      todayStr: today
    });

    const isLapse = grade === 'again';
    const nextReps = isLapse ? 0 : currentReps + 1;
    const nextLapses = isLapse ? currentLapses + 1 : currentLapses;

    const { isDue, key: _omittedKey, ...persistedData } = existing;

    const updatedCard = {
      ...persistedData,
      card_key: cardKey,
      lang_code: langCode,
      interval: nextState.interval,
      ease: nextState.ease,
      due_date: nextState.due_date,
      reps: nextReps,
      lapses: nextLapses,
      last_reviewed: today
    };

    // 1. Optimistic UI update
    this.cards[cardKey] = updatedCard;

    // 2. Stage to IndexedDB and sync outbox
    await stageLocalMutation('word_srs', cardKey, updatedCard);

    // 3. Atomically record review in calendar_index
    const cardType = existing.card_type || 'visual';
    metadataStore.recordReview(langCode, today, 'srs', cardType);

    return nextState;
  }
}

export const srsStore = new SrsStore();