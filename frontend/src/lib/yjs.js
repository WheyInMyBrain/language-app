import * as Y from 'yjs';
import { WebsocketProvider } from 'y-websocket';
import { IndexeddbPersistence } from 'y-indexeddb';
import { CONFIG } from './config.js';

const activeHandles = new Map();

/**
 * Creates or retrieves a cached Yjs document synchronized with
 * local IndexedDB and the WebSocket server.
 */
export function createSyncedDoc(roomName, onStatusChange = null) {
  if (activeHandles.has(roomName)) {
    return activeHandles.get(roomName);
  }

  const doc = new Y.Doc();

  // 1. Instant local-first IndexedDB persistence
  const idbProvider = new IndexeddbPersistence(roomName, doc);

  // 2. Real-time WebSocket sync to Rust backend
  const wsProvider = new WebsocketProvider(CONFIG.WS_BASE, roomName, doc);

  if (onStatusChange) {
    wsProvider.on('status', ({ status }) => {
      onStatusChange(status);
    });
  }

  // Cleanup helper when leaving views or evicting docs
  const destroy = () => {
    activeHandles.delete(roomName);
    wsProvider.destroy();
    idbProvider.destroy();
    doc.destroy();
  };

  const handle = { doc, idbProvider, wsProvider, destroy };

  // Store in active cache
  activeHandles.set(roomName, handle);

  return handle;
}

/**
 * Synchronously retrieves an active room handle without creating a new connection.
 * Used by services (e.g., dailyLogService) to mutate indexes and metadata in-memory.
 */
export function getDocHandle(roomName) {
  return activeHandles.get(roomName) || null;
}