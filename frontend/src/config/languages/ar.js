// frontend/src/config/languages/ar.js

// Arabic Diacritics (Harakat / Tashkeel) Unicode mapping
// 1: Fatha (a), 2: Damma (u), 3: Kasra (i), 4: Sukun/Shaddah/Tanwin, 5: Plain letter
const HARAKAT_MAP = {
  fatha: ['\u064E', '\u064B'],          // Fatha, Tanwin Fath
  damma: ['\u064F', '\u064C'],          // Damma, Tanwin Damm
  kasra: ['\u0650', '\u064D'],          // Kasra, Tanwin Kasr
  neutral: ['\u0652', '\u0651']         // Sukun, Shaddah
};

function detectHaraka(charWithDiacritic = '') {
  for (const mark of HARAKAT_MAP.fatha) {
    if (charWithDiacritic.includes(mark)) return 1;
  }
  for (const mark of HARAKAT_MAP.damma) {
    if (charWithDiacritic.includes(mark)) return 2;
  }
  for (const mark of HARAKAT_MAP.kasra) {
    if (charWithDiacritic.includes(mark)) return 3;
  }
  for (const mark of HARAKAT_MAP.neutral) {
    if (charWithDiacritic.includes(mark)) return 4;
  }
  return 5;
}

export default {
  code: 'ar',
  name: 'Arabic',
  dir: 'rtl', // Useful for RTL layout support in cards/text

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

  momentum: {
    listening: {
      floor: 20,
      baseline: 45,
      ceiling: 90,
      halfLifeDays: 2.5,
      maxSlewRate: 15
    },
    speaking: {
      floor: 5,
      baseline: 10,
      ceiling: 25,
      halfLifeDays: 2.5,
      maxSlewRate: 5
    },
    vocab: {
      floor: 2,
      baseline: 5,
      ceiling: 10, // Strict invariant: max 10
      halfLifeDays: 2.5,
      maxSlewRate: 2
    },
    srs: {
      vision: {
        floor: 10,
        baseline: 20,
        ceiling: 35
      },
      listen: {
        floor: 5,
        baseline: 10,
        ceiling: 20
      },
      write: {
        floor: 1,
        baseline: 3,
        ceiling: 5
      }
    },
    revisions: {
      floor: 1,
      baseline: 1,
      ceiling: 2
    }
  },

  colors: {
    theme: { dark_primary: '#38bdf8', light_primary: '#0284c7', primary: '#0ea5e9' },
    streak: { dark_primary: '#fb7185', light_primary: '#e11d48', primary: '#f43f5e' },
    vocab: { dark_primary: '#34d399', light_primary: '#059669', primary: '#10b981' },
    ci: { dark_primary: '#d8b4fe', light_primary: '#9333ea', primary: '#a855f7' },
    listening: { dark_primary: '#fb923c', light_primary: '#ea580c', primary: '#f97316' },
    speaking: { dark_primary: '#e879f9', light_primary: '#a21caf', primary: '#c026d3' },
    grammar: { dark_primary: '#2dd4bf', light_primary: '#0f766e', primary: '#14b8a6' },
    flashcard: { dark_primary: '#f472b6', light_primary: '#db2777', primary: '#ec4899' }
  },

  // Mapped to Harakat for grammatical vowel colorization
  tones: {
    1: '#38bdf8', // Fatḥah (a) - Cyan
    2: '#f59e0b', // Ḍammah (u) - Amber
    3: '#10b981', // Kasrah (i) - Emerald
    4: '#a855f7', // Sukūn / Shaddah - Purple
    5: '#94a3b8'  // Plain consonant - Slate
  },

  glyphConfig: {
    // Regex matching Arabic unicode block
    isInspectable: (char) => /[\u0600-\u06FF]/.test(char),

    // Lined calligraphy guide for Arabic script
    gridType: 'lined',

    labels: {
      primaryPhonetic: 'Transliteration',
      component1: 'Root (Jadhar)',
      component2: 'Pattern (Wazn)',
      mnemonic: 'Root Meaning'
    },

    resolveChroma: (glyphData, tones) => {
      const markNum = detectHaraka(glyphData?.phonetic || glyphData?.char || '');
      const color = tones?.[markNum] || tones?.[5] || '#94a3b8';
      const labelMap = { 1: 'Fatḥah', 2: 'Ḍammah', 3: 'Kasrah', 4: 'Sukūn', 5: 'Consonant' };
      return {
        accentColor: color,
        badgeText: labelMap[markNum] || 'Letter'
      };
    }
  },

  colorize(arabicText = '', transliteration = '') {
    const tones = this.tones;

    // Tokenize transliteration by spaces
    const rawLatinTokens = (transliteration || '').trim().split(/(\s+)/);
    const secondaryTokens = rawLatinTokens.map((chunk) => {
      if (/^\s+$/.test(chunk)) return { text: chunk, color: null };
      return { text: chunk, color: null };
    });

    // Tokenize Arabic words by space
    const words = (arabicText || '').trim().split(/(\s+)/);
    const primaryTokens = words.map((chunk) => {
      if (/^\s+$/.test(chunk)) return { text: chunk, color: null };
      const markNum = detectHaraka(chunk);
      return {
        text: chunk,
        color: markNum !== 5 ? (tones[markNum] || null) : null
      };
    });

    return { primaryTokens, secondaryTokens };
  }
};