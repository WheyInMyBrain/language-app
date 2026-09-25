/**
 * frontend/src/lib/yjs.js
 * Single Shared Multiplexed WebSocket Provider for Yjs.
 * Manages 1 physical WebSocket connection for unlimited concurrent rooms.
 */
import * as Y from 'yjs';
import { IndexeddbPersistence } from 'y-indexeddb';
import * as syncProtocol from 'y-protocols/sync';
import * as encoding from 'lib0/encoding';
import * as decoding from 'lib0/decoding';

const MSG_SUBSCRIBE = 0x01;
const MSG_UNSUBSCRIBE = 0x02;
const MSG_PAYLOAD = 0x03;

class MultiplexedWsClient {
  constructor() {
    this.ws = null;
    this.rooms = new Map(); // roomName -> Set<{ doc, onStatusChange }>
    this.status = 'disconnected'; // 'connecting' | 'connected' | 'disconnected'
    this.reconnectTimer = null;
  }

  getWsUrl() {
    if (typeof window === 'undefined') return 'ws://localhost:3000/ws';
    const proto = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    return `${proto}//${window.location.host}/ws`;
  }

  connect() {
    if (this.ws && (this.ws.readyState === WebSocket.OPEN || this.ws.readyState === WebSocket.CONNECTING)) {
      return;
    }

    this.status = 'connecting';
    this.notifyAllStatus('connecting');

    try {
      this.ws = new WebSocket(this.getWsUrl());
      this.ws.binaryType = 'arraybuffer';

      this.ws.onopen = () => {
        this.status = 'connected';
        this.notifyAllStatus('connected');

        // Resubscribe all active rooms on reconnect
        for (const [roomName, handlers] of this.rooms.entries()) {
          this.sendSubscribe(roomName);
          // Send local Step 1 sync for each room
          for (const { doc } of handlers) {
            const encoder = encoding.createEncoder();
            syncProtocol.writeSyncStep1(encoder, doc);
            this.sendPayload(roomName, encoding.toUint8Array(encoder));
          }
        }
      };

      this.ws.onmessage = (event) => {
        this.handleMessage(new Uint8Array(event.data));
      };

      this.ws.onclose = () => {
        this.status = 'disconnected';
        this.notifyAllStatus('disconnected');
        this.scheduleReconnect();
      };

      this.ws.onerror = () => {
        this.ws?.close();
      };
    } catch {
      this.scheduleReconnect();
    }
  }

  scheduleReconnect() {
    if (this.reconnectTimer) return;
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = null;
      if (this.rooms.size > 0) {
        this.connect();
      }
    }, 2500);
  }

  notifyAllStatus(status) {
    for (const handlers of this.rooms.values()) {
      for (const { onStatusChange } of handlers) {
        if (onStatusChange) onStatusChange(status);
      }
    }
  }

  sendSubscribe(roomName) {
    if (this.ws?.readyState !== WebSocket.OPEN) return;
    const nameBytes = new TextEncoder().encode(roomName);
    const buf = new Uint8Array(3 + nameBytes.length);
    buf[0] = MSG_SUBSCRIBE;
    buf[1] = (nameBytes.length >> 8) & 0xff;
    buf[2] = nameBytes.length & 0xff;
    buf.set(nameBytes, 3);
    this.ws.send(buf);
  }

  sendUnsubscribe(roomName) {
    if (this.ws?.readyState !== WebSocket.OPEN) return;
    const nameBytes = new TextEncoder().encode(roomName);
    const buf = new Uint8Array(3 + nameBytes.length);
    buf[0] = MSG_UNSUBSCRIBE;
    buf[1] = (nameBytes.length >> 8) & 0xff;
    buf[2] = nameBytes.length & 0xff;
    buf.set(nameBytes, 3);
    this.ws.send(buf);
  }

  sendPayload(roomName, payload) {
    if (this.ws?.readyState !== WebSocket.OPEN) return;
    const nameBytes = new TextEncoder().encode(roomName);
    const buf = new Uint8Array(3 + nameBytes.length + payload.length);
    buf[0] = MSG_PAYLOAD;
    buf[1] = (nameBytes.length >> 8) & 0xff;
    buf[2] = nameBytes.length & 0xff;
    buf.set(nameBytes, 3);
    buf.set(payload, 3 + nameBytes.length);
    this.ws.send(buf);
  }

  handleMessage(buf) {
    if (buf.length < 3) return;
    const flag = buf[0];
    const nameLen = (buf[1] << 8) | buf[2];
    if (buf.length < 3 + nameLen) return;

    const roomName = new TextDecoder().decode(buf.subarray(3, 3 + nameLen));
    const payload = buf.subarray(3 + nameLen);

    if (flag === MSG_PAYLOAD) {
      const handlers = this.rooms.get(roomName);
      if (!handlers) return;

      for (const { doc } of handlers) {
        const decoder = decoding.createDecoder(payload);
        const encoder = encoding.createEncoder();
        
        doc.transact(() => {
          syncProtocol.readSyncMessage(decoder, encoder, doc, this);
        });

        // If reading sync generated a response (e.g., Step 2 in response to Step 1)
        if (encoding.length(encoder) > 0) {
          this.sendPayload(roomName, encoding.toUint8Array(encoder));
        }
      }
    }
  }

  registerRoom(roomName, doc, onStatusChange) {
    if (!this.rooms.has(roomName)) {
      this.rooms.set(roomName, new Set());
      this.sendSubscribe(roomName);
    }

    const handler = { doc, onStatusChange };
    this.rooms.get(roomName).add(handler);

    // Initial connection trigger
    this.connect();

    // Hook Yjs local updates to broadcast to Rust backend
    const onDocUpdate = (update, origin) => {
      if (origin !== this) {
        const encoder = encoding.createEncoder();
        syncProtocol.writeUpdate(encoder, update);
        this.sendPayload(roomName, encoding.toUint8Array(encoder));
      }
    };
    doc.on('update', onDocUpdate);

    // Return cleanup hook
    return () => {
      doc.off('update', onDocUpdate);
      const set = this.rooms.get(roomName);
      if (set) {
        set.delete(handler);
        if (set.size === 0) {
          this.rooms.delete(roomName);
          this.sendUnsubscribe(roomName);
        }
      }
    };
  }
}

// Single global multiplexer instance
const multiplexer = new MultiplexedWsClient();
const activeHandles = new Map();

/**
 * Creates or retrieves a cached Yjs document synchronized with
 * local IndexedDB and the shared multiplexed WebSocket server.
 */
export function createSyncedDoc(roomName, onStatusChange = null) {
  if (activeHandles.has(roomName)) {
    return activeHandles.get(roomName);
  }

  const doc = new Y.Doc();

  // 1. Instant local IndexedDB persistence
  const idbProvider = new IndexeddbPersistence(roomName, doc);

  // 2. Register with single shared WebSocket multiplexer
  const unregister = multiplexer.registerRoom(roomName, doc, onStatusChange);

  const destroy = () => {
    activeHandles.delete(roomName);
    unregister();
    idbProvider.destroy();
    doc.destroy();
  };

  const handle = { doc, idbProvider, destroy };
  activeHandles.set(roomName, handle);

  return handle;
}

export function getDocHandle(roomName) {
  return activeHandles.get(roomName) || null;
}