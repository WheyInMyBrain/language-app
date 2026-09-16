import { getLanguageConfig } from '../../config/languages/index.js';
import { metadataStore } from './metadata.svelte.js';
import { getDefaultConfig } from '../utils/languageCode.js';

class ActiveLanguageStore {
  get current() {
    const langCode = metadataStore.activeLanguage || 'zh-CN';

    // 1. Static base config (preserves methods like .colorize()) or default fallback
    let base = {};
    try {
      base = getLanguageConfig(langCode) || {};
    } catch (_) {
      base = getDefaultConfig(langCode, langCode);
    }

    // 2. Dynamic state saved in SQLite / IndexedDB via Yjs
    const dynamicData = metadataStore.languages?.[langCode] || {};

    // 3. Merge: Dynamic overrides static
    return {
      ...base,
      ...dynamicData,
      goals: {
        ...(base.goals || {}),
        ...(dynamicData.goals || {})
      },
      milestones: {
        ...(base.milestones || {}),
        ...(dynamicData.milestones || {})
      },
      colors: {
        ...(base.colors || {}),
        ...(dynamicData.colors || {})
      },
      tones: {
        ...(base.tones || {}),
        ...(dynamicData.tones || {})
      }
    };
  }

  get code() {
    return this.current.code;
  }

  get name() {
    return this.current.name;
  }

  get goals() {
    return this.current.goals;
  }

  get milestones() {
    return this.current.milestones;
  }

  get colors() {
    return this.current.colors;
  }

  get tones() {
    return this.current.tones;
  }

  // Forward helper methods like .colorize() if defined on base config
  colorize(...args) {
    if (typeof this.current.colorize === 'function') {
      return this.current.colorize(...args);
    }
    return { primaryTokens: [], secondaryTokens: [] };
  }
}

export const activeLanguage = new ActiveLanguageStore();