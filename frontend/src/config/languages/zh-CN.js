// Tone diacritic mapping
const TONE_MARKS = {
  1: ['ā', 'ē', 'ī', 'ō', 'ū', 'ǖ', 'Ā', 'Ē', 'Ī', 'Ō', 'Ū', 'Ǖ'],
  2: ['á', 'é', 'í', 'ó', 'ú', 'ǘ', 'Á', 'É', 'Í', 'Ó', 'Ú', 'Ǘ'],
  3: ['ǎ', 'ě', 'ǐ', 'ǒ', 'ǔ', 'ǚ', 'Ǎ', 'Ě', 'Ǐ', 'Ǒ', 'Ǔ', 'Ǚ'],
  4: ['à', 'è', 'ì', 'ò', 'ù', 'ǜ', 'À', 'È', 'Ì', 'Ò', 'Ù', 'Ǜ']
};

function detectTone(syllable) {
  for (let tone = 1; tone <= 4; tone++) {
    for (const char of TONE_MARKS[tone]) {
      if (syllable.includes(char)) return tone;
    }
  }
  return 5; // Neutral tone
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

  colors: {
    // Theme (Neon Violet / Royal Purple)
    theme: { 
      dark_primary: '#c084fc',  // Luminous violet for dark glass
      light_primary: '#7e22ce', // Deep contrast purple for light glass
      primary: '#a855f7' 
    },

    // Streak (Vibrant Ember / Crimson Coral)
    streak: { 
      dark_primary: '#fb7185', 
      light_primary: '#e11d48', 
      primary: '#f43f5e' 
    },

    // Vocab (Emerald / Mint Glass)
    vocab: { 
      dark_primary: '#34d399',  // Crisp mint glow on dark mode
      light_primary: '#059669', // Emerald readability on light mode
      primary: '#10b981' 
    },

    // CI Video (Amethyst / Deep Electric Purple)
    ci: { 
      dark_primary: '#d8b4fe', 
      light_primary: '#9333ea', 
      primary: '#a855f7' 
    },

    // Listening (Sunset Amber / Deep Tangerine)
    listening: { 
      dark_primary: '#fb923c',  // Vibrant peach-orange on dark glass
      light_primary: '#ea580c', // High-contrast orange on light glass
      primary: '#f97316' 
    },

    // Speaking (Luminous Lilac / Deep Indigo)
    speaking: { 
      dark_primary: '#e879f9', 
      light_primary: '#a21caf', 
      primary: '#c026d3' 
    },

    // Grammar (Cyan / Oceanic Azure)
    grammar: { 
      dark_primary: '#38bdf8',  // Glowing sky-cyan on dark glass
      light_primary: '#0284c7', // Deep sapphire-cyan on light glass
      primary: '#0ea5e9' 
    },

    // Flashcard / Review (Ruby Rose)
    flashcard: { 
      dark_primary: '#f472b6', 
      light_primary: '#db2777', 
      primary: '#ec4899' 
    }
  },

  // 🌟 BALANCED TONE CHROMATICS 🌟
  // Calibrated for WCAG AA contrast against both dark (#12131a) & frosted light (#ffffff/60) backgrounds
  tones: {
    1: '#38bdf8', // Tone 1 (High Level): Vivid Sky Cyan — crystal clear on dark & light
    2: '#34d399', // Tone 2 (Rising): Jade Mint — balanced brightness without glare
    3: '#fbbf24', // Tone 3 (Dipping): Warm Sunflower Amber — avoids muddy brown tones
    4: '#f87171', // Tone 4 (Falling): Coral Crimson — crisp without visual fatigue
    5: '#94a3b8'  // Tone 5 (Neutral): Balanced Slate Mist — readable subdued neutral
  },

  /**
   * Tokenizes Chinese Hanzi and Pinyin into colored tokens
   */
  colorize(hanzi = '', pinyin = '') {
    const tones = this.tones;

    // Split pinyin while keeping spaces and punctuation intact
    const rawSyllables = (pinyin || '').trim().split(/(\s+)/);
    const secondaryTokens = rawSyllables.map((chunk) => {
      if (/^\s+$/.test(chunk)) {
        return { text: chunk, color: null };
      }
      const toneNum = detectTone(chunk);
      return {
        text: chunk,
        color: tones[toneNum] || tones[5]
      };
    });

    // Pair Hanzi characters with corresponding non-whitespace syllables
    const cleanSyllables = rawSyllables.filter((s) => !/^\s+$/.test(s));
    const characters = Array.from(hanzi || '');

    const primaryTokens = characters.map((char, i) => {
      if (/^\s+$/.test(char)) {
        return { text: char, color: null };
      }
      if (cleanSyllables.length === characters.filter((c) => !/^\s+$/.test(c)).length) {
        const toneNum = detectTone(cleanSyllables[i] || '');
        return { text: char, color: tones[toneNum] || tones[5] };
      }
      return { text: char, color: null };
    });

    return { primaryTokens, secondaryTokens };
  }
};