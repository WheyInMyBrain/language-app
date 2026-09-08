// frontend/src/lib/audioSync.js
import { CONFIG } from './config.js';
import { uploadProgressStore } from './stores/uploadProgress.svelte.js';

const DB_NAME = 'lang_app_audio_vault';
const STORE_NAME = 'offline_recordings';

function openAudioDb() {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, 1);
    req.onupgradeneeded = () => {
      const db = req.result;
      if (!db.objectStoreNames.contains(STORE_NAME)) {
        db.createObjectStore(STORE_NAME, { keyPath: 'id' });
      }
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

export function getAudioStaticUrl(lang, date, category, index) {
  const cleanIndex = String(index).replace('.webm', '');
  return `${CONFIG.AUDIO_BASE}/${lang}/${date}/${category}/${cleanIndex}.webm`;
}

export async function resolveAudioSource(lang, date, category, index, hasDuration) {
  const cleanIndex = String(index).replace('.webm', '');
  const id = `${lang}:${date}:${category}:${cleanIndex}`;
  try {
    const db = await openAudioDb();
    const tx = db.transaction(STORE_NAME, 'readonly');
    const store = tx.objectStore(STORE_NAME);
    const item = await new Promise((resolve) => {
      const req = store.get(id);
      req.onsuccess = () => resolve(req.result);
      req.onerror = () => resolve(null);
    });

    if (item && item.blob) {
      return {
        url: URL.createObjectURL(item.blob),
        duration: item.duration,
        isPendingSync: true
      };
    }
  } catch (err) {
    console.warn('[AudioVault] DB read error:', err);
  }

  if (hasDuration && Number(hasDuration) > 0) {
    return {
      url: getAudioStaticUrl(lang, date, category, index),
      duration: Number(hasDuration),
      isPendingSync: false
    };
  }

  return { url: null, duration: 0, isPendingSync: false };
}

export async function saveAudioRecord({ lang, date, category, index, blob, duration }) {
  const cleanIndex = String(index).replace('.webm', '');
  const id = `${lang}:${date}:${category}:${cleanIndex}`;
  const payload = {
    id,
    lang,
    date,
    category,
    index: cleanIndex,
    blob,
    duration,
    timestamp: Date.now()
  };

  const db = await openAudioDb();
  const tx = db.transaction(STORE_NAME, 'readwrite');
  tx.objectStore(STORE_NAME).put(payload);
  await new Promise((resolve) => (tx.oncomplete = resolve));

  return await uploadSingleRecord(payload, db);
}

/**
 * Uploads via XHR to obtain actual upload progress events
 */
function uploadSingleRecord(item, db) {
  if (!navigator.onLine) return Promise.resolve(false);

  const uploadUrl = `${CONFIG.API_BASE}/api/audio/${item.lang}/${item.date}/${item.category}/${item.index}`;

  return new Promise((resolve) => {
    const xhr = new XMLHttpRequest();
    const totalBytes = item.blob.size || 0;

    uploadProgressStore.startTask(item.id, totalBytes);

    xhr.upload.onprogress = (e) => {
      if (e.lengthComputable) {
        uploadProgressStore.updateTask(item.id, e.loaded, e.total);
      }
    };

    xhr.onload = async () => {
      uploadProgressStore.finishTask(item.id);
      if (xhr.status === 201 || xhr.status === 200) {
        try {
          const delTx = db.transaction(STORE_NAME, 'readwrite');
          delTx.objectStore(STORE_NAME).delete(item.id);
        } catch (err) {
          console.warn('[AudioSync] Failed to clear DB item:', err);
        }
        resolve(true);
      } else {
        resolve(false);
      }
    };

    xhr.onerror = () => {
      uploadProgressStore.finishTask(item.id);
      resolve(false);
    };

    xhr.open('POST', uploadUrl, true);
    xhr.setRequestHeader('Content-Type', 'audio/webm');
    xhr.send(item.blob);
  });
}

/**
 * Sequential background drain when back online
 */
export async function syncPendingAudios() {
  if (!navigator.onLine) return;

  try {
    const db = await openAudioDb();
    const tx = db.transaction(STORE_NAME, 'readonly');
    const store = tx.objectStore(STORE_NAME);
    const pendingItems = await new Promise((resolve) => {
      const req = store.getAll();
      req.onsuccess = () => resolve(req.result);
      req.onerror = () => resolve([]);
    });

    // Process sequentially to prevent network saturation on mobile connections
    for (const item of pendingItems) {
      await uploadSingleRecord(item, db);
    }
  } catch (err) {
    console.error('[AudioSync] Queue processor failure:', err);
  }
}

if (typeof window !== 'undefined') {
  window.addEventListener('online', () => syncPendingAudios());
}