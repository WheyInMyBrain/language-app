import { initLocalDatabase } from '../db.js';
import { canonicalizeVideoUrl } from '../mediaResolver.js';

class ListeningIndexStore {
  entries = $state([]); // [{ date, link }]
  #currentLang = null;

  async connect(langCode) {
    if (!langCode) return;
    if (this.#currentLang === langCode && this.entries.length > 0) return;

    this.#currentLang = langCode;
    await this.refresh();
  }

  async refresh() {
    if (!this.#currentLang) return;
    const db = await initLocalDatabase();

    const tx = db.transaction('activities', 'readonly');
    const allActs = await tx.store.getAll();
    await tx.done;

    this.entries = allActs
      .filter((a) => a.lang_code === this.#currentLang && a.activity_type === 'listening' && !a.deleted_at && a.link)
      .map((a) => ({
        date: a.log_date,
        link: a.link
      }));
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