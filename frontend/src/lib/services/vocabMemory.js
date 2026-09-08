// frontend/src/lib/services/vocabMemory.js

/**
 * Splits pronunciation string into individual syllables,
 * handling regular spaces, non-breaking spaces (\u00A0), tabs, hyphens, and punctuation.
 */
export function tokenizePronunciation(pronStr) {
  if (!pronStr || typeof pronStr !== 'string') return [];
  return pronStr
    .trim()
    .replace(/[\u00A0\u1680\u2000-\u200a\u202f\u205f\u3000,\/\-_]/g, ' ')
    .split(/\s+/)
    .filter(Boolean);
}

/**
 * Extracts raw glyphs from native script, stripping CJK/ASCII punctuation & whitespace.
 */
export function tokenizeCharacters(nativeStr) {
  if (!nativeStr || typeof nativeStr !== 'string') return [];
  return Array.from(nativeStr.trim().replace(/[\s\p{P}\p{S}]/gu, ''));
}

/**
 * Builds phrase and character lookup maps in memory from existing vocab entries.
 */
export function buildVocabMemory(entries = []) {
  const phraseMap = new Map();
  const charMap = new Map();

  for (const entry of entries) {
    const rawNative = (entry.native_script || '').trim();
    const rawPron = (entry.pronunciation || '').trim();

    if (!rawNative || !rawPron) continue;

    // 1. Exact phrase mapping (e.g., "紫色" -> "zǐ sè")
    phraseMap.set(rawNative, rawPron);

    // 2. Character-to-syllable decomposition
    const chars = tokenizeCharacters(rawNative);
    const syllables = tokenizePronunciation(rawPron);

    // If counts match 1:1, decompose and save individual characters
    if (chars.length === syllables.length && chars.length > 0) {
      for (let i = 0; i < chars.length; i++) {
        charMap.set(chars[i], syllables[i]);
      }
    }
  }

  return { phraseMap, charMap };
}

/**
 * Predicts pronunciation for input text:
 * 1. Checks exact phrase match.
 * 2. Assembles known characters one by one.
 */
export function predictFromMemory(nativeText, { phraseMap, charMap }) {
  if (!nativeText || typeof nativeText !== 'string') return '';
  const text = nativeText.trim();
  if (!text) return '';

  // Priority 1: Exact whole-word match
  if (phraseMap.has(text)) {
    return phraseMap.get(text);
  }

  // Priority 2: Character-by-character reconstruction
  const chars = Array.from(text);
  const matchedTokens = [];
  let foundAny = false;

  for (const ch of chars) {
    if (charMap.has(ch)) {
      matchedTokens.push(charMap.get(ch));
      foundAny = true;
    } else {
      matchedTokens.push(ch); // Retain unknown character in place
    }
  }

  return foundAny ? matchedTokens.join(' ') : '';
}