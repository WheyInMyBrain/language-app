import { getLanguageConfig } from '../../config/languages/index.js';
import { metadataStore } from './metadata.svelte.js';

class ActiveLanguageStore {
  get current() {
    return getLanguageConfig(metadataStore.activeLanguage);
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
}

export const activeLanguage = new ActiveLanguageStore();