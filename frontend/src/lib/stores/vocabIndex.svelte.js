import { initLocalDatabase } from '../db.js';
import { stripDiacritics } from '../formatters/phonetics.js';
import { buildVocabMemory, predictFromMemory } from '../services/vocabMemory.js';

class VocabIndexStore {
  entries = $state([]);
  isLoaded = $state(false);
  #currentLang = null;

  // Reactively updates whenever entries changes
  #memoryMaps = $derived(buildVocabMemory(this.entries));

  async connect(langCode) {
    if (!langCode) return;
    if (this.#currentLang === langCode && this.isLoaded) return;

    this.#currentLang = langCode;
    this.isLoaded = false;
    await this.refresh();
  }

  async refresh() {
    if (!this.#currentLang) return;
    const db = await initLocalDatabase();

    const tx = db.transaction('words', 'readonly');
    const allWords = await tx.store.getAll();
    await tx.done;

    this.entries = allWords
      .filter((w) => w.lang_code === this.#currentLang && !w.deleted_at)
      .map((item) => ({
        ...item,
        _normPrimary: (item.native_script || '').toLowerCase(),
        _normSecondary: stripDiacritics(item.pronunciation || '')
      }));

    this.isLoaded = true;
  }

  predictPronunciation = (text) => {
    return predictFromMemory(text, this.#memoryMaps);
  };

  search(rawQuery) {
    const query = (rawQuery || '').trim();
    if (!query) return this.entries;

    const cleanQuery = stripDiacritics(query);
    const lowerQuery = query.toLowerCase();

    return this.entries.filter((entry) => {
      if (entry._normPrimary.includes(lowerQuery)) return true;
      if (entry._normSecondary.startsWith(cleanQuery)) return true;

      const syllables = entry._normSecondary.split(/[\s'-]+/);
      return syllables.some((s) => s.startsWith(cleanQuery));
    });
  }
}

export const vocabIndexStore = new VocabIndexStore();