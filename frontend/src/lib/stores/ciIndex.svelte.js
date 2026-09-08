import { createSyncedDoc } from '../yjs.js';
import { canonicalizeVideoUrl } from '../mediaResolver.js';

class CIIndexStore {
  links = $state([]);
  #handle = null;
  #currentLang = null;

  connect(langCode) {
    if (this.#currentLang === langCode && this.#handle) return;
    if (this.#handle) this.#handle.destroy();

    this.#currentLang = langCode;
    const roomName = `${langCode}:ci_index`;
    this.#handle = createSyncedDoc(roomName);

    const { doc, idbProvider } = this.#handle;
    const linksArray = doc.getArray('links');

    const sync = () => {
      this.links = linksArray.toArray();
    };

    idbProvider.on('synced', sync);
    linksArray.observe(sync);

    if (idbProvider.synced) sync();
  }

  isDuplicate(rawUrl) {
    if (!rawUrl) return false;
    const canonical = canonicalizeVideoUrl(rawUrl);
    return this.links.some((l) => canonicalizeVideoUrl(l) === canonical);
  }
}

export const ciIndexStore = new CIIndexStore();