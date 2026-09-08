// frontend/src/lib/stores/vocabIndex.svelte.js
import { createSyncedDoc } from '../yjs.js';
import { stripDiacritics } from '../formatters/phonetics.js';
import { buildVocabMemory, predictFromMemory } from '../services/vocabMemory.js';

class VocabIndexStore {
  entries = $state([]);
  isLoaded = $state(false);
  activeRoom = $state(null);
  #docHandle = null;

  // Reactively updates whenever entries changes
  #memoryMaps = $derived(buildVocabMemory(this.entries));

  connect(langCode) {
    const roomName = `${langCode}:vocab_index`;
    if (this.activeRoom === roomName) return;

    if (this.#docHandle) {
      this.#docHandle.destroy();
      this.entries = [];
      this.isLoaded = false;
    }

    this.activeRoom = roomName;
    this.#docHandle = createSyncedDoc(roomName);

    const { doc, idbProvider } = this.#docHandle;
    const entriesArray = doc.getArray('entries');

    const sync = () => {
      const raw = entriesArray.toArray().flat();
      this.entries = raw.map((item) => ({
        ...item,
        _normPrimary: (item.native_script || '').toLowerCase(),
        _normSecondary: stripDiacritics(item.pronunciation || '')
      }));
    };

    idbProvider.on('synced', () => {
      this.isLoaded = true;
      sync();
    });

    entriesArray.observe(sync);
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