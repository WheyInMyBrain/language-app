/**
 * frontend/src/lib/mediaResolver.js
 * Comprehensive media parser, duration converter, and YouTube timestamp extractor
 */

/**
 * Extracts YouTube Video ID if present
 */
export function extractYouTubeId(url) {
  if (!url) return null;
  const match = url.match(
    /(?:youtu\.be\/|youtube\.com\/(?:embed\/|v\/|watch\?v=|watch\?.+&v=))([\w-]{11})/
  );
  return match ? match[1] : null;
}

/**
 * Normalizes video URLs to strip tracking parameters (e.g., si=...)
 * while preserving valid YouTube IDs and timestamp references.
 */
export function canonicalizeVideoUrl(rawUrl) {
  if (!rawUrl) return '';
  const urlStr = rawUrl.trim();

  try {
    const parsed = new URL(urlStr);

    // YouTube Shortened (youtu.be/xyz)
    if (parsed.hostname === 'youtu.be' || parsed.hostname.endsWith('.youtu.be')) {
      const id = parsed.pathname.replace(/^\//, '');
      return id ? `https://www.youtube.com/watch?v=${id}` : urlStr;
    }

    // YouTube Standard (youtube.com/watch?v=xyz)
    if (parsed.hostname.includes('youtube.com')) {
      const v = parsed.searchParams.get('v');
      if (v) return `https://www.youtube.com/watch?v=${v}`;
    }

    // Bilibili
    if (parsed.hostname.includes('bilibili.com')) {
      return `${parsed.origin}${parsed.pathname}`;
    }

    return urlStr;
  } catch {
    return urlStr;
  }
}

/**
 * Parses timer strings:
 * - "14:20"     -> 860s (mm:ss)
 * - "1:15:30"   -> 4530s (hh:mm:ss)
 * - "15m"       -> 900s
 * - "45s"       -> 45s
 * - "1.5h"      -> 5400s
 * - "20"        -> 1200s (defaults bare numbers to minutes)
 */
export function parseTimerToSeconds(input) {
  if (input === null || input === undefined || input === '') return 0;
  if (typeof input === 'number') return Math.max(0, Math.round(input));

  const str = String(input).trim().toLowerCase();
  if (!str) return 0;

  // 1. Check for compound durations: "1h30m", "14m20s"
  const compoundRegex = /^(?:(\d+(?:\.\d+)?)h)?\s*(?:(\d+(?:\.\d+)?)m)?\s*(?:(\d+(?:\.\d+)?)s)?$/;
  const compoundMatch = str.match(compoundRegex);
  if (compoundMatch && (compoundMatch[1] || compoundMatch[2] || compoundMatch[3])) {
    const hrs = parseFloat(compoundMatch[1] || '0') * 3600;
    const mins = parseFloat(compoundMatch[2] || '0') * 60;
    const secs = parseFloat(compoundMatch[3] || '0');
    return Math.round(hrs + mins + secs);
  }

  // 2. Colon-separated timestamps: mm:ss or hh:mm:ss
  if (str.includes(':')) {
    const parts = str.split(':').map((p) => parseFloat(p.trim()));
    if (parts.some(isNaN)) return 0;

    if (parts.length === 2) {
      // mm:ss
      return Math.round(parts[0] * 60 + parts[1]);
    } else if (parts.length === 3) {
      // hh:mm:ss
      return Math.round(parts[0] * 3600 + parts[1] * 60 + parts[2]);
    }
  }

  // 3. Pure number entered without unit: defaults to minutes (e.g. "15" -> 15 mins)
  if (/^\d+(\.\d+)?$/.test(str)) {
    return Math.round(parseFloat(str) * 60);
  }

  return 0;
}

/**
 * Formats total seconds into standard mm:ss or hh:mm:ss
 */
export function formatSecondsToTimer(totalSeconds) {
  const s = Math.max(0, Math.round(totalSeconds || 0));
  const hrs = Math.floor(s / 3600);
  const mins = Math.floor((s % 3600) / 60);
  const secs = s % 60;

  const pad = (n) => (n < 10 ? `0${n}` : `${n}`);

  if (hrs > 0) {
    return `${hrs}:${pad(mins)}:${pad(secs)}`;
  }
  return `${mins}:${pad(secs)}`;
}

/**
 * Tries to extract timestamp parameters embedded in the URL (e.g., ?t=860 or ?t=14m20s)
 */
export function extractUrlTimestamp(rawUrl) {
  if (!rawUrl) return 0;
  try {
    const parsed = new URL(rawUrl.trim());
    const tParam = parsed.searchParams.get('t') || parsed.searchParams.get('start');
    if (!tParam) return 0;

    // "860s" -> "860"
    const cleaned = tParam.replace(/s$/, '');
    return parseTimerToSeconds(cleaned);
  } catch {
    return 0;
  }
}