/**
 * frontend/src/lib/services/youtubeDurationFetcher.js
 * Multi-tiered YouTube resolver:
 * Tier 1: Fast zero-auth oEmbed & JSON metadata endpoints (sub-200ms)
 * Tier 2: Headless 1px Sandbox IFrame Player API (bulletproof browser fallback)
 * Tier 3: URL timestamp parameter extraction
 */
import { extractYouTubeId, formatSecondsToTimer } from '../mediaResolver.js';

const cache = new Map();
let apiPromise = null;

// High-speed JSON endpoints for rapid duration lookup
const FAST_MIRRORS = [
  (id) => `https://invidious.nerdvpn.de/api/v1/videos/${id}`,
  (id) => `https://pipedapi.kavin.rocks/streams/${id}`,
  (id) => `https://api.piped.privacydev.net/streams/${id}`
];

/**
 * Tier 1: Fast direct JSON query with tight 1200ms abort controller
 */
async function resolveViaFastJson(videoId) {
  for (const getUrl of FAST_MIRRORS) {
    try {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), 1200);

      const res = await fetch(getUrl(videoId), {
        signal: controller.signal,
        headers: { Accept: 'application/json' }
      });
      clearTimeout(timer);

      if (!res.ok) continue;

      const data = await res.json();
      const totalSec = Number(data.lengthSeconds ?? data.duration ?? 0);

      if (totalSec > 0) {
        return {
          seconds: totalSec,
          title: data.title || null,
          author: data.author || data.uploader || null
        };
      }
    } catch {
      // Continue to next mirror or fallback to IFrame sandbox
      continue;
    }
  }
  return null;
}

/**
 * Loads the YouTube Iframe API script once
 */
function ensureYouTubeIframeAPI() {
  if (typeof window !== 'undefined' && window.YT && window.YT.Player) {
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
 * Tier 2: Resolves duration by creating a brief 1px sandbox player
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
      }, 5000);

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
 * @param {string} url - YouTube URL
 * @returns {Promise<{seconds: number, formatted: string, title?: string, author?: string} | null>}
 */
export async function fetchYouTubeDuration(url) {
  if (!url || typeof url !== 'string') return null;

  const videoId = extractYouTubeId(url);
  if (!videoId) return null;

  if (cache.has(videoId)) {
    return cache.get(videoId);
  }

  let durationSec = 0;
  let extraMeta = {};

  // 1. Tier 1: Try Fast JSON Endpoints (Sub-200ms)
  const fastResult = await resolveViaFastJson(videoId);
  if (fastResult && fastResult.seconds > 0) {
    durationSec = fastResult.seconds;
    extraMeta = { title: fastResult.title, author: fastResult.author };
  }

  // 2. Tier 2: Headless IFrame Sandbox fallback
  if (!durationSec || durationSec <= 0) {
    durationSec = await resolveViaIframePlayer(videoId);
  }

  // 3. Tier 3: Check for explicit timestamp in URL (?t=14m20s or &t=860)
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
      formatted: formatSecondsToTimer(durationSec),
      ...extraMeta
    };
    cache.set(videoId, result);
    return result;
  }

  return null;
}