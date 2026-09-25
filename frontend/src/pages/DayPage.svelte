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
  import { activeLanguage } from '../lib/stores/activeLanguage.svelte.js';
  import { processSessionSRSReview } from '../lib/services/srsService.js';

  // Components
  import OmniBar from '../components/OmniBar.svelte';
  import OmniCard from '../components/OmniCard.svelte';
  import SRSBar from '../components/SRSBar.svelte';

  // Vector Icons
  import { 
    Sparkles, 
    Compass,
    ChevronLeft,
    ChevronRight,
    MessageSquare,
    Play,
    Headphones,
    BookOpen,
    Layers,
    Plus
  } from '@lucide/svelte';

  let { date, langCode, onSelectDate } = $props();

  let dayHandle = null;
  let words = $state([]);
  let activities = $state([]);
  let session = $state({ revision: 0, interval: 0, ease: 2.5, due_date: null });
  let isLoaded = $state(false);
  let activeFilter = $state('all'); // 'all' | 'vocab' | 'ci' | 'listening' | 'grammar'

  // Dynamic Language Theme Colors
  let colors = $derived(activeLanguage.colors || {});
  let goals = $derived(activeLanguage.goals || {});
  let themeColor = $derived(activeLanguage.themeColor || colors.theme || '#a855f7');
  let langConfig = $derived(activeLanguage.current || {});

  let vocabColor = $derived(colors.vocab?.primary || colors.vocab?.dark_primary || '#10b981');
  let ciColor = $derived(colors.ci?.primary || colors.ci?.dark_primary || '#a855f7');
  let listeningColor = $derived(colors.listening?.primary || colors.listening?.dark_primary || '#f97316');
  let grammarColor = $derived(colors.grammar?.primary || colors.grammar?.dark_primary || '#0ea5e9');

  // Isolated activity slices
  let ciActivities = $derived(activities.filter((a) => a.activity_type === 'ci'));
  let listeningActivities = $derived(activities.filter((a) => a.activity_type === 'listening'));
  let grammarActivities = $derived(activities.filter((a) => a.activity_type === 'grammar'));

  let totalItemsCount = $derived(
    words.length + ciActivities.length + listeningActivities.length + grammarActivities.length
  );

  let formattedDisplayDate = $derived.by(() => {
    if (!date) return '';
    try {
      const [y, m, d] = date.split('-').map(Number);
      const parsed = new Date(y, m - 1, d);
      return parsed.toLocaleDateString(undefined, { 
        weekday: 'short', 
        month: 'short', 
        day: 'numeric',
        year: 'numeric'
      });
    } catch {
      return date;
    }
  });

  function navigateDate(offsetDays) {
    if (!date || !onSelectDate) return;
    try {
      const [y, m, d] = date.split('-').map(Number);
      const target = new Date(y, m - 1, d);
      target.setDate(target.getDate() + offsetDays);
      const year = target.getFullYear();
      const month = String(target.getMonth() + 1).padStart(2, '0');
      const day = String(target.getDate()).padStart(2, '0');
      onSelectDate(`${year}-${month}-${day}`);
    } catch (e) {
      console.error('Failed to scrub date:', e);
    }
  }

  // Yjs Sync Effect
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

    let syncPending = false;
    const batchedSync = () => {
      if (syncPending) return;
      syncPending = true;
      queueMicrotask(() => {
        syncPending = false;
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
      });
    };

    const handleSynced = () => {
      batchedSync();
      isLoaded = true;
    };

    doc.on('afterTransaction', batchedSync);
    idbProvider.on('synced', handleSynced);

    const handleWsSync = (isSynced) => {
      if (isSynced) handleSynced();
    };
    wsProvider.on('sync', handleWsSync);

    if (idbProvider.synced) handleSynced();

    return () => {
      doc.off('afterTransaction', batchedSync);
      idbProvider.off('synced', handleSynced);
      wsProvider.off('sync', handleWsSync);
      if (dayHandle) {
        dayHandle.destroy();
        dayHandle = null;
      }
    };
  });

  function syncMetadataTotals() {
    metadataStore.refreshDayTotals(langCode, date);
  }

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

  async function handleSRSReview(grade) {
    if (!dayHandle) return;
    await processSessionSRSReview({ langCode, dateStr: date, dayDocHandle: dayHandle, grade });
    syncMetadataTotals();
  }
