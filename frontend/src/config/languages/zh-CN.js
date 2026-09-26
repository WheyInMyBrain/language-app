// frontend/src/config/languages/zh-CN.js

const TONE_MARKS = {
  1: ['ā', 'ē', 'ī', 'ō', 'ū', 'ǖ', 'Ā', 'Ē', 'Ī', 'Ō', 'Ū', 'Ǖ'],
  2: ['á', 'é', 'í', 'ó', 'ú', 'ǘ', 'Á', 'É', 'Í', 'Ó', 'Ú', 'Ǘ'],
  3: ['ǎ', 'ě', 'ǐ', 'ǒ', 'ǔ', 'ǚ', 'Ǎ', 'Ě', 'Ǐ', 'Ǒ', 'Ǚ', 'Ǚ'],
  4: ['à', 'è', 'ì', 'ò', 'ù', 'ǜ', 'À', 'È', 'Ì', 'Ò', 'Ù', 'Ǜ']
};

function detectTone(syllable = '') {
  for (let tone = 1; tone <= 4; tone++) {
    for (const char of TONE_MARKS[tone]) {
      if (syllable.includes(char)) return tone;
    }
  }
  return 5;
}

export default {
  code: 'zh-CN',
  name: 'Chinese',

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
      floor: 20,       // Minimum target during recovery / travel slumps (mins)
      baseline: 45,    // Standard nominal target (mins)
      ceiling: 90,     // Maximum cap during flow state (mins)
      halfLifeDays: 2.5,
      maxSlewRate: 15
    },
    speaking: {
      floor: 5,        // Recovery floor (mins)
      baseline: 10,    // Standard nominal target (mins)
      ceiling: 25,     // Maximum cap (mins)
      halfLifeDays: 2.5,
      maxSlewRate: 5
    },
    vocab: {
      floor: 2,        // Minimum baseline when exhausted (words)
      baseline: 5,     // Standard nominal target (words)
      ceiling: 10,     // 🌟 HARD CEILING (never more than 10 words)
      halfLifeDays: 2.5,
      maxSlewRate: 2
    },

    // 🌟 TRI-DECK SRS PACING BOUNDARIES (Cards/Day) 🌟
    srs: {
      vision: {
        floor: 10,     // Slump / recovery floor
        baseline: 20,  // Standard nominal daily quota
        ceiling: 35    // Flow surge maximum
      },
      listen: {
        floor: 5,      // Slump / recovery floor
        baseline: 10,  // Standard nominal daily quota
        ceiling: 20    // Flow surge maximum
      },
      write: {
        floor: 1,      // Minimal motor requirement
        baseline: 3,   // Standard calligraphy practice
        ceiling: 5     // Strict bound to prevent wrist fatigue
      }
    },

    // 🌟 DAY-PAGE REVISION DISPATCH PACING (Days/Day) 🌟
    revisions: {
      floor: 1,        // Always prioritize exactly 1 anchor day (Pass 0/1 first)
      baseline: 1,     // Standard comfortable deep revision
      ceiling: 2       // High-flow limit (max 2 past days in one sitting)
    }
  },

  colors: {
    theme: { dark_primary: '#c084fc', light_primary: '#7e22ce', primary: '#a855f7' },
    streak: { dark_primary: '#fb7185', light_primary: '#e11d48', primary: '#f43f5e' },
    vocab: { dark_primary: '#34d399', light_primary: '#059669', primary: '#10b981' },
    ci: { dark_primary: '#d8b4fe', light_primary: '#9333ea', primary: '#a855f7' },
    listening: { dark_primary: '#fb923c', light_primary: '#ea580c', primary: '#f97316' },
    speaking: { dark_primary: '#e879f9', light_primary: '#a21caf', primary: '#c026d3' },
    grammar: { dark_primary: '#38bdf8', light_primary: '#0284c7', primary: '#0ea5e9' },
    flashcard: { dark_primary: '#f472b6', light_primary: '#db2777', primary: '#ec4899' }
  },

  tones: {
    1: '#38bdf8',
    2: '#34d399',
    3: '#fbbf24',
    4: '#f87171',
    5: '#94a3b8'
  },

  // 🌟 GENERIC GLYPH INSPECTION CONTRACT 🌟
  glyphConfig: {
    // Determines if a clicked character is inspectable
    isInspectable: (char) => /[\u4e00-\u9fa5]/.test(char),

    // Grid type for the vector canvas: 'rice' (米字格) | 'square' | 'lined'
    gridType: 'rice',

    // Labels customized for Chinese typography
    labels: {
      primaryPhonetic: 'Pinyin',
      component1: 'Radical',
      component2: 'Decomposition',
      mnemonic: 'Mnemonic Hint'
    },

    // Extracts the chromatic accent and badge label for a glyph
    resolveChroma: (glyphData, tones) => {
      const toneNum = detectTone(glyphData?.phonetic || glyphData?.pinyin || '');
      const color = tones?.[toneNum] || tones?.[5] || '#94a3b8';
      return {
        accentColor: color,
        badgeText: `Tone ${toneNum}`
      };
    }
  },

  colorize(hanzi = '', pinyin = '') {
    const tones = this.tones;
    const rawSyllables = (pinyin || '').trim().split(/(\s+)/);
    const secondaryTokens = rawSyllables.map((chunk) => {
      if (/^\s+$/.test(chunk)) return { text: chunk, color: null };
      const toneNum = detectTone(chunk);
      return { text: chunk, color: tones[toneNum] || tones[5] };
    });

    const cleanSyllables = rawSyllables.filter((s) => !/^\s+$/.test(s));
    const characters = Array.from(hanzi || '');

    const primaryTokens = characters.map((char, i) => {
      if (/^\s+$/.test(char)) return { text: char, color: null };
      if (cleanSyllables.length === characters.filter((c) => !/^\s+$/.test(c)).length) {
        const toneNum = detectTone(cleanSyllables[i] || '');
        return { text: char, color: tones[toneNum] || tones[5] };
      }
      return { text: char, color: null };
    });

    return { primaryTokens, secondaryTokens };
  }
};