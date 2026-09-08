// frontend/src/lib/services/ciCandidateService.js
import { canonicalizeMediaUrl } from '../media.js';

export function getUnprocessedCICandidates(listeningEntries = [], ciLinks = []) {
  // 1. Create a Set of normalized, already-processed CI links
  const processedSet = new Set();
  for (const raw of ciLinks) {
    const clean = canonicalizeMediaUrl(raw);
    if (clean) processedSet.add(clean);
  }

  // 2. Filter listening entries that haven't been processed into CI yet
  const candidates = [];
  const seenInSession = new Set();

  for (const entry of listeningEntries) {
    if (!entry?.link) continue;
    const cleanUrl = canonicalizeMediaUrl(entry.link);
    if (!cleanUrl || processedSet.has(cleanUrl)) continue;

    // Deduplicate within the candidate queue
    const uniqueKey = `${entry.date || 'Undated'}_${cleanUrl}`;
    if (seenInSession.has(uniqueKey)) continue;
    seenInSession.add(uniqueKey);

    candidates.push({
      date: entry.date || 'Undated',
      url: cleanUrl
    });
  }

  // 3. Group by date
  const groupedByDate = {};
  for (const item of candidates) {
    if (!groupedByDate[item.date]) {
      groupedByDate[item.date] = [];
    }
    groupedByDate[item.date].push(item);
  }

  // 4. Sort dates descending (latest first)
  const sortedDates = Object.keys(groupedByDate).sort((a, b) => b.localeCompare(a));

  return {
    candidates,
    groupedByDate,
    sortedDates
  };
}