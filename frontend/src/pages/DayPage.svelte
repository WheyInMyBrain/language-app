<!-- frontend/src/pages/DayPage.svelte -->
<script>
  import { createSyncedDoc } from '../lib/yjs.js';
  import { 
    addWordToDay, 
    updateWordInDay, 
    addCIToDay, 
    updateCIInDay, 
    addListeningToDay, 
    updateListeningInDay, 
    addGrammarToDay, 
    updateGrammarInDay 
  } from '../lib/services/dailyLogService.js';
  import { ciIndexStore } from '../lib/stores/ciIndex.svelte.js';
  import { listeningIndexStore } from '../lib/stores/listeningIndex.svelte.js';
  import { metadataStore } from '../lib/stores/metadata.svelte.js';
  import { processSessionSRSReview } from '../lib/services/srsService.js';

  // Creator Bars
  import VocabBar from '../components/VocabBar.svelte';
  import CIBar from '../components/CIBar.svelte';
  import ListeningBar from '../components/ListeningBar.svelte';
  import GrammarBar from '../components/GrammarBar.svelte';

  // Cards
  import VocabCard from '../components/VocabCard.svelte';
  import CICard from '../components/CICard.svelte';
  import ListeningCard from '../components/ListeningCard.svelte';
  import GrammarCard from '../components/GrammarCard.svelte';

  // SRS
  import SRSBar from '../components/SRSBar.svelte';

  let { date, langCode } = $props();

  let dayHandle = null;
  let words = $state([]);
  let activities = $state([]);
  let session = $state({ revision: 0, interval: 0, ease: 2.5, due_date: null });
  let isLoaded = $state(false);

  let ciActivities = $derived(
    activities.filter((a) => a.activity_type === 'ci')
  );
  let listeningActivities = $derived(
    activities.filter((a) => a.activity_type === 'listening')
  );
  let grammarActivities = $derived(
    activities.filter((a) => a.activity_type === 'grammar')
  );

  $effect(() => {
    const curDate = date;
    const curLang = langCode;
    if (!curDate || !curLang) return;

    ciIndexStore.connect(curLang);
    listeningIndexStore.connect(curLang);

    isLoaded = false;
    words = [];
    activities = [];
    session = { revision: 0, interval: 0, ease: 2.5, due_date: curDate };

    const roomName = `${curLang}:${curDate}`;
    dayHandle = createSyncedDoc(roomName);

    const { doc, idbProvider, wsProvider } = dayHandle;
    const wordsArray = doc.getArray('words');
    const activitiesArray = doc.getArray('activities');
    const metaMap = doc.getMap('meta');

    const sync = () => {
      words = wordsArray.toArray();
      activities = activitiesArray.toArray();
      
      const rawSession = metaMap.get('session');

      if (rawSession) {
        session = {
          revision: Number(rawSession.revision ?? 0),
          interval: Number(rawSession.interval ?? 0),
          ease: Number(rawSession.ease ?? 2.50),
          due_date: rawSession.due_date || curDate
        };
      }
    };

    const handleSynced = () => {
      sync();
      isLoaded = true;
    };

    wordsArray.observe(sync);
    activitiesArray.observe(sync);
    metaMap.observe(sync);

    doc.on('update', sync);

    idbProvider.on('synced', handleSynced);

    const handleWsSync = (isSynced) => {
      if (isSynced) {
        handleSynced();
      }
    };
    wsProvider.on('sync', handleWsSync);

    if (idbProvider.synced) {
      handleSynced();
    }

    return () => {
      doc.off('update', sync);
      idbProvider.off('synced', handleSynced);
      wsProvider.off('sync', handleWsSync);
      wordsArray.unobserve(sync);
      activitiesArray.unobserve(sync);
      metaMap.unobserve(sync);
      if (dayHandle) {
        dayHandle.destroy();
        dayHandle = null;
      }
    };
  });

  // Helper to recompute stats and update global:metadata
  function syncMetadataTotals() {
    metadataStore.refreshDayTotals(langCode, date);
  }

  // 1. Vocab Handlers
  async function handleAddWord(payload) {
    if (!dayHandle) return;
    await addWordToDay({ langCode, dateStr: date, dayDocHandle: dayHandle, wordData: payload });
    syncMetadataTotals();
  }

  async function handleUpdateWord(wordIndex, payload) {
    if (!dayHandle) return;
    await updateWordInDay({ langCode, dateStr: date, dayDocHandle: dayHandle, wordIndex, wordData: payload });
    syncMetadataTotals();
  }

  // 2. CI Handlers
  async function handleAddCI(payload) {
    if (!dayHandle) return;
    await addCIToDay({ langCode, dateStr: date, dayDocHandle: dayHandle, ciData: payload });
    syncMetadataTotals();
  }

  async function handleUpdateCI(itemIndex, payload) {
    if (!dayHandle) return;
    await updateCIInDay({ langCode, dateStr: date, dayDocHandle: dayHandle, itemIndex, ciData: payload });
    syncMetadataTotals();
  }

  // 3. Listening Handlers
  async function handleAddListening(payload) {
    if (!dayHandle) return;
    await addListeningToDay({ langCode, dateStr: date, dayDocHandle: dayHandle, listeningData: payload });
    syncMetadataTotals();
  }

  async function handleUpdateListening(itemIndex, payload) {
    if (!dayHandle) return;
    await updateListeningInDay({ langCode, dateStr: date, dayDocHandle: dayHandle, itemIndex, listeningData: payload });
    syncMetadataTotals();
  }

  // 4. Grammar Handlers
  async function handleAddGrammar(payload) {
    if (!dayHandle) return;
    await addGrammarToDay({ langCode, dateStr: date, dayDocHandle: dayHandle, grammarData: payload });
    syncMetadataTotals();
  }

  async function handleUpdateGrammar(itemIndex, payload) {
    if (!dayHandle) return;
    await updateGrammarInDay({ langCode, dateStr: date, dayDocHandle: dayHandle, itemIndex, grammarData: payload });
    syncMetadataTotals();
  }

  // 5. SRS Review Handler (Updates revision which alters min(3, rev) * ci multiplier)
  async function handleSRSReview(grade) {
    if (!dayHandle) return;
    await processSessionSRSReview({
      langCode,
      dateStr: date,
      dayDocHandle: dayHandle,
      grade
    });
    syncMetadataTotals();
  }