</script>

<div 
  class="relative w-full max-w-5xl xl:max-w-6xl mx-auto space-y-6 pt-1 sm:pt-2 pb-24 px-2 sm:px-4 md:px-6 select-none box-border"
  style="--day-accent: {themeColor};"
>
  {#if !isLoaded}
    <div class="py-24 flex flex-col items-center justify-center space-y-3 text-center">
      <div 
        class="w-10 h-10 rounded-2xl flex items-center justify-center animate-spin border shadow-xs"
        style="background-color: color-mix(in srgb, var(--day-accent) 15%, transparent); border-color: color-mix(in srgb, var(--day-accent) 35%, transparent); color: var(--day-accent);"
      >
        <Sparkles size={18} />
      </div>
      <p class="text-xs font-mono font-bold text-[var(--text-muted)] animate-pulse">
        Synchronizing session canvas...
      </p>
    </div>
  {:else}

    <!-- 🌟 1. UNIFIED GLASS RAIL HEADER WITH DATE SCRUBBING & ACTIVITY SPARKLINES 🌟 -->
    <header class="flex items-center justify-between gap-3 pb-3 border-b border-[var(--border-subtle)] relative z-20 flex-wrap sm:flex-nowrap">
      
      <!-- Date Scrubber Capsule -->
      <div class="flex items-center gap-2">
        <div class="flex items-center p-1 rounded-2xl bg-[var(--bg-surface)] border border-[var(--border-subtle)] shadow-xs">
          <button
            type="button"
            onclick={() => navigateDate(-1)}
            aria-label="Previous Day"
            class="w-8 h-8 rounded-xl flex items-center justify-center text-[var(--text-muted)] hover:text-[var(--text-primary)] hover:bg-[var(--bg-surface-elevated)] transition-all active:scale-90 cursor-pointer"
          >
            <ChevronLeft size={16} strokeWidth={2.5} />
          </button>

          <div class="px-3 text-center min-w-[130px] sm:min-w-[170px]">
            <h1 class="text-sm sm:text-base font-black tracking-tight text-[var(--text-primary)] leading-tight">
              {formattedDisplayDate}
            </h1>
            <span class="text-[9px] font-mono text-[var(--text-muted)] hidden sm:inline-flex items-center gap-1">
              <Compass size={10} style="color: var(--day-accent);" />
              <span>{langConfig.name || langCode} Workspace</span>
            </span>
          </div>

          <button
            type="button"
            onclick={() => navigateDate(1)}
            aria-label="Next Day"
            class="w-8 h-8 rounded-xl flex items-center justify-center text-[var(--text-muted)] hover:text-[var(--text-primary)] hover:bg-[var(--bg-surface-elevated)] transition-all active:scale-90 cursor-pointer"
          >
            <ChevronRight size={16} strokeWidth={2.5} />
          </button>
        </div>
      </div>

      <!-- Right: Sparkline Distribution & Entry Count -->
      <div class="flex items-center gap-2.5 font-mono text-[10px] font-bold">
        <div 
          class="flex items-center gap-1 px-2.5 py-1.5 rounded-xl bg-[var(--bg-surface)] border border-[var(--border-subtle)] shadow-xs"
          title="Daily Study Distribution (Vocab, CI, Listening, Grammar)"
        >
          <span 
            class="w-2 h-3 rounded-full transition-opacity" 
            style="background-color: {vocabColor}; opacity: {words.length > 0 ? 1 : 0.2}; box-shadow: {words.length > 0 ? `0 0 6px ${vocabColor}` : 'none'};"
          ></span>
          <span 
            class="w-2 h-3 rounded-full transition-opacity" 
            style="background-color: {ciColor}; opacity: {ciActivities.length > 0 ? 1 : 0.2}; box-shadow: {ciActivities.length > 0 ? `0 0 6px ${ciColor}` : 'none'};"
          ></span>
          <span 
            class="w-2 h-3 rounded-full transition-opacity" 
            style="background-color: {listeningColor}; opacity: {listeningActivities.length > 0 ? 1 : 0.2}; box-shadow: {listeningActivities.length > 0 ? `0 0 6px ${listeningColor}` : 'none'};"
          ></span>
          <span 
            class="w-2 h-3 rounded-full transition-opacity" 
            style="background-color: {grammarColor}; opacity: {grammarActivities.length > 0 ? 1 : 0.2}; box-shadow: {grammarActivities.length > 0 ? `0 0 6px ${grammarColor}` : 'none'};"
          ></span>
        </div>

        <span class="px-3 py-1.5 rounded-xl bg-[var(--bg-surface)] border border-[var(--border-subtle)] text-[var(--text-muted)] shadow-xs">
          {totalItemsCount} {totalItemsCount === 1 ? 'entry' : 'entries'}
        </span>
      </div>
    </header>

    <!-- 🌟 2. STABLE MAXIMUM ENVELOPE DOCK (Clean: Zero Artificial Edge Fog) 🌟 -->
    <div class="sticky top-2 z-40 w-full" style="contain: style;">
      <OmniBar
        {words}
        {ciActivities}
        {listeningActivities}
        {grammarActivities}
        activeDate={date}
        colors={colors}
        goals={goals}
        onAddWord={handleAddWord}
        onUpdateWord={handleUpdateWord}
        onAddCI={handleAddCI}
        onUpdateCI={handleUpdateCI}
        onAddListening={handleAddListening}
        onUpdateListening={handleUpdateListening}
        onAddGrammar={handleAddGrammar}
        onUpdateGrammar={handleUpdateGrammar}
      />
    </div>

    <!-- 🌟 3. FILTER QUICK-JUMP CHIPS 🌟 -->
    <div class="flex items-center gap-1.5 overflow-x-auto pb-1 pt-1 no-scrollbar z-20">
      <button
        type="button"
        onclick={() => (activeFilter = 'all')}
        class="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-full text-xs font-bold transition-all duration-150 cursor-pointer border {activeFilter === 'all' 
          ? 'bg-[var(--bg-surface-elevated)] border-[var(--border-hover)] text-[var(--text-primary)] shadow-xs scale-105' 
          : 'bg-[var(--bg-surface)]/80 border-[var(--border-subtle)] text-[var(--text-muted)] hover:text-[var(--text-primary)]'}"
      >
        <Layers size={12} />
        <span>All ({totalItemsCount})</span>
      </button>

      <button
        type="button"
        onclick={() => (activeFilter = 'vocab')}
        class="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-full text-xs font-bold transition-all duration-150 cursor-pointer border"
        style="
          background-color: {activeFilter === 'vocab' ? `color-mix(in srgb, ${vocabColor} 18%, var(--bg-surface))` : 'var(--bg-surface)'};
          border-color: {activeFilter === 'vocab' ? vocabColor : 'var(--border-subtle)'};
          color: {activeFilter === 'vocab' ? vocabColor : 'var(--text-muted)'};
        "
      >
        <MessageSquare size={12} />
        <span>Vocab ({words.length})</span>
      </button>

      <button
        type="button"
        onclick={() => (activeFilter = 'ci')}
        class="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-full text-xs font-bold transition-all duration-150 cursor-pointer border"
        style="
          background-color: {activeFilter === 'ci' ? `color-mix(in srgb, ${ciColor} 18%, var(--bg-surface))` : 'var(--bg-surface)'};
          border-color: {activeFilter === 'ci' ? ciColor : 'var(--border-subtle)'};
          color: {activeFilter === 'ci' ? ciColor : 'var(--text-muted)'};
        "
      >
        <Play size={12} />
        <span>CI Video ({ciActivities.length})</span>
      </button>

      <button
        type="button"
        onclick={() => (activeFilter = 'listening')}
        class="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-full text-xs font-bold transition-all duration-150 cursor-pointer border"
        style="
          background-color: {activeFilter === 'listening' ? `color-mix(in srgb, ${listeningColor} 18%, var(--bg-surface))` : 'var(--bg-surface)'};
          border-color: {activeFilter === 'listening' ? listeningColor : 'var(--border-subtle)'};
          color: {activeFilter === 'listening' ? listeningColor : 'var(--text-muted)'};
        "
      >
        <Headphones size={12} />
        <span>Listening ({listeningActivities.length})</span>
      </button>

      <button
        type="button"
        onclick={() => (activeFilter = 'grammar')}
        class="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-full text-xs font-bold transition-all duration-150 cursor-pointer border"
        style="
          background-color: {activeFilter === 'grammar' ? `color-mix(in srgb, ${grammarColor} 18%, var(--bg-surface))` : 'var(--bg-surface)'};
          border-color: {activeFilter === 'grammar' ? grammarColor : 'var(--border-subtle)'};
          color: {activeFilter === 'grammar' ? grammarColor : 'var(--text-muted)'};
        "
      >
        <BookOpen size={12} />
        <span>Grammar ({grammarActivities.length})</span>
      </button>
    </div>

    <!-- 🌟 4. THE DYNAMIC BENTO STUDIO PAVILIONS 🌟 -->
    {#if totalItemsCount === 0}
      <div class="py-14 px-6 rounded-3xl border border-dashed border-[var(--border-card)] bg-[var(--bg-surface)]/30 backdrop-blur-md text-center space-y-3 max-w-md mx-auto shadow-xs">
        <div 
          class="w-10 h-10 rounded-2xl flex items-center justify-center mx-auto border shadow-xs"
          style="background-color: color-mix(in srgb, var(--day-accent) 15%, transparent); border-color: color-mix(in srgb, var(--day-accent) 35%, transparent); color: var(--day-accent);"
        >
          <Sparkles size={18} />
        </div>
        <div class="space-y-1">
          <p class="text-sm font-bold text-[var(--text-primary)]">
            Canvas ready for today
          </p>
          <p class="text-xs text-[var(--text-muted)] max-w-xs mx-auto leading-relaxed">
            Use the Omnibar above or hotkeys <kbd class="px-1.5 py-0.5 rounded bg-[var(--bg-base)] border border-[var(--border-subtle)] font-mono text-[10px]">1</kbd>–<kbd class="px-1.5 py-0.5 rounded bg-[var(--bg-base)] border border-[var(--border-subtle)] font-mono text-[10px]">4</kbd> to add vocabulary, CI, or listening immersion.
          </p>
        </div>
      </div>
    {:else}

      <div class="space-y-12 pt-2 relative z-10">
        
        <!-- ============================================== -->
        <!-- PAVILION 1: VOCABULARY AUTO-WALL               -->
        <!-- ============================================== -->
        {#if activeFilter === 'all' || activeFilter === 'vocab'}
          <section class="space-y-4 relative">
            <!-- 🌟 Lateral Flank Bleed (Left and Right Inward Lighting) 🌟 -->
            <div 
              class="pointer-events-none absolute -left-24 top-1/2 -translate-y-1/2 w-48 h-[120%] rounded-full blur-[90px] opacity-25 -z-10"
              style="background: radial-gradient(circle at 0% 50%, {vocabColor}, transparent 75%);"
            ></div>
            <div 
              class="pointer-events-none absolute -right-24 top-1/2 -translate-y-1/2 w-48 h-[120%] rounded-full blur-[90px] opacity-25 -z-10"
              style="background: radial-gradient(circle at 100% 50%, {vocabColor}, transparent 75%);"
            ></div>

            <!-- Matching Section Bridge Header -->
            <div class="flex items-center gap-3">
              <div class="flex-1 h-px bg-gradient-to-r from-transparent via-[var(--border-subtle)] to-transparent"></div>
              <div 
                class="flex items-center gap-2 px-3.5 py-1 rounded-full bg-[var(--bg-surface)] border shadow-xs"
                style="border-color: color-mix(in srgb, {vocabColor} 30%, var(--border-subtle));"
              >
                <MessageSquare size={12} style="color: {vocabColor};" />
                <span class="text-[10px] font-mono font-bold uppercase tracking-widest text-[var(--text-primary)]">
                  Vocabulary Gallery
                </span>
                <span class="text-[10px] font-mono font-bold px-1.5 rounded-full" style="background-color: color-mix(in srgb, {vocabColor} 15%, transparent); color: {vocabColor};">
                  {words.length}
                </span>
              </div>
              <div class="flex-1 h-px bg-gradient-to-r from-transparent via-[var(--border-subtle)] to-transparent"></div>
            </div>

            {#if words.length > 0}
              <div class="grid grid-cols-[repeat(auto-fill,minmax(280px,1fr))] gap-4 sm:gap-5 items-start">
                {#each words as word, i (`v_${word.id ?? word.word_index ?? i}`)}
                  <OmniCard
                    type="vocab"
                    lang={langCode}
                    {date}
                    item={word}
                    index={word.word_index ?? (i + 1)}
                  />
                {/each}
              </div>
            {:else}
              <div 
                class="w-full py-6 rounded-3xl border border-dashed text-center flex items-center justify-center gap-2 shadow-inner"
                style="border-color: color-mix(in srgb, {vocabColor} 30%, transparent); background-color: color-mix(in srgb, {vocabColor} 4%, transparent);"
              >
                <Plus size={14} style="color: {vocabColor};" />
                <span class="text-xs font-mono font-bold" style="color: {vocabColor};">
                  No words logged yet today — Target: {goals.vocab || 10}
                </span>
              </div>
            {/if}
          </section>
        {/if}

        <!-- ============================================== -->
        <!-- PAVILION 2: COMPREHENSIBLE INPUT (Dynamic Bento) -->
        <!-- ============================================== -->
        {#if activeFilter === 'all' || activeFilter === 'ci'}
          <section class="space-y-4 relative">
            <!-- 🌟 Lateral Flank Bleed 🌟 -->
            <div 
              class="pointer-events-none absolute -left-24 top-1/2 -translate-y-1/2 w-48 h-[120%] rounded-full blur-[90px] opacity-25 -z-10"
              style="background: radial-gradient(circle at 0% 50%, {ciColor}, transparent 75%);"
            ></div>
            <div 
              class="pointer-events-none absolute -right-24 top-1/2 -translate-y-1/2 w-48 h-[120%] rounded-full blur-[90px] opacity-25 -z-10"
              style="background: radial-gradient(circle at 100% 50%, {ciColor}, transparent 75%);"
            ></div>

            <div class="flex items-center gap-3">
              <div class="flex-1 h-px bg-gradient-to-r from-transparent via-[var(--border-subtle)] to-transparent"></div>
              <div 
                class="flex items-center gap-2 px-3.5 py-1 rounded-full bg-[var(--bg-surface)] border shadow-xs"
                style="border-color: color-mix(in srgb, {ciColor} 30%, var(--border-subtle));"
              >
                <Play size={12} style="color: {ciColor};" />
                <span class="text-[10px] font-mono font-bold uppercase tracking-widest text-[var(--text-primary)]">
                  Comprehensible Input
                </span>
                <span class="text-[10px] font-mono font-bold px-1.5 rounded-full" style="background-color: color-mix(in srgb, {ciColor} 15%, transparent); color: {ciColor};">
                  {ciActivities.length}
                </span>
              </div>
              <div class="flex-1 h-px bg-gradient-to-r from-transparent via-[var(--border-subtle)] to-transparent"></div>
            </div>

            {#if ciActivities.length > 0}
              <div class={ciActivities.length === 1 ? 'max-w-3xl mx-auto w-full' : 'grid grid-cols-1 lg:grid-cols-2 gap-5 items-start'}>
                {#each ciActivities as activity, i (`ci_${activity.id ?? activity.item_index ?? i}`)}
                  <OmniCard
                    type="ci"
                    lang={langCode}
                    {date}
                    item={activity}
                    index={activity.item_index ?? (i + 1)}
                  />
                {/each}
              </div>
            {:else}
              <div 
                class="w-full py-6 rounded-3xl border border-dashed text-center flex items-center justify-center gap-2 shadow-inner"
                style="border-color: color-mix(in srgb, {ciColor} 30%, transparent); background-color: color-mix(in srgb, {ciColor} 4%, transparent);"
              >
                <Plus size={14} style="color: {ciColor};" />
                <span class="text-xs font-mono font-bold" style="color: {ciColor};">
                  No CI videos recorded today — Target: {goals.ci || 1}
                </span>
              </div>
            {/if}
          </section>
        {/if}

        <!-- ============================================== -->
        <!-- PAVILION 3: LISTENING IMMERSION (Dynamic Bento) -->
        <!-- ============================================== -->
        {#if activeFilter === 'all' || activeFilter === 'listening'}
          <section class="space-y-4 relative">
            <!-- 🌟 Lateral Flank Bleed 🌟 -->
            <div 
              class="pointer-events-none absolute -left-24 top-1/2 -translate-y-1/2 w-48 h-[120%] rounded-full blur-[90px] opacity-25 -z-10"
              style="background: radial-gradient(circle at 0% 50%, {listeningColor}, transparent 75%);"
            ></div>
            <div 
              class="pointer-events-none absolute -right-24 top-1/2 -translate-y-1/2 w-48 h-[120%] rounded-full blur-[90px] opacity-25 -z-10"
              style="background: radial-gradient(circle at 100% 50%, {listeningColor}, transparent 75%);"
            ></div>

            <div class="flex items-center gap-3">
              <div class="flex-1 h-px bg-gradient-to-r from-transparent via-[var(--border-subtle)] to-transparent"></div>
              <div 
                class="flex items-center gap-2 px-3.5 py-1 rounded-full bg-[var(--bg-surface)] border shadow-xs"
                style="border-color: color-mix(in srgb, {listeningColor} 30%, var(--border-subtle));"
              >
                <Headphones size={12} style="color: {listeningColor};" />
                <span class="text-[10px] font-mono font-bold uppercase tracking-widest text-[var(--text-primary)]">
                  Listening Immersion
                </span>
                <span class="text-[10px] font-mono font-bold px-1.5 rounded-full" style="background-color: color-mix(in srgb, {listeningColor} 15%, transparent); color: {listeningColor};">
                  {listeningActivities.length}
                </span>
              </div>
              <div class="flex-1 h-px bg-gradient-to-r from-transparent via-[var(--border-subtle)] to-transparent"></div>
            </div>

            {#if listeningActivities.length > 0}
              <div class={listeningActivities.length === 1 ? 'max-w-3xl mx-auto w-full' : 'grid grid-cols-1 lg:grid-cols-2 gap-5 items-start'}>
                {#each listeningActivities as activity, i (`li_${activity.id ?? activity.item_index ?? i}`)}
                  <OmniCard
                    type="listening"
                    lang={langCode}
                    {date}
                    item={activity}
                    index={activity.item_index ?? (i + 1)}
                  />
                {/each}
              </div>
            {:else}
              <div 
                class="w-full py-6 rounded-3xl border border-dashed text-center flex items-center justify-center gap-2 shadow-inner"
                style="border-color: color-mix(in srgb, {listeningColor} 30%, transparent); background-color: color-mix(in srgb, {listeningColor} 4%, transparent);"
              >
                <Plus size={14} style="color: {listeningColor};" />
                <span class="text-xs font-mono font-bold" style="color: {listeningColor};">
                  No listening sessions logged — Target: {goals.listening_minutes || 30}m
                </span>
              </div>
            {/if}
          </section>
        {/if}

        <!-- ============================================== -->
        <!-- PAVILION 4: GRAMMAR & PATTERNS                 -->
        <!-- ============================================== -->
        {#if activeFilter === 'all' || activeFilter === 'grammar'}
          <section class="space-y-4 relative">
            <!-- 🌟 Lateral Flank Bleed 🌟 -->
            <div 
              class="pointer-events-none absolute -left-24 top-1/2 -translate-y-1/2 w-48 h-[120%] rounded-full blur-[90px] opacity-25 -z-10"
              style="background: radial-gradient(circle at 0% 50%, {grammarColor}, transparent 75%);"
            ></div>
            <div 
              class="pointer-events-none absolute -right-24 top-1/2 -translate-y-1/2 w-48 h-[120%] rounded-full blur-[90px] opacity-25 -z-10"
              style="background: radial-gradient(circle at 100% 50%, {grammarColor}, transparent 75%);"
            ></div>

            <div class="flex items-center gap-3">
              <div class="flex-1 h-px bg-gradient-to-r from-transparent via-[var(--border-subtle)] to-transparent"></div>
              <div 
                class="flex items-center gap-2 px-3.5 py-1 rounded-full bg-[var(--bg-surface)] border shadow-xs"
                style="border-color: color-mix(in srgb, {grammarColor} 30%, var(--border-subtle));"
              >
                <BookOpen size={12} style="color: {grammarColor};" />
                <span class="text-[10px] font-mono font-bold uppercase tracking-widest text-[var(--text-primary)]">
                  Grammar & Patterns
                </span>
                <span class="text-[10px] font-mono font-bold px-1.5 rounded-full" style="background-color: color-mix(in srgb, {grammarColor} 15%, transparent); color: {grammarColor};">
                  {grammarActivities.length}
                </span>
              </div>
              <div class="flex-1 h-px bg-gradient-to-r from-transparent via-[var(--border-subtle)] to-transparent"></div>
            </div>

            {#if grammarActivities.length > 0}
              <div class="grid grid-cols-1 md:grid-cols-2 gap-4 sm:gap-5 items-start">
                {#each grammarActivities as activity, i (`gr_${activity.id ?? activity.item_index ?? i}`)}
                  <OmniCard
                    type="grammar"
                    lang={langCode}
                    {date}
                    item={activity}
                    index={activity.item_index ?? (i + 1)}
                  />
                {/each}
              </div>
            {:else}
              <div 
                class="w-full py-6 rounded-3xl border border-dashed text-center flex items-center justify-center gap-2 shadow-inner"
                style="border-color: color-mix(in srgb, {grammarColor} 30%, transparent); background-color: color-mix(in srgb, {grammarColor} 4%, transparent);"
              >
                <Plus size={14} style="color: {grammarColor};" />
                <span class="text-xs font-mono font-bold" style="color: {grammarColor};">
                  No grammar patterns logged — Target: {goals.grammar || 3}
                </span>
              </div>
            {/if}
          </section>
        {/if}

      </div>

    {/if}

    <!-- 🌟 5. BOTTOM SRS REVISION BAR (Clean: Zero Artificial Edge Fog) 🌟 -->
    <div class="sticky bottom-3 z-40 w-full pt-4 pointer-events-none">
      <div class="pointer-events-auto w-full">
        <SRSBar {session} activeDate={date} onReview={handleSRSReview} />
      </div>
    </div>

  {/if}

</div>