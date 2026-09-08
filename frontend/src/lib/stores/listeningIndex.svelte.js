import { createSyncedDoc } from '../yjs.js';
import { canonicalizeVideoUrl } from '../mediaResolver.js';

class ListeningIndexStore {
  entries = $state([]); // [{ date, link }]
  #handle = null;
  #currentLang = null;

  connect(langCode) {
    if (this.#currentLang === langCode && this.#handle) return;
    if (this.#handle) this.#handle.destroy();

    this.#currentLang = langCode;
    const roomName = `${langCode}:listening_index`;
    this.#handle = createSyncedDoc(roomName);

    const { doc, idbProvider } = this.#handle;
    const entriesArray = doc.getArray('entries');

    const sync = () => {
      this.entries = entriesArray.toArray();
    };

    idbProvider.on('synced', sync);
    entriesArray.observe(sync);

    if (idbProvider.synced) sync();
  }

  findMatches(rawUrl, excludeDate = null) {
    if (!rawUrl) return [];
    const canonical = canonicalizeVideoUrl(rawUrl);
    return this.entries.filter(
      (e) => canonicalizeVideoUrl(e.link) === canonical && (!excludeDate || e.date !== excludeDate)
    );
  }
}

export const listeningIndexStore = new ListeningIndexStore();