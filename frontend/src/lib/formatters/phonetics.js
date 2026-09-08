/**
 * Normalizes strings by removing tone marks and diacritics for neutral search.
 * e.g. "xuéxí" -> "xuexi", "lǜ" -> "lv"
 */
export function stripDiacritics(str) {
  if (!str || typeof str !== 'string') return '';
  return str
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/ü/gi, 'v')
    .toLowerCase()
    .trim();
}

/**
 * Universal colorizer entry point.
 * Returns an array of tokens: Array<{ text: string, color: string | null }>
 */
export function tokenizePhonetics(primary, secondary, langConfig) {
  if (!langConfig || !langConfig.colorize) {
    return {
      primaryTokens: [{ text: primary || '', color: null }],
      secondaryTokens: [{ text: secondary || '', color: null }]
    };
  }

  return langConfig.colorize(primary, secondary);
}