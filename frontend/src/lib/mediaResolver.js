/**
 * Normalizes video URLs to strip tracking query parameters
 * (e.g. youtu.be/xyz?si=... -> youtube.com/watch?v=xyz)
 */
export function canonicalizeVideoUrl(rawUrl) {
  if (!rawUrl) return '';
  const urlStr = rawUrl.trim();

  try {
    const parsed = new URL(urlStr);

    // YouTube Shortened
    if (parsed.hostname === 'youtu.be') {
      const id = parsed.pathname.replace('/', '');
      return `https://www.youtube.com/watch?v=${id}`;
    }

    // YouTube Standard
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
 * Parses timer strings like "10:45", "1:15:30", "45", or "12m" into total seconds.
 */
export function parseTimerToSeconds(input) {
  if (!input) return 0;
  if (typeof input === 'number') return Math.max(0, Math.round(input));

  const str = String(input).trim().toLowerCase();

  // If already pure seconds
  if (/^\d+$/.test(str)) {
    return parseInt(str, 10);
  }

  // Matches mm:ss or hh:mm:ss
  const parts = str.split(':').map((p) => parseInt(p, 10));
  if (parts.some(isNaN)) return 0;

  if (parts.length === 2) {
    // mm:ss
    return parts[0] * 60 + parts[1];
  } else if (parts.length === 3) {
    // hh:mm:ss
    return parts[0] * 3600 + parts[1] * 60 + parts[2];
  }

  return 0;
}

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