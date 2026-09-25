// frontend/src/lib/yjs.js
import * as Y from 'yjs';
import { WebsocketProvider } from 'y-websocket';
import { IndexeddbPersistence } from 'y-indexeddb';

const activeHandles = new Map();

function getWsUrl() {
  if (typeof window === 'undefined') return 'ws://localhost:3000/ws';
  const proto = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
  return `${proto}//${window.location.host}/ws`;
}

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

  // 2. Real-time WebSocket sync through Vite proxy
  const wsProvider = new WebsocketProvider(getWsUrl(), roomName, doc);

  if (onStatusChange) {
    wsProvider.on('status', ({ status }) => {
      onStatusChange(status);
    });
  }

  const destroy = () => {
    activeHandles.delete(roomName);
    wsProvider.destroy();
    idbProvider.destroy();
    doc.destroy();
  };

  const handle = { doc, idbProvider, wsProvider, destroy };
  activeHandles.set(roomName, handle);

  return handle;
}

export function getDocHandle(roomName) {
  return activeHandles.get(roomName) || null;
}