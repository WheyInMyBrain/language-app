// frontend/src/lib/services/dailyLogService.js
import { getDocHandle } from '../yjs.js';
import { metadataStore } from '../stores/metadata.svelte.js';
import { canonicalizeMediaUrl } from '../media.js';

/**
 * Adds a new word to the active day and cross-indexes into vocab_index & srs queue.
 */
export async function addWordToDay({ langCode, dateStr, dayDocHandle, wordData }) {
  if (!dayDocHandle?.doc) throw new Error('Day document handle unavailable.');

  const { doc: dayDoc } = dayDocHandle;
  const wordsArray = dayDoc.getArray('words');
  const currentWords = wordsArray.toArray();
  const nextWordIndex = currentWords.length + 1;
  const wordId = Date.now();

  const cleanNative = (wordData.native_script || '').trim();
  const cleanPron = (wordData.pronunciation || '').trim();
  const cleanLink = wordData.link ? wordData.link.trim() : null;

  const newWordRecord = {
    id: wordId,
    word_index: nextWordIndex,
    native_script: cleanNative,
    pronunciation: cleanPron,
    link: cleanLink,
    audio_duration: 0
  };

  // 1. Mutate Day Document
  wordsArray.push([newWordRecord]);

  // 2. Cross-index into {lang}:vocab_index
  const vocabHandle = getDocHandle(`${langCode}:vocab_index`);
  if (vocabHandle?.doc && cleanNative.length > 0) {
    const vocabEntries = vocabHandle.doc.getArray('entries');
    const flatList = vocabEntries.toArray().flat();
    const exists = flatList.some(
      (e) => e.native_script === cleanNative && e.pronunciation === cleanPron
    );

    if (!exists) {
      vocabEntries.push([
        {
          word_id: wordId,
          native_script: cleanNative,
          pronunciation: cleanPron,
          link: cleanLink,
          date: dateStr
        }
      ]);
    }
  }

  // 3. Mutate SRS Room ({lang}:srs) -> 'visual', 'listening', and 'writing'
  const srsHandle = getDocHandle(`${langCode}:srs`);
  if (srsHandle?.doc) {
    const queueMap = srsHandle.doc.getMap('queue');

    const cardPayload = {
      due_date: dateStr,
      interval: 0,
      ease: 2.50,
      native: cleanNative,
      pronunciation: cleanPron,
      link: cleanLink,
      source_date: dateStr
    };

    queueMap.set(`${dateStr}:w${wordId}:visual`, {
      ...cardPayload,
      card_type: 'visual'
    });

    queueMap.set(`${dateStr}:w${wordId}:listening`, {
      ...cardPayload,
      card_type: 'listening'
    });

    queueMap.set(`${dateStr}:w${wordId}:writing`, {
      ...cardPayload,
      card_type: 'writing'
    });
  }

  // 4. Refresh global totals once
  metadataStore.refreshDayTotals(langCode, dateStr);

  return newWordRecord;
}

/**
 * Updates word text/link and updates vocab_index and SRS cards.
 */
export async function updateWordInDay({ langCode, dateStr, dayDocHandle, wordIndex, wordData }) {
  if (!dayDocHandle?.doc) throw new Error('Day document handle unavailable.');

  const { doc: dayDoc } = dayDocHandle;
  const wordsArray = dayDoc.getArray('words');
  const words = wordsArray.toArray();

  const targetIdx = words.findIndex((w) => (w.word_index ?? w.id) === wordIndex);
  if (targetIdx === -1) throw new Error(`Word #${wordIndex} not found.`);

  const existing = words[targetIdx];
  const cleanNative = (wordData.native_script || '').trim();
  const cleanPron = (wordData.pronunciation || '').trim();
  const cleanLink = wordData.link ? wordData.link.trim() : null;

  const updatedRecord = {
    ...existing,
    native_script: cleanNative,
    pronunciation: cleanPron,
    link: cleanLink
  };

  dayDoc.transact(() => {
    wordsArray.delete(targetIdx, 1);
    wordsArray.insert(targetIdx, [updatedRecord]);
  });

  const wordId = existing.id;

  // Update in Vocab Index
  const vocabHandle = getDocHandle(`${langCode}:vocab_index`);
  if (vocabHandle?.doc) {
    const vocabEntries = vocabHandle.doc.getArray('entries');
    const flatList = vocabEntries.toArray().flat();
    const vIdx = flatList.findIndex((e) => e.word_id === wordId);

    if (vIdx !== -1) {
      vocabHandle.doc.transact(() => {
        vocabEntries.delete(vIdx, 1);
        vocabEntries.insert(vIdx, [
          {
            word_id: wordId,
            native_script: cleanNative,
            pronunciation: cleanPron,
            link: cleanLink,
            date: dateStr
          }
        ]);
      });
    }
  }

  // Update in SRS Queue
  const srsHandle = getDocHandle(`${langCode}:srs`);
  if (srsHandle?.doc) {
    const queueMap = srsHandle.doc.getMap('queue');
    ['visual', 'listening', 'writing'].forEach((type) => {
      const cardKey = `${dateStr}:w${wordId}:${type}`;
      const prevCard = queueMap.get(cardKey);
      if (prevCard) {
        queueMap.set(cardKey, {
          ...prevCard,
          native: cleanNative,
          pronunciation: cleanPron,
          link: cleanLink
        });
      }
    });
  }

  metadataStore.refreshDayTotals(langCode, dateStr);
  return updatedRecord;
}

