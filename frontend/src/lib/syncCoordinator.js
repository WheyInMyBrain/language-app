import { initLocalDatabase } from './db.js';
import { metadataStore } from './stores/metadata.svelte.js';
import { vocabIndexStore } from './stores/vocabIndex.svelte.js';
import { ciIndexStore } from './stores/ciIndex.svelte.js';
import { listeningIndexStore } from './stores/listeningIndex.svelte.js';
import { srsStore } from './stores/srs.svelte.js';

class SyncCoordinator {
  #isSyncing = false;
  #isFlushing = false;
  #syncIntervalId = null;
  #eventSource = null;
  #reconnectTimer = null;
  #debounceTimer = null;
  #flushDebounceTimer = null;

  init() {
    if (typeof window === 'undefined') return;

    // 1. Recover stream and trigger full sync when coming back online
    window.addEventListener('online', () => {
      this.connectEventStream();
      this.syncAll();
    });

    // 2. Tear down stream when going offline
    window.addEventListener('offline', () => {
      this.disconnectEventStream();
    });

    // 3. Trigger foreground recovery on tab focus
    document.addEventListener('visibilitychange', () => {
      if (document.visibilityState === 'visible') {
        if (!this.#eventSource) this.connectEventStream();
        this.syncAll();
      }
    });

    // 4. Fallback background sync heartbeat (every 60s)
    this.#syncIntervalId = setInterval(() => {
      if (navigator.onLine) this.syncAll();
    }, 60_000);

    // 5. Connect SSE stream on startup
    this.connectEventStream();
  }

  /**
   * Micro-debounced flush called by stores right after stageLocalMutation
   */
  scheduleFlush() {
    if (typeof window === 'undefined' || !navigator.onLine) return;
    if (this.#flushDebounceTimer) clearTimeout(this.#flushDebounceTimer);
    this.#flushDebounceTimer = setTimeout(() => {
      this.flushOutbox().catch((err) => {
        console.warn('[SyncCoordinator] Debounced flush failed:', err);
      });
    }, 300);
  }

  connectEventStream() {
    if (this.#eventSource || !navigator.onLine) return;
    if (this.#reconnectTimer) {
      clearTimeout(this.#reconnectTimer);
      this.#reconnectTimer = null;
    }

    try {
      this.#eventSource = new EventSource('/api/sync/events');

      this.#eventSource.addEventListener('sync', (e) => {
        const lang = e.data?.trim();
        if (this.#debounceTimer) clearTimeout(this.#debounceTimer);
        this.#debounceTimer = setTimeout(() => {
          this.pullDeltas(lang || null).catch((err) => {
            console.warn('[SyncCoordinator] SSE-triggered delta pull failed:', err);
          });
        }, 100);
      });

      this.#eventSource.onerror = () => {
        this.disconnectEventStream();
        this.#reconnectTimer = setTimeout(() => {
          this.connectEventStream();
        }, 4000);
      };
    } catch (err) {
      console.warn('[SyncCoordinator] SSE connection attempt failed:', err);
    }
  }

  disconnectEventStream() {
    if (this.#reconnectTimer) {
      clearTimeout(this.#reconnectTimer);
      this.#reconnectTimer = null;
    }
    if (this.#eventSource) {
      this.#eventSource.close();
      this.#eventSource = null;
    }
  }

  async syncAll(activeLang = null) {
    if (this.#isSyncing || !navigator.onLine) return;
    this.#isSyncing = true;

    try {
      // 1. Flush local outbox mutations to the backend first
      await this.flushOutbox();

      // 2. Pull remote deltas downstream
      const lang = activeLang || metadataStore.activeLanguage;
      await this.pullDeltas(lang);
    } catch (err) {
      console.warn('[SyncCoordinator] Sync pass paused (will retry):', err);
    } finally {
      this.#isSyncing = false;
    }
  }

  async flushOutbox() {
    if (this.#isFlushing || !navigator.onLine) return;
    this.#isFlushing = true;

    try {
      const db = await initLocalDatabase();
      const pending = await db.getAllFromIndex('outbox', 'by_timestamp');
      if (!pending || pending.length === 0) return;

      // Track exact mutation IDs being sent in this flight
      const processedIds = pending.map((m) => m.mutation_id);

      const payload = {
        mutations: pending.map((m) => ({
          table: m.table,
          key: m.record_key,
          data: m.payload
        }))
      };

      const res = await fetch('/api/sync/push', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
      });

      if (!res.ok) throw new Error(`Push failed with HTTP ${res.status}`);

      const ack = await res.json();
      if (ack.status === 'ok') {
        const tx = db.transaction('outbox', 'readwrite');
        for (const id of processedIds) {
          await tx.store.delete(id);
        }
        await tx.done;
      }
    } finally {
      this.#isFlushing = false;
    }
  }

  async pullDeltas(langCode = null) {
    const db = await initLocalDatabase();
    const scopeKey = 'global';
    const cursorRecord = await db.get('sync_cursors', scopeKey);
    let sinceTimestamp = cursorRecord?.last_synced_at || 0;

    const url = new URL('/api/sync/pull', window.location.origin);
    url.searchParams.set('since', String(sinceTimestamp));

    const res = await fetch(url.toString());
    if (!res.ok) throw new Error(`Pull failed with HTTP ${res.status}`);

    const delta = await res.json();
    const { server_time, languages, daily_logs, words, activities, word_srs } = delta;

    // Detect if the server instance was recreated or time jumped backwards
    if (server_time && sinceTimestamp > 0 && server_time < sinceTimestamp) {
      console.warn('[SyncCoordinator] Server instance reset detected. Resetting cursor to 0.');
      await db.put('sync_cursors', { scope: scopeKey, last_synced_at: 0 });
      return this.pullDeltas(langCode);
    }

    let hasChanges = false;
    const tx = db.transaction(
      ['languages', 'daily_logs', 'words', 'activities', 'word_srs', 'sync_cursors'],
      'readwrite'
    );

    const applyLww = async (storeName, items, keyField) => {
      if (!items || items.length === 0) return;
      const store = tx.objectStore(storeName);
      for (const item of items) {
        const existing = await store.get(item[keyField]);
        if (!existing || item.updated_at >= (existing.updated_at || 0)) {
          hasChanges = true;
          if (item.deleted_at) {
            await store.delete(item[keyField]);
          } else {
            await store.put(item);
          }
        }
      }
    };

    await applyLww('languages', languages, 'code');
    await applyLww('daily_logs', daily_logs, 'id');
    await applyLww('words', words, 'id');
    await applyLww('activities', activities, 'id');
    await applyLww('word_srs', word_srs, 'card_key');

    if (server_time) {
      await tx.objectStore('sync_cursors').put({
        scope: scopeKey,
        last_synced_at: server_time
      });
    }

    await tx.done;

    // Rehydrate active stores if remote mutations were merged
    if (hasChanges) {
      const targetLang = langCode || metadataStore.activeLanguage;
      await Promise.all([
        metadataStore.init(true),
        vocabIndexStore.refresh ? vocabIndexStore.refresh() : Promise.resolve(),
        ciIndexStore.refresh ? ciIndexStore.refresh() : Promise.resolve(),
        listeningIndexStore.refresh ? listeningIndexStore.refresh() : Promise.resolve(),
        srsStore.connect ? srsStore.connect(targetLang) : Promise.resolve()
      ]);
    }
  }
}

export const syncCoordinator = new SyncCoordinator();