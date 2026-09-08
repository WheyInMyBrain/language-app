<!-- frontend/src/components/VocabSearchStream.svelte -->
<script>
  import { vocabIndexStore } from '../lib/stores/vocabIndex.svelte.js';
  import { activeLanguage } from '../lib/stores/activeLanguage.svelte.js';
  import { tokenizePhonetics } from '../lib/formatters/phonetics.js';
  import ColoredText from './ColoredText.svelte';
  import MediaStage from './MediaStage.svelte';

  let { onSelectDate } = $props();

  let query = $state('');
  let searchInput = $state(null);
  let scrollTrack = $state(null);
  let scrollLeft = $state(0);
  let containerWidth = $state(380);

  let filteredEntries = $derived(vocabIndexStore.search(query));
  let langConfig = $derived(activeLanguage.current);

  // Constants for horizontal card geometry
  const CARD_WIDTH = 130;
  const CARD_GAP = 10;
  const ITEM_STRIDE = CARD_WIDTH + CARD_GAP; // 140px stride
  const BUFFER_COUNT = 2; // Over-render buffer

  let totalWidth = $derived(
    filteredEntries.length > 0 ? filteredEntries.length * ITEM_STRIDE - CARD_GAP : 0
  );

  let startIndex = $derived(
    Math.max(0, Math.floor(scrollLeft / ITEM_STRIDE) - BUFFER_COUNT)
  );

  let endIndex = $derived(
    Math.min(
      filteredEntries.length,
      Math.ceil((scrollLeft + containerWidth) / ITEM_STRIDE) + BUFFER_COUNT
    )
  );

  let visibleEntries = $derived.by(() => {
    return filteredEntries.slice(startIndex, endIndex).map((item, idx) => ({
      ...item,
      virtualIndex: startIndex + idx,
      offsetLeft: (startIndex + idx) * ITEM_STRIDE
    }));
  });

  function handleScroll(e) {
    scrollLeft = e.currentTarget.scrollLeft;
  }

  function clearSearch() {
    query = '';
    if (scrollTrack) scrollTrack.scrollLeft = 0;
    if (searchInput) searchInput.focus();
  }
</script>

<div class="w-full space-y-3 pt-2">
  <!-- Search Input Bar -->
  <div class="relative flex items-center gap-2 px-3.5 py-2.5 rounded-2xl border border-[var(--border-card)] bg-[var(--bg-surface)] shadow-xs transition-colors focus-within:border-[var(--border-hover)]">
    <span class="text-sm opacity-60">🔍</span>

    <input
      bind:this={searchInput}
      bind:value={query}
      type="text"
      placeholder="Search Hanzi or Pinyin..."
      class="w-full bg-transparent border-none outline-none text-xs sm:text-sm font-semibold text-[var(--text-primary)] placeholder-[var(--text-muted)]"
    />

    <span class="text-[10px] font-bold font-mono px-2 py-0.5 rounded-md bg-[var(--badge-bg)] text-[var(--text-muted)] border border-[var(--border-card)] shrink-0">
      {filteredEntries.length}
    </span>

    {#if query}
      <button
        onclick={clearSearch}
        aria-label="Clear search"
        class="text-xs text-[var(--text-muted)] hover:text-rose-500 active:scale-95 px-1 cursor-pointer"
      >
        ✖
      </button>
    {/if}
  </div>

  <!-- Virtualized Scroller Track -->
  {#if filteredEntries.length === 0}
    <div class="py-8 px-4 text-center text-xs text-[var(--text-muted)] italic rounded-2xl border border-dashed border-[var(--border-card)]">
      {query ? `No cards match "${query}"` : 'No vocabulary entries logged yet.'}
    </div>
  {:else}
    <div 
      bind:this={scrollTrack}
      bind:clientWidth={containerWidth}
      onscroll={handleScroll}
      class="relative w-full overflow-x-auto overscroll-x-contain pb-2 pt-1 select-none [contain:paint_layout] h-[190px] touch-pan-x"
    >
      <!-- Horizontal Phantom Track Anchor -->
      <div class="relative h-full" style="width: {totalWidth}px; min-width: 100%;">
        {#each visibleEntries as item (item.word_id || item.native_script + item.date)}
          {@const tokens = tokenizePhonetics(item.native_script, item.pronunciation, langConfig)}
          
          <!-- Outer anchor handles layout coordinate without CSS animation collisions -->
          <div
            style="left: {item.offsetLeft}px;"
            class="absolute top-0 w-[130px] h-[178px]"
          >
            <!-- Inner button safely handles scale & hover without shifting position -->
            <button
              onclick={() => onSelectDate(item.date)}
              class="w-full h-full flex flex-col items-center justify-between p-2.5 rounded-2xl border border-[var(--border-card)] bg-[var(--bg-surface)] shadow-xs transition-transform duration-75 active:scale-[0.96] active:bg-[var(--bg-surface-active)] text-center cursor-pointer outline-none select-none"
            >
              <!-- Media Container -->
              <div class="w-full mb-1.5 pointer-events-none">
                <MediaStage 
                  src={item.link} 
                  alt={item.native_script} 
                  fallbackChar={item.native_script}
                  observerRoot={scrollTrack}
                />
              </div>

              <!-- Native Script -->
              <div class="w-full text-base font-black truncate leading-tight tracking-tight">
                <ColoredText tokens={tokens.primaryTokens} fallbackClass="text-[var(--text-primary)]" />
              </div>

              <!-- Phonetics -->
              <div class="w-full text-[11px] font-semibold truncate leading-tight mt-0.5 pb-0.5">
                <ColoredText tokens={tokens.secondaryTokens} fallbackClass="text-[var(--text-muted)]" />
              </div>
            </button>
          </div>
        {/each}
      </div>
    </div>
  {/if}
</div>