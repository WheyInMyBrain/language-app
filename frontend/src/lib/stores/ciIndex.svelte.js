import { initLocalDatabase } from '../db.js';
import { canonicalizeVideoUrl } from '../mediaResolver.js';

class CIIndexStore {
  links = $state([]);
  #currentLang = null;

  async connect(langCode) {
    if (!langCode) return;
    if (this.#currentLang === langCode && this.links.length > 0) return;

    this.#currentLang = langCode;
    await this.refresh();
  }

  async refresh() {
    if (!this.#currentLang) return;
    const db = await initLocalDatabase();

    const tx = db.transaction('activities', 'readonly');
    const allActs = await tx.store.getAll();
    await tx.done;

    this.links = allActs
      .filter((a) => a.lang_code === this.#currentLang && a.activity_type === 'ci' && !a.deleted_at && a.link)
      .map((a) => a.link);
  }

  isDuplicate(rawUrl) {
    if (!rawUrl) return false;
    const canonical = canonicalizeVideoUrl(rawUrl);
    return this.links.some((l) => canonicalizeVideoUrl(l) === canonical);
  }
}

export const ciIndexStore = new CIIndexStore();