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
    streak: { dark_primary: '#ff5252', light_primary: '#c62828' },
    vocab: { dark_primary: '#2e7d32', light_primary: '#2e7d32' },
    ci: { dark_primary: '#6a1b9a', light_primary: '#6a1b9a' },
    listening: { dark_primary: '#bf360c', light_primary: '#d84315' },
    speaking: { dark_primary: '#b388ff', light_primary: '#4527a0' },
    grammar: { dark_primary: '#01579b', light_primary: '#0277bd' },
    flashcard: { dark_primary: '#f43f5e', light_primary: '#e11d48' }
  },

  tones: {
    1: '#0284c7', // Sky Blue
    2: '#16a34a', // Leaf Green
    3: '#d9ab06', // Amber
    4: '#dc2626', // Crimson
    5: '#64748b'  // Slate
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