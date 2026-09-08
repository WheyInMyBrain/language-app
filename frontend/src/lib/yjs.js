import * as Y from 'yjs';
import { WebsocketProvider } from 'y-websocket';
import { IndexeddbPersistence } from 'y-indexeddb';
import { CONFIG } from './config.js';

// Increment this string (e.g., 'v2', 'v3') whenever you restore a backup
// to immediately orphan and bypass stale browser IndexedDB caches on all devices.
export const DB_EPOCH = 'v1';

const activeHandles = new Map();

/**
 * Creates or retrieves a cached Yjs document synchronized with
 * local IndexedDB and the WebSocket server under the active DB_EPOCH.
 */
export function createSyncedDoc(roomName, onStatusChange = null) {
  // Prefix room name with current epoch for safe version isolation
  const namespacedRoom = `${DB_EPOCH}:${roomName}`;

  if (activeHandles.has(namespacedRoom)) {
    return activeHandles.get(namespacedRoom);
  }

  const doc = new Y.Doc();

  // 1. Instant local-first IndexedDB persistence
  const idbProvider = new IndexeddbPersistence(namespacedRoom, doc);

  // 2. Real-time WebSocket sync to Rust backend
  const wsProvider = new WebsocketProvider(CONFIG.WS_BASE, namespacedRoom, doc);

  if (onStatusChange) {
    wsProvider.on('status', ({ status }) => {
      onStatusChange(status);
    });
  }

  // Cleanup helper when leaving views or evicting docs
  const destroy = () => {
    activeHandles.delete(namespacedRoom);
    wsProvider.destroy();
    idbProvider.destroy();
    doc.destroy();
  };

  const handle = { doc, idbProvider, wsProvider, destroy };

  // Store in active cache
  activeHandles.set(namespacedRoom, handle);

  return handle;
}

/**
 * Synchronously retrieves an active room handle without creating a new connection.
 * Used by services (e.g., dailyLogService) to mutate indexes and metadata in-memory.
 */
export function getDocHandle(roomName) {
  const namespacedRoom = `${DB_EPOCH}:${roomName}`;
  return activeHandles.get(namespacedRoom) || null;
}