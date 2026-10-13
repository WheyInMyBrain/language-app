// frontend/src/lib/db.js
import { openDB } from 'idb';

const DB_NAME = 'PolyglotPWA';
const DB_VERSION = 1;

let dbPromise = null;

export function getDb() {
  if (!dbPromise) {
    dbPromise = openDB(DB_NAME, DB_VERSION, {
      upgrade(db) {
        if (!db.objectStoreNames.contains('languages')) {
          db.createObjectStore('languages', { keyPath: 'code' });
        }
        if (!db.objectStoreNames.contains('daily_logs')) {
          const store = db.createObjectStore('daily_logs', { keyPath: 'id' });
          store.createIndex('by_lang_date', ['lang_code', 'log_date']);
          store.createIndex('by_lang', 'lang_code');
        }
        if (!db.objectStoreNames.contains('words')) {
          const store = db.createObjectStore('words', { keyPath: 'id' });
          store.createIndex('by_lang_date', ['lang_code', 'log_date']);
          store.createIndex('by_lang', 'lang_code');
        }
        if (!db.objectStoreNames.contains('activities')) {
          const store = db.createObjectStore('activities', { keyPath: 'id' });
          store.createIndex('by_lang_date', ['lang_code', 'log_date']);
          store.createIndex('by_type', ['lang_code', 'activity_type']);
        }
        if (!db.objectStoreNames.contains('word_srs')) {
          const store = db.createObjectStore('word_srs', { keyPath: 'card_key' });
          store.createIndex('by_lang', 'lang_code');
          store.createIndex('by_lang_due', ['lang_code', 'due_date']);
        }
        if (!db.objectStoreNames.contains('outbox')) {
          const outbox = db.createObjectStore('outbox', { keyPath: 'mutation_id' });
          outbox.createIndex('by_timestamp', 'created_at');
        }
        if (!db.objectStoreNames.contains('sync_cursors')) {
          db.createObjectStore('sync_cursors', { keyPath: 'scope' });
        }
      },
      blocked() {
        console.warn('[IndexedDB] Database open blocked. Close other tabs running this app.');
      },
      blocking() {
        if (dbPromise) {
          dbPromise.then((db) => db.close());
          dbPromise = null;
        }
      }
    });
  }
  return dbPromise;
}

export const initLocalDatabase = getDb;

/**
 * Safely strips Svelte 5 $state Proxies and non-serializable fields
 */
function toCloneable(val) {
  if (val === null || val === undefined) return val;
  try {
    return JSON.parse(JSON.stringify(val));
  } catch {
    return val;
  }
}

/**
 * Atomic Local Write-Ahead Transaction
 */
export async function stageLocalMutation(table, recordKey, recordData) {
  const db = await getDb();
  const now = Date.now();
  
  // Strip Svelte Proxies so IndexedDB's Structured Clone Algorithm never throws
  const cleanData = toCloneable(recordData);

  const payload = {
    ...cleanData,
    updated_at: now
  };

  const mutationId = `${table}#${recordKey}#${now}`;

  const tx = db.transaction([table, 'outbox'], 'readwrite');
  await tx.objectStore(table).put(payload);
  await tx.objectStore('outbox').put({
    mutation_id: mutationId,
    table,
    record_key: recordKey,
    payload,
    created_at: now
  });
  await tx.done;

  return payload;
}