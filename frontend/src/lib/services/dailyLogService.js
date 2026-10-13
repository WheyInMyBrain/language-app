import { initLocalDatabase, stageLocalMutation } from '../db.js';
import { metadataStore } from '../stores/metadata.svelte.js';
import { vocabIndexStore } from '../stores/vocabIndex.svelte.js';
import { ciIndexStore } from '../stores/ciIndex.svelte.js';
import { listeningIndexStore } from '../stores/listeningIndex.svelte.js';
import { srsStore } from '../stores/srs.svelte.js';
import { canonicalizeMediaUrl } from '../media.js';

/**
 * Adds a new word to the active day and cross-indexes into vocab_index & word_srs.
 */
export async function addWordToDay({ langCode, dateStr, wordData }) {
  const db = await initLocalDatabase();

  // 1. Determine next word index for this specific day
  const existingWords = await db.getAllFromIndex('words', 'by_lang_date', [langCode, dateStr]);
  const activeWords = existingWords.filter((w) => !w.deleted_at);
  const nextWordIndex = activeWords.length + 1;
  const wordId = crypto.randomUUID();

  const cleanNative = (wordData.native_script || '').trim();
  const cleanPron = (wordData.pronunciation || '').trim();
  const cleanLink = wordData.link ? wordData.link.trim() : null;

  const newWordRecord = {
    id: wordId,
    lang_code: langCode,
    log_date: dateStr,
    word_index: nextWordIndex,
    native_script: cleanNative,
    pronunciation: cleanPron,
    link: cleanLink,
    audio_duration: 0,
    deleted_at: null
  };

  // 2. Persist word locally & stage in outbox
  await stageLocalMutation('words', wordId, newWordRecord);

  // 3. Generate and stage SRS cards: 'visual', 'listening', and 'writing'
  const cardTypes = ['visual', 'listening', 'writing'];
  for (const cardType of cardTypes) {
    const cardKey = `${langCode}:${wordId}:${cardType}`;
    const srsCard = {
      card_key: cardKey,
      lang_code: langCode,
      word_id: wordId,
      card_type: cardType,
      native_script: cleanNative,
      pronunciation: cleanPron,
      due_date: dateStr,
      interval: 0,
      ease: 2.50,
      reps: 0,
      lapses: 0,
      last_reviewed: null,
      deleted_at: null
    };

    await stageLocalMutation('word_srs', cardKey, srsCard);

    // Update in-memory SRS store if currently loaded
    if (srsStore.activeLang === langCode) {
      srsStore.cards[cardKey] = srsCard;
    }
  }

  // 4. Refresh local index caches & day totals
  await vocabIndexStore.refresh();
  await metadataStore.refreshDayTotals(langCode, dateStr);

  return newWordRecord;
}

/**
 * Updates word text/link and updates vocab_index and word_srs cards.
 */
export async function updateWordInDay({ langCode, dateStr, wordId, wordData }) {
  const db = await initLocalDatabase();
  const existing = await db.get('words', wordId);
  if (!existing || existing.deleted_at) throw new Error(`Word ${wordId} not found.`);

  const cleanNative = (wordData.native_script || '').trim();
  const cleanPron = (wordData.pronunciation || '').trim();
  const cleanLink = wordData.link ? wordData.link.trim() : null;

  const updatedRecord = {
    ...existing,
    native_script: cleanNative,
    pronunciation: cleanPron,
    link: cleanLink
  };

  // 1. Update word record
  await stageLocalMutation('words', wordId, updatedRecord);

  // 2. Update associated SRS cards
  const cardTypes = ['visual', 'listening', 'writing'];
  for (const cardType of cardTypes) {
    const cardKey = `${langCode}:${wordId}:${cardType}`;
    const existingCard = await db.get('word_srs', cardKey);
    if (existingCard) {
      const updatedCard = {
        ...existingCard,
        native_script: cleanNative,
        pronunciation: cleanPron
      };
      await stageLocalMutation('word_srs', cardKey, updatedCard);

      if (srsStore.activeLang === langCode) {
        srsStore.cards[cardKey] = updatedCard;
      }
    }
  }

  // 3. Refresh store caches & day totals
  await vocabIndexStore.refresh();
  await metadataStore.refreshDayTotals(langCode, dateStr);

  return updatedRecord;
}

/**
 * Adds CI activity and updates deduplication index with canonical URLs.
 */
export async function addCIToDay({ langCode, dateStr, ciData }) {
  const db = await initLocalDatabase();
  const existingActs = await db.getAllFromIndex('activities', 'by_lang_date', [langCode, dateStr]);
  const nextItemIndex = existingActs.filter((a) => a.activity_type === 'ci' && !a.deleted_at).length + 1;
  const activityId = crypto.randomUUID();

  const cleanLink = canonicalizeMediaUrl(ciData.link);

  const newActivity = {
    id: activityId,
    lang_code: langCode,
    log_date: dateStr,
    activity_type: 'ci',
    item_index: nextItemIndex,
    link: cleanLink,
    link_duration: Number(ciData.durationSec) || 0,
    audio_duration: 0,
    metadata_json: '{}',
    deleted_at: null
  };

  await stageLocalMutation('activities', activityId, newActivity);

  await ciIndexStore.refresh();
  await metadataStore.refreshDayTotals(langCode, dateStr);

  return newActivity;
}

