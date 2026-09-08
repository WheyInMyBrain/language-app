// Automatically use window.location.hostname so phone on LAN connects cleanly
const HOST = typeof window !== 'undefined' ? window.location.hostname : 'localhost';

export const CONFIG = {
  WS_BASE: `ws://${HOST}:8080/ws`,
  API_BASE: `http://${HOST}:8080`,
  AUDIO_BASE: `http://${HOST}:8080/audio`,
  ROOM_METADATA: 'global:metadata',
};