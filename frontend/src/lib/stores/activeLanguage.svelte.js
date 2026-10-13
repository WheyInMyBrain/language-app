// frontend/src/lib/stores/activeLanguage.svelte.js
import { getLanguageConfig } from '../../config/languages/index.js';
import { metadataStore } from './metadata.svelte.js';
import { getDefaultConfig } from '../utils/languageCode.js';

class ActiveLanguageStore {
  /**
   * Raw static configuration from config/languages/*.js
   */
  get staticBase() {
    const langCode = metadataStore.activeLanguage || 'zh-CN';
    try {
      const cfg = getLanguageConfig(langCode);
      if (cfg && Object.keys(cfg).length > 0) return cfg;
    } catch (_) {}
    return getDefaultConfig(langCode, langCode);
  }

  /**
   * Composed reactive view: Dynamic overrides from metadataStore override static base
   */
  get current() {
    const langCode = metadataStore.activeLanguage || 'zh-CN';
    const base = this.staticBase;
    const dynamicData = metadataStore.languages?.[langCode] || {};

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
      momentum: {
        ...(base.momentum || {}),
        ...(dynamicData.momentum || {})
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
    return this.current.code || metadataStore.activeLanguage || 'zh-CN';
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

  get themeColor() {
    return (
      this.current.colors?.theme?.dark_primary ||
      this.current.colors?.theme?.light_primary ||
      '#a855f7'
    );
  }

  get tones() {
    return this.current.tones;
  }

  /**
   * Updates settings through activeLanguage and writes them to metadataStore
   * so they are staged into the outbox and synced to the backend SQLite DB.
   */
  async updateConfig(partialConfig) {
    const langCode = this.code;
    await metadataStore.updateLanguageConfig(langCode, partialConfig);
  }

  /**
   * Ensures the active language defaults exist in metadataStore and SQLite.
   * If metadataStore doesn't have colors/tones yet, this pushes the static
   * defaults to the backend.
   */
  async ensureSynced() {
    const langCode = this.code;
    const dynamicData = metadataStore.languages?.[langCode];

    // If metadataStore has no record or is missing colors/tones, seed the static base into it
    if (!dynamicData || !dynamicData.colors || Object.keys(dynamicData.colors).length === 0) {
      const base = this.staticBase;
      await metadataStore.updateLanguageConfig(langCode, {
        name: base.name || langCode,
        goals: base.goals || {},
        milestones: base.milestones || {},
        momentum: base.momentum || {},
        colors: base.colors || {},
        tones: base.tones || {}
      });
    }
  }

  colorize(...args) {
    if (typeof this.current.colorize === 'function') {
      return this.current.colorize(...args);
    }
    return { primaryTokens: [], secondaryTokens: [] };
  }
}

export const activeLanguage = new ActiveLanguageStore();