/**
 * Adds CI activity and updates deduplication index with canonical URLs.
 */
export async function addCIToDay({ langCode, dateStr, dayDocHandle, ciData }) {
  if (!dayDocHandle?.doc) throw new Error('Day document handle unavailable.');

  const { doc: dayDoc } = dayDocHandle;
  const activitiesArray = dayDoc.getArray('activities');
  const activities = activitiesArray.toArray();
  const nextItemIndex = activities.filter((a) => a.activity_type === 'ci').length + 1;

  // Clean and canonicalize link (removes tracking params, normalizes YouTube)
  const cleanLink = canonicalizeMediaUrl(ciData.link);

  const newActivity = {
    activity_type: 'ci',
    item_index: nextItemIndex,
    link: cleanLink,
    link_duration: Number(ciData.durationSec) || 0,
    audio_duration: 0,
    metadata: null
  };

  activitiesArray.push([newActivity]);

  // Track in CI Deduplication Index
  if (cleanLink) {
    const ciHandle = getDocHandle(`${langCode}:ci_index`);
    if (ciHandle?.doc) {
      const links = ciHandle.doc.getArray('links');
      if (!links.toArray().flat().includes(cleanLink)) {
        links.push([cleanLink]);
      }
    }
  }

  metadataStore.refreshDayTotals(langCode, dateStr);
  return newActivity;
}

/**
 * Updates an existing CI entry with canonical URL.
 */
export async function updateCIInDay({ langCode, dateStr, dayDocHandle, itemIndex, ciData }) {
  if (!dayDocHandle?.doc) throw new Error('Day document handle unavailable.');

  const { doc: dayDoc } = dayDocHandle;
  const activitiesArray = dayDoc.getArray('activities');
  const activities = activitiesArray.toArray();

  const targetIdx = activities.findIndex(
    (a) => a.activity_type === 'ci' && a.item_index === itemIndex
  );
  if (targetIdx === -1) throw new Error(`CI entry #${itemIndex} not found.`);

  const oldEntry = activities[targetIdx];
  const cleanLink = canonicalizeMediaUrl(ciData.link);

  const updatedActivity = {
    ...oldEntry,
    link: cleanLink,
    link_duration: Number(ciData.durationSec) || 0
  };

  dayDoc.transact(() => {
    activitiesArray.delete(targetIdx, 1);
    activitiesArray.insert(targetIdx, [updatedActivity]);
  });

  // Track updated URL in CI index if not already present
  if (cleanLink) {
    const ciHandle = getDocHandle(`${langCode}:ci_index`);
    if (ciHandle?.doc) {
      const links = ciHandle.doc.getArray('links');
      if (!links.toArray().flat().includes(cleanLink)) {
        links.push([cleanLink]);
      }
    }
  }

  metadataStore.refreshDayTotals(langCode, dateStr);
  return updatedActivity;
}

/**
 * Adds Listening activity and records canonical URL in listening_index.
 */
