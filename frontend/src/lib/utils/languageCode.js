// frontend/src/lib/utils/languageCode.js

// Primary lookup dictionary covering major target languages
const COMMON_MAP = {
  chinese: 'zh-CN',
  mandarin: 'zh-CN',
  japanese: 'ja',
  korean: 'ko',
  spanish: 'es',
  french: 'fr',
  german: 'de',
  italian: 'it',
  russian: 'ru',
  portuguese: 'pt-BR',
  arabic: 'ar',
  hindi: 'hi',
  vietnamese: 'vi',
  thai: 'th',
  dutch: 'nl',
  swedish: 'sv',
  turkish: 'tr',
  indonesian: 'id',
  polish: 'pl'
};

/**
 * Resolves a language name or code into a normalized BCP 47 code.
 * Example: "Japanese" -> "ja", "Chinese" -> "zh-CN", "ES" -> "es"
 */
export function guessLanguageCode(inputName) {
  if (!inputName) return '';
  const clean = inputName.trim().toLowerCase();

  // 1. Direct match in lookup table
  if (COMMON_MAP[clean]) return COMMON_MAP[clean];

  // 2. If user typed a valid code already (e.g. "ja", "de-DE", "ko")
  try {
    const canonical = Intl.getCanonicalLocales(clean)[0];
    if (canonical) return canonical;
  } catch (_) {}

  // 3. Reverse search through Intl display names
  try {
    const enDisplay = new Intl.DisplayNames(['en'], { type: 'language' });
    for (const [code] of Object.entries(COMMON_MAP)) {
      const standardName = enDisplay.of(code)?.toLowerCase();
      if (standardName && standardName === clean) {
        return code;
      }
    }
  } catch (_) {}

  // Fallback slug
  return clean.slice(0, 3);
}

export function getDefaultConfig(code, name) {
  return {
    code,
    name,
    current_streak: 0,
    longest_streak: 0,
    total_days: 0,
    goals: {
      vocab: 10,
      grammar: 1,
      ci: 1,
      listening_minutes: 45,
      speaking_minutes: 10
    },
    milestones: {
      vocab_total: 1000,
      listening_hours: 48,
      speaking_hours: 12
    },
    colors: {
      streak: { dark_primary: '#ff5252', light_primary: '#c62828' },
      vocab: { dark_primary: '#2e7d32', light_primary: '#2e7d32' },
      ci: { dark_primary: '#6a1b9a', light_primary: '#6a1b9a' },
      listening: { dark_primary: '#bf360c', light_primary: '#d84315' },
      speaking: { dark_primary: '#b388ff', light_primary: '#4527a0' },
      grammar: { dark_primary: '#01579b', light_primary: '#0277bd' },
      flashcard: { dark_primary: '#f43f5e', light_primary: '#e11d48' }
    },
    tones: {
      1: '#0284c7',
      2: '#16a34a',
      3: '#d9ab06',
      4: '#dc2626',
      5: '#64748b'
    }
  };
}