/**
 * Updates an existing CI entry with canonical URL.
 */
export async function updateCIInDay({ langCode, dateStr, activityId, ciData }) {
  const db = await initLocalDatabase();
  const existing = await db.get('activities', activityId);
  if (!existing || existing.deleted_at) throw new Error(`CI entry ${activityId} not found.`);

  const cleanLink = canonicalizeMediaUrl(ciData.link);

  const updatedActivity = {
    ...existing,
    link: cleanLink,
    link_duration: Number(ciData.durationSec) || 0
  };

  await stageLocalMutation('activities', activityId, updatedActivity);

  await ciIndexStore.refresh();
  await metadataStore.refreshDayTotals(langCode, dateStr);

  return updatedActivity;
}

/**
 * Adds Listening activity and records canonical URL in listening_index.
 */
export async function addListeningToDay({ langCode, dateStr, listeningData }) {
  const db = await initLocalDatabase();
  const existingActs = await db.getAllFromIndex('activities', 'by_lang_date', [langCode, dateStr]);
  const nextItemIndex = existingActs.filter((a) => a.activity_type === 'listening' && !a.deleted_at).length + 1;
  const activityId = crypto.randomUUID();

  const cleanLink = canonicalizeMediaUrl(listeningData.link);

  const newActivity = {
    id: activityId,
    lang_code: langCode,
    log_date: dateStr,
    activity_type: 'listening',
    item_index: nextItemIndex,
    link: cleanLink,
    link_duration: Number(listeningData.durationSec) || 0,
    audio_duration: 0,
    metadata_json: '{}',
    deleted_at: null
  };

  await stageLocalMutation('activities', activityId, newActivity);

  await listeningIndexStore.refresh();
  await metadataStore.refreshDayTotals(langCode, dateStr);

  return newActivity;
}

/**
 * Updates an existing Listening activity with canonical URL.
 */
export async function updateListeningInDay({ langCode, dateStr, activityId, listeningData }) {
  const db = await initLocalDatabase();
  const existing = await db.get('activities', activityId);
  if (!existing || existing.deleted_at) throw new Error(`Listening entry ${activityId} not found.`);

  const cleanLink = canonicalizeMediaUrl(listeningData.link);

  const updatedActivity = {
    ...existing,
    link: cleanLink,
    link_duration: Number(listeningData.durationSec) || 0
  };

  await stageLocalMutation('activities', activityId, updatedActivity);

  await listeningIndexStore.refresh();
  await metadataStore.refreshDayTotals(langCode, dateStr);

  return updatedActivity;
}

/**
 * Adds Grammar pattern activity.
 */
export async function addGrammarToDay({ langCode, dateStr, grammarData }) {
  const db = await initLocalDatabase();
  const existingActs = await db.getAllFromIndex('activities', 'by_lang_date', [langCode, dateStr]);
  const nextItemIndex = existingActs.filter((a) => a.activity_type === 'grammar' && !a.deleted_at).length + 1;
  const activityId = crypto.randomUUID();

  const metadataObj = {
    title: (grammarData.title || '').trim(),
    pronunciation: (grammarData.pronunciation || '').trim(),
    structure: (grammarData.structure || '').trim(),
    meaning: (grammarData.meaning || '').trim()
  };

  const newActivity = {
    id: activityId,
    lang_code: langCode,
    log_date: dateStr,
    activity_type: 'grammar',
    item_index: nextItemIndex,
    link: grammarData.link ? grammarData.link.trim() : null,
    link_duration: 0,
    audio_duration: 0,
    metadata_json: JSON.stringify(metadataObj),
    deleted_at: null
  };

  await stageLocalMutation('activities', activityId, newActivity);
  await metadataStore.refreshDayTotals(langCode, dateStr);

  return newActivity;
}

/**
 * Updates an existing Grammar pattern.
 */
export async function updateGrammarInDay({ langCode, dateStr, activityId, grammarData }) {
  const db = await initLocalDatabase();
  const existing = await db.get('activities', activityId);
  if (!existing || existing.deleted_at) throw new Error(`Grammar entry ${activityId} not found.`);

  const metadataObj = {
    title: (grammarData.title || '').trim(),
    pronunciation: (grammarData.pronunciation || '').trim(),
    structure: (grammarData.structure || '').trim(),
    meaning: (grammarData.meaning || '').trim()
  };

  const updatedActivity = {
    ...existing,
    link: grammarData.link ? grammarData.link.trim() : null,
    metadata_json: JSON.stringify(metadataObj)
  };

  await stageLocalMutation('activities', activityId, updatedActivity);

  if (langCode && dateStr) {
    await metadataStore.refreshDayTotals(langCode, dateStr);
  }

  return updatedActivity;
}