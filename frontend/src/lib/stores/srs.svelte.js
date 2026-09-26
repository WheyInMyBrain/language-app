// frontend/src/lib/stores/srs.svelte.js
import { createSyncedDoc, getDocHandle } from '../yjs.js';
import { calculateNextSRSState } from '../srsEngine.js';
import { metadataStore } from './metadata.svelte.js';

class SrsStore {
  cards = $state({});
  isLoaded = $state(false);
  activeRoom = $state(null);
  #docHandle = null;

  connect(langCode) {
    if (!langCode) return;
    const roomName = `${langCode}:srs`;
    if (this.activeRoom === roomName) return;

    if (this.#docHandle) {
      this.#docHandle.destroy();
      this.cards = {};
      this.isLoaded = false;
    }

    this.activeRoom = roomName;
    this.#docHandle = createSyncedDoc(roomName);

    const { doc, idbProvider, wsProvider } = this.#docHandle;
    const queueMap = doc.getMap('queue');

    const syncState = () => {
      this.cards = queueMap.toJSON();
      if (Object.keys(this.cards).length > 0) {
        this.isLoaded = true;
      }
    };

    // Initial check in case doc already has data
    syncState();

    // Observe local map changes
    queueMap.observe(syncState);

    // Sync from IndexedDB
    idbProvider.on('synced', () => {
      syncState();
      this.isLoaded = true;
    });

    // Sync from WebSocket server (catches the server blob arrival)
    if (wsProvider) {
      wsProvider.on('sync', (isSynced) => {
        if (isSynced) {
          syncState();
          this.isLoaded = true;
        }
      });
    }

    // Direct Y.Doc update listener catches incoming remote binary changes
    doc.on('update', () => {
      syncState();
    });
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
   * Rates an SRS card, tracks lapses & last_reviewed, and records review count in calendar_index.
   */
  async rateCard(langCode, cardKey, grade) {
    if (!langCode || !cardKey) return null;

    const handle = this.#docHandle || getDocHandle(`${langCode}:srs`);
    if (!handle?.doc) {
      throw new Error(`Yjs document for "${langCode}:srs" not found.`);
    }

    const queueMap = handle.doc.getMap('queue');
    const existing = queueMap.get(cardKey);
    if (!existing) {
      throw new Error(`Card "${cardKey}" not found in queue.`);
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

    // Prune transient UI keys before writing to Yjs
    const { isDue, key: _omittedKey, ...persistedData } = existing;

    handle.doc.transact(() => {
      queueMap.set(cardKey, {
        ...persistedData,
        interval: nextState.interval,
        ease: nextState.ease,
        due_date: nextState.due_date,
        reps: nextReps,
        lapses: nextLapses,
        last_reviewed: today
      });
    });

    // 🌟 Atomically record SRS review in today's calendar_index entry
    const cardType = existing.card_type || 'visual';
    metadataStore.recordReview(langCode, today, 'srs', cardType);

    return nextState;
  }
}

export const srsStore = new SrsStore();