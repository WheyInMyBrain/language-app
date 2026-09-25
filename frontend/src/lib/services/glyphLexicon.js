// frontend/src/lib/services/glyphLexicon.js
const memoryCache = new Map();

/**
 * Converts an array of stroke points [[x1, y1], [x2, y2], ...] into an SVG path string "M x1 y1 L x2 y2 ..."
 */
export function pointsToSvgPath(points) {
  if (!Array.isArray(points) || points.length === 0) return '';
  return points.reduce((acc, pt, i) => {
    return i === 0 ? `M ${pt[0]} ${pt[1]}` : `${acc} L ${pt[0]} ${pt[1]}`;
  }, '');
}

/**
 * Universal glyph fetcher supporting any language code
 * Works offline once fetched (via memory cache & localStorage fallback)
 */
export async function fetchGlyphDetails(lang = 'zh-CN', char) {
  if (!char || typeof char !== 'string') return null;

  // Unicode-safe single-glyph extraction (handles surrogate pairs properly)
  const trimmed = char.trim();
  const glyphs = Array.from(trimmed);
  const cleanChar = glyphs[0];
  if (!cleanChar) return null;

  const cacheKey = `glyph:${lang}:${cleanChar}`;

  // 1. In-memory check (0ms)
  if (memoryCache.has(cacheKey)) {
    return memoryCache.get(cacheKey);
  }

  // 2. Persistent storage check (works offline)
  try {
    const local = localStorage.getItem(cacheKey);
    if (local) {
      const parsed = JSON.parse(local);
      memoryCache.set(cacheKey, parsed);
      return parsed;
    }
  } catch {}

  // 3. Network fetch to Axum backend
  try {
    const res = await fetch(`/api/glyph/${encodeURIComponent(lang)}/${encodeURIComponent(cleanChar)}`);
    if (!res.ok) return null;
    const data = await res.json();

    // Cache in RAM
    memoryCache.set(cacheKey, data);

    // Persist to local storage for offline use
    try {
      localStorage.setItem(cacheKey, JSON.stringify(data));
    } catch {
      // Storage quota safety: clear old items if needed
    }

    return data;
  } catch (err) {
    console.warn(`[GlyphLexicon] Failed to fetch character for ${lang}:`, cleanChar, err);
    return null;
  }
}