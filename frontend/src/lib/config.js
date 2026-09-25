/**
 * frontend/src/lib/config.js
 * Relative path configurations leveraging Vite's dev proxy and production relative routing.
 */

// Dynamically compute WebSocket endpoint based on current host & protocol
function getWebSocketBase() {
  if (typeof window === 'undefined') return 'ws://localhost:3000/ws';
  const proto = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
  return `${proto}//${window.location.host}/ws`;
}

export const CONFIG = {
  WS_BASE: getWebSocketBase(),
  API_BASE: '',        // Relative: queries like /api/... go directly through Vite proxy
  AUDIO_BASE: '/audio', // Relative: queries like /audio/... go through Vite proxy
  MEDIA_BASE: '/media', // Relative: queries like /media/... go through Vite proxy
  ROOM_METADATA: 'global:metadata',
};