export async function addListeningToDay({ langCode, dateStr, dayDocHandle, listeningData }) {
  if (!dayDocHandle?.doc) throw new Error('Day document handle unavailable.');

  const { doc: dayDoc } = dayDocHandle;
  const activitiesArray = dayDoc.getArray('activities');
  const activities = activitiesArray.toArray();
  const nextItemIndex = activities.filter((a) => a.activity_type === 'listening').length + 1;

  const cleanLink = canonicalizeMediaUrl(listeningData.link);

  const newActivity = {
    activity_type: 'listening',
    item_index: nextItemIndex,
    link: cleanLink,
    link_duration: Number(listeningData.durationSec) || 0,
    audio_duration: 0,
    metadata: null
  };

  activitiesArray.push([newActivity]);

  if (cleanLink) {
    const listHandle = getDocHandle(`${langCode}:listening_index`);
    if (listHandle?.doc) {
      listHandle.doc.getArray('entries').push([{ date: dateStr, link: cleanLink }]);
    }
  }

  metadataStore.refreshDayTotals(langCode, dateStr);
  return newActivity;
}

/**
 * Updates an existing Listening activity with canonical URL.
 */
export async function updateListeningInDay({ langCode, dateStr, dayDocHandle, itemIndex, listeningData }) {
  if (!dayDocHandle?.doc) throw new Error('Day document handle unavailable.');

  const { doc: dayDoc } = dayDocHandle;
  const activitiesArray = dayDoc.getArray('activities');
  const activities = activitiesArray.toArray();

  const targetIdx = activities.findIndex(
    (a) => a.activity_type === 'listening' && a.item_index === itemIndex
  );
  if (targetIdx === -1) throw new Error(`Listening entry #${itemIndex} not found.`);

  const oldEntry = activities[targetIdx];
  const cleanLink = canonicalizeMediaUrl(listeningData.link);

  const updatedActivity = {
    ...oldEntry,
    link: cleanLink,
    link_duration: Number(listeningData.durationSec) || 0
  };

  dayDoc.transact(() => {
    activitiesArray.delete(targetIdx, 1);
    activitiesArray.insert(targetIdx, [updatedActivity]);
  });

  metadataStore.refreshDayTotals(langCode, dateStr);
  return updatedActivity;
}

/**
 * Adds Grammar pattern activity.
 */
export async function addGrammarToDay({ langCode, dateStr, dayDocHandle, grammarData }) {
  if (!dayDocHandle?.doc) throw new Error('Day document handle unavailable.');

  const { doc: dayDoc } = dayDocHandle;
  const activitiesArray = dayDoc.getArray('activities');
  const activities = activitiesArray.toArray();
  const nextItemIndex = activities.filter((a) => a.activity_type === 'grammar').length + 1;

  const newActivity = {
    activity_type: 'grammar',
    item_index: nextItemIndex,
    link: grammarData.link ? grammarData.link.trim() : null,
    link_duration: 0,
    audio_duration: 0,
    metadata: {
      title: (grammarData.title || '').trim(),
      pronunciation: (grammarData.pronunciation || '').trim(),
      structure: (grammarData.structure || '').trim(),
      meaning: (grammarData.meaning || '').trim()
    }
  };

  activitiesArray.push([newActivity]);

  metadataStore.refreshDayTotals(langCode, dateStr);
  return newActivity;
}

/**
 * Updates an existing Grammar pattern.
 */
export async function updateGrammarInDay({ dayDocHandle, itemIndex, grammarData, langCode, dateStr }) {
  if (!dayDocHandle?.doc) throw new Error('Day document handle unavailable.');

  const { doc: dayDoc } = dayDocHandle;
  const activitiesArray = dayDoc.getArray('activities');
  const activities = activitiesArray.toArray();

  const targetIdx = activities.findIndex(
    (a) => a.activity_type === 'grammar' && a.item_index === itemIndex
  );
  if (targetIdx === -1) throw new Error(`Grammar entry #${itemIndex} not found.`);

  const oldEntry = activities[targetIdx];
  const updatedActivity = {
    ...oldEntry,
    link: grammarData.link ? grammarData.link.trim() : null,
    metadata: {
      title: (grammarData.title || '').trim(),
      pronunciation: (grammarData.pronunciation || '').trim(),
      structure: (grammarData.structure || '').trim(),
      meaning: (grammarData.meaning || '').trim()
    }
  };

  dayDoc.transact(() => {
    activitiesArray.delete(targetIdx, 1);
    activitiesArray.insert(targetIdx, [updatedActivity]);
  });

  if (langCode && dateStr) {
    metadataStore.refreshDayTotals(langCode, dateStr);
  }

  return updatedActivity;
}