</script>

<div class="max-w-md mx-auto space-y-8 pt-2 pb-24 px-1">
  {#if !isLoaded}
    <div class="py-12 text-center text-xs text-[var(--text-muted)] animate-pulse">
      Syncing session for {date}...
    </div>
  {:else}
    <!-- 1. VOCABULARY SECTION -->
    <section class="space-y-3">
      <VocabBar
        {words}
        activeDate={date}
        onAddWord={handleAddWord}
        onUpdateWord={handleUpdateWord}
      />

      {#if words.length > 0}
        <div class="space-y-3 pt-1">
          {#each words as word, i (`${date}_w_${word.id ?? ''}_${i}`)}
            <VocabCard
              lang={langCode}
              {date}
              {word}
              index={word.word_index ?? (i + 1)}
              isOpen={true}
            />
          {/each}
        </div>
      {/if}
    </section>

    <!-- 2. COMPREHENSIBLE INPUT SECTION -->
    <section class="space-y-3">
      <CIBar
        {ciActivities}
        activeDate={date}
        onAddCI={handleAddCI}
        onUpdateCI={handleUpdateCI}
      />

      {#if ciActivities.length > 0}
        <div class="space-y-3 pt-1">
          {#each ciActivities as activity, i (`${date}_ci_${activity.item_index ?? ''}_${i}`)}
            <CICard
              lang={langCode}
              {date}
              {activity}
              index={activity.item_index ?? (i + 1)}
              isOpen={true}
            />
          {/each}
        </div>
      {/if}
    </section>

    <!-- 3. LISTENING PRACTICE SECTION -->
    <section class="space-y-3">
      <ListeningBar
        {listeningActivities}
        activeDate={date}
        onAddListening={handleAddListening}
        onUpdateListening={handleUpdateListening}
      />

      {#if listeningActivities.length > 0}
        <div class="space-y-3 pt-1">
          {#each listeningActivities as activity, i (`${date}_list_${activity.item_index ?? ''}_${i}`)}
            <ListeningCard
              lang={langCode}
              {date}
              {activity}
              index={activity.item_index ?? (i + 1)}
              isOpen={true}
            />
          {/each}
        </div>
      {/if}
    </section>

    <!-- 4. GRAMMAR & PATTERNS SECTION -->
    <section class="space-y-3">
      <GrammarBar
        {grammarActivities}
        activeDate={date}
        onAddGrammar={handleAddGrammar}
        onUpdateGrammar={handleUpdateGrammar}
      />

      {#if grammarActivities.length > 0}
        <div class="space-y-3 pt-1">
          {#each grammarActivities as activity, i (`${date}_gram_${activity.item_index ?? ''}_${i}`)}
            <GrammarCard
              lang={langCode}
              {date}
              {activity}
              index={activity.item_index ?? (i + 1)}
              isOpen={true}
            />
          {/each}
        </div>
      {/if}
    </section>

    <!-- 5. BOTTOM SRS REVISION BAR -->
    <section class="pt-4 border-t border-[var(--border-card)]">
      <SRSBar
        {session}
        activeDate={date}
        onReview={handleSRSReview}
      />
    </section>
  {/if}
</div>