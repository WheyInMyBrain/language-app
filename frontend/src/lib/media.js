// frontend/src/lib/media.js

/**
 * Extracts pure YouTube 11-character video ID from any format
 */
export function extractYouTubeId(url) {
  if (!url || typeof url !== 'string') return null;
  const match = url.trim().match(
    /(?:youtu\.be\/|youtube\.com\/(?:embed\/|v\/|watch\?v=|watch\?.+&v=|shorts\/))([\w-]{11})/i
  );
  return match ? match[1] : null;
}

/**
 * Strips tracking parameters, playlists, and referral junk.
 */
export function canonicalizeMediaUrl(rawInput) {
  if (!rawInput || typeof rawInput !== 'string') return '';

  // 1. Strip Obsidian wiki-link brackets: ![[filename.mp4]] -> filename.mp4
  let clean = rawInput.trim().replace(/^!*\[\[(.*?)\]\]$/, '$1').trim();
  if (!clean) return '';

  // 2. Canonicalize YouTube
  const ytId = extractYouTubeId(clean);
  if (ytId) {
    const timeMatch = clean.match(/[?&]t=([0-9hms]+)/i);
    if (timeMatch) {
      return `https://www.youtube.com/watch?v=${ytId}&t=${timeMatch[1]}`;
    }
    return `https://www.youtube.com/watch?v=${ytId}`;
  }

  // 3. Keep direct URLs (http/https/data)
  if (clean.startsWith('http://') || clean.startsWith('https://') || clean.startsWith('data:')) {
    return clean;
  }

  // 4. Return local filename (for local static assets)
  return clean;
}

/**
 * Resolves cleaned URL into a renderable component payload
 */
export function getMediaInfo(rawUrl) {
  if (!rawUrl || typeof rawUrl !== 'string') {
    return { type: 'empty', url: '' };
  }

  const clean = canonicalizeMediaUrl(rawUrl);
  if (!clean) {
    return { type: 'empty', url: '' };
  }

  // 1. Check YouTube
  const ytId = extractYouTubeId(clean);
  if (ytId) {
    return {
      type: 'youtube',
      id: ytId,
      url: clean
    };
  }

  // 2. Direct Web URLs & Data URIs
  if (clean.startsWith('http://') || clean.startsWith('https://') || clean.startsWith('data:')) {
    const isVideo = /\.(mp4|webm|mov|m4v)(?:\?.*)?$/i.test(clean);
    return {
      type: isVideo ? 'direct_video' : 'image',
      url: clean
    };
  }

  // 3. Local media files (served via Vite /media proxy)
  const resolvedUrl = `/media/${encodeURIComponent(clean)}`;
  const isVideo = /\.(mp4|webm|mov|m4v)(?:\?.*)?$/i.test(clean);

  return {
    type: isVideo ? 'direct_video' : 'image',
    url: resolvedUrl
  };
}