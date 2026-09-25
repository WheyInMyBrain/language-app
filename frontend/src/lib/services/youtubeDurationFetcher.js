/**
 * frontend/src/lib/services/youtubeDurationFetcher.js
 * Production YouTube duration resolver using the official YouTube Iframe Player API.
 * 100% Client-side, zero API key required, silent execution.
 */
import { extractYouTubeId, formatSecondsToTimer } from '../mediaResolver.js';

const cache = new Map();
let apiPromise = null;

/**
 * Loads the YouTube Iframe API script once.
 */
function ensureYouTubeIframeAPI() {
  if (window.YT && window.YT.Player) {
    return Promise.resolve(window.YT);
  }

  if (apiPromise) return apiPromise;

  apiPromise = new Promise((resolve) => {
    if (!document.getElementById('yt-iframe-api-tag')) {
      const tag = document.createElement('script');
      tag.id = 'yt-iframe-api-tag';
      tag.src = 'https://www.youtube.com/iframe_api';
      document.head.appendChild(tag);
    }

    const previousOnReady = window.onYouTubeIframeAPIReady;
    window.onYouTubeIframeAPIReady = () => {
      if (typeof previousOnReady === 'function') previousOnReady();
      resolve(window.YT);
    };

    const pollInterval = setInterval(() => {
      if (window.YT && window.YT.Player) {
        clearInterval(pollInterval);
        resolve(window.YT);
      }
    }, 100);
  });

  return apiPromise;
}

/**
 * Resolves duration by creating a brief 1px sandbox player
 */
function resolveViaIframePlayer(videoId) {
  return new Promise(async (resolve) => {
    try {
      const YT = await ensureYouTubeIframeAPI();

      const mount = document.createElement('div');
      mount.id = `yt-probe-${videoId}-${Date.now()}`;
      mount.style.position = 'fixed';
      mount.style.left = '-1000px';
      mount.style.top = '-1000px';
      mount.style.width = '1px';
      mount.style.height = '1px';
      mount.style.overflow = 'hidden';
      mount.style.pointerEvents = 'none';
      document.body.appendChild(mount);

      let player = null;
      let checkInterval = null;
      let timeoutTimer = null;

      const cleanup = () => {
        if (checkInterval) clearInterval(checkInterval);
        if (timeoutTimer) clearTimeout(timeoutTimer);
        if (player && typeof player.destroy === 'function') {
          try { player.destroy(); } catch (_) {}
        }
        if (mount && mount.parentNode) {
          mount.parentNode.removeChild(mount);
        }
      };

      timeoutTimer = setTimeout(() => {
        cleanup();
        resolve(0);
      }, 6000);

      player = new YT.Player(mount.id, {
        videoId,
        playerVars: {
          autoplay: 0,
          controls: 0,
          disablekb: 1,
          fs: 0,
          rel: 0,
          mute: 1
        },
        events: {
          onReady: (event) => {
            checkInterval = setInterval(() => {
              try {
                const duration = event.target.getDuration();
                if (duration && duration > 0) {
                  const sec = Math.round(duration);
                  cleanup();
                  resolve(sec);
                }
              } catch (_) {}
            }, 100);
          },
          onError: () => {
            cleanup();
            resolve(0);
          }
        }
      });
    } catch (_) {
      resolve(0);
    }
  });
}

/**
 * Main Exported Fetcher
 */
export async function fetchYouTubeDuration(url) {
  if (!url || typeof url !== 'string') return null;

  const videoId = extractYouTubeId(url);
  if (!videoId) return null;

  if (cache.has(videoId)) {
    return cache.get(videoId);
  }

  // 1. Resolve duration through YouTube's native Player API
  let durationSec = await resolveViaIframePlayer(videoId);

  // 2. Fallback: Check if URL had an explicit start/resume timestamp (?t=...)
  if (!durationSec || durationSec <= 0) {
    try {
      const parsed = new URL(url.trim());
      const t = parsed.searchParams.get('t') || parsed.searchParams.get('start');
      if (t) {
        const sec = parseInt(t.replace(/s$/, ''), 10);
        if (!isNaN(sec) && sec > 0) {
          durationSec = sec;
        }
      }
    } catch (_) {}
  }

  if (durationSec > 0) {
    const result = {
      seconds: durationSec,
      formatted: formatSecondsToTimer(durationSec)
    };
    cache.set(videoId, result);
    return result;
  }

  return null;
}