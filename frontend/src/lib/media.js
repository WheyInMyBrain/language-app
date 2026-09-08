// frontend/src/lib/media.js
import { CONFIG } from './config.js';

/**
 * Extracts pure YouTube 11-character video ID from any format:
 * - https://www.youtube.com/watch?v=dQw4w9WgXcQ
 * - https://youtu.be/dQw4w9WgXcQ?si=abcdef
 * - https://www.youtube.com/shorts/dQw4w9WgXcQ
 * - https://m.youtube.com/watch?v=dQw4w9WgXcQ&feature=shared
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
 * - Converts any YouTube link into a clean canonical: `https://www.youtube.com/watch?v={ID}`
 * - Preserves optional timestamp `t=...` if present
 * - Leaves direct video/image URLs intact
 * - Returns null or empty string if input is invalid/garbage
 */
export function canonicalizeMediaUrl(rawInput) {
  if (!rawInput || typeof rawInput !== 'string') return '';

  // 1. Strip Obsidian wiki-link brackets: ![[filename.mp4]] -> filename.mp4
  let clean = rawInput.trim().replace(/^!*\[\[(.*?)\]\]$/, '$1').trim();
  if (!clean) return '';

  // 2. Canonicalize YouTube
  const ytId = extractYouTubeId(clean);
  if (ytId) {
    // Preserve timestamp if specified (?t=120 or &t=2m10s)
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
 * Only produces: 'youtube' | 'direct_video' | 'image' | 'empty'
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

  // 3. Local media files (relative paths served by Axum backend)
  const resolvedUrl = `${CONFIG.API_BASE}/media/${encodeURIComponent(clean)}`;
  const isVideo = /\.(mp4|webm|mov|m4v)(?:\?.*)?$/i.test(clean);

  return {
    type: isVideo ? 'direct_video' : 'image',
    url: resolvedUrl
  };
}