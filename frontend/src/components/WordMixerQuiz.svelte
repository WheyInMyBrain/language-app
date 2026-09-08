<!-- frontend/src/components/WordMixerQuiz.svelte -->
<script>
  import { vocabIndexStore } from '../lib/stores/vocabIndex.svelte.js';
  import { activeLanguage } from '../lib/stores/activeLanguage.svelte.js';
  import { tokenizePhonetics } from '../lib/formatters/phonetics.js';
  import { playTTS } from '../lib/tts.js';
  import MediaStage from './MediaStage.svelte';
  import ColoredText from './ColoredText.svelte';

  let { 
    langCode,
    minCount = 2,
    maxCount = 10,
    defaultCount = 2,
    onSelectDate = null
  } = $props();

  // Initialize without stale-capture warnings
  let selectedCount = $state(2);
  let showText = $state(true);
  let mixedWords = $state([]);
  let scrollTrack = $state(null);

  // Sync prop changes without triggering state_referenced_locally
  $effect(() => {
    selectedCount = defaultCount;
  });

  let langConfig = $derived(activeLanguage.current);
  let pool = $derived(vocabIndexStore.entries || []);

  // Fisher-Yates random selection
  function pickRandomWords(sourceList, count) {
    if (!sourceList || sourceList.length === 0) return [];
    const poolCopy = [...sourceList];
    const n = Math.min(count, poolCopy.length);
    const result = [];

    for (let i = 0; i < n; i++) {
      const randIdx = Math.floor(Math.random() * poolCopy.length);
      result.push(poolCopy[randIdx]);
      poolCopy.splice(randIdx, 1);
    }
    return result;
  }

  function forgeNewCombination() {
    mixedWords = pickRandomWords(pool, selectedCount);
    if (scrollTrack) {
      scrollTrack.scrollTo({ left: 0, behavior: 'smooth' });
    }
  }

  function handleSelectCount(num) {
    selectedCount = num;
    forgeNewCombination();
  }

  // Initial combination once dictionary loads
  $effect(() => {
    if (pool.length > 0 && mixedWords.length === 0) {
      forgeNewCombination();
    }
  });

  function handlePronounce(e, native) {
    e.stopPropagation();
    if (native) {
      playTTS(native, langCode || langConfig?.code || 'zh-CN');
    }
  }
</script>

<div class="word-mixer-main-card relative flex flex-col gap-3.5 p-4 sm:p-5 rounded-2xl bg-[var(--bg-surface)] border border-[var(--border-card)] shadow-xs select-none overflow-hidden">
  <!-- Pink-Purple-Blue Accent Stripe -->
  <div class="absolute top-0 left-0 right-0 h-[3px] bg-gradient-to-r from-pink-500 via-purple-500 to-blue-500 opacity-90"></div>

  <!-- Header & Controls -->
  <div class="flex items-center justify-between flex-wrap gap-2 pt-0.5">
    <div class="flex items-center gap-2">
      <span class="text-base">🎲</span>
      <span class="text-xs font-extrabold tracking-wide text-[var(--text-primary)]">
        Word Mixer & Sentence Forge
      </span>
    </div>

    <div class="flex items-center gap-1.5 flex-wrap ml-auto">
      <!-- Full Card vs Image Only Toggle -->
      <button
        type="button"
        onclick={() => (showText = !showText)}
        class="px-2.5 py-1 text-[11px] font-extrabold rounded-lg border border-[var(--border-card)] bg-[var(--bg-base)] text-[var(--text-primary)] hover:bg-[var(--bg-surface-active)] transition-all cursor-pointer"
      >
        {showText ? '📝 Full Card' : '🖼️ Image Only'}
      </button>

      <!-- Word Count Picker (2 - 10) -->
      <div class="flex items-center gap-1 p-1 rounded-xl bg-[var(--bg-base)] border border-[var(--border-card)] overflow-x-auto max-w-[210px] no-scrollbar">
        {#each Array.from({ length: maxCount - minCount + 1 }, (_, i) => minCount + i) as num}
          {@const isSelected = selectedCount === num}
          <button
            type="button"
            onclick={() => handleSelectCount(num)}
            class="min-w-6 h-6 px-1.5 rounded-md text-[11px] font-mono font-bold flex items-center justify-center shrink-0 transition-all cursor-pointer {isSelected 
              ? 'bg-gradient-to-r from-pink-500 to-purple-500 text-white shadow-xs font-black' 
              : 'text-[var(--text-muted)] hover:text-[var(--text-primary)]'}"
          >
            {num}
          </button>
        {/each}
      </div>
    </div>
  </div>

  <!-- Prompt Instruction -->
  <div class="text-[11px] text-[var(--text-muted)] leading-tight -mt-1">
    Construct a cohesive sentence or dialogue integrating all <strong class="text-[var(--text-primary)] font-mono font-bold">{selectedCount}</strong> selected words below:
  </div>

  <!-- Cards Horizontal Stage Track -->
  {#if pool.length === 0}
    <div class="py-10 text-center text-xs text-[var(--text-muted)] italic border border-dashed border-[var(--border-card)] rounded-xl">
      ⚠️ No vocabulary items available yet. Once logs load, words will appear here.
    </div>
  {:else}
    <div
      bind:this={scrollTrack}
      class="flex items-center gap-2.5 w-full overflow-x-auto overscroll-x-contain py-2 px-1 touch-pan-x"
    >
      {#each mixedWords as item, index (item.word_id || `${item.native_script}-${index}`)}
        {@const tokens = tokenizePhonetics(item.native_script, item.pronunciation, langConfig)}

        <!-- Word Card Container -->
        <div
          class="flex flex-col items-center gap-2 p-2.5 rounded-2xl bg-[var(--bg-base)] border border-[var(--border-card)] shadow-xs shrink-0 select-none transition-all duration-150 hover:-translate-y-1 hover:border-pink-500/50 hover:shadow-md"
          style="width: {showText ? '160px' : '140px'};"
        >
          <!-- MediaStage Box -->
          <div class="w-full h-28 flex items-center justify-center rounded-xl overflow-hidden bg-[var(--bg-surface)] border border-[var(--border-card)]">
            <MediaStage
              src={item.link || ''}
              alt={item.native_script}
              fallbackChar={item.native_script}
              observerRoot={scrollTrack}
            />
          </div>

          <!-- Text Section (Hidden in Image Only mode) -->
          {#if showText}
            <div class="w-full flex flex-col items-center text-center gap-0.5 pt-0.5">
              <div class="w-full text-base font-black truncate leading-tight tracking-tight">
                <ColoredText tokens={tokens.primaryTokens} fallbackClass="text-[var(--text-primary)]" />
              </div>
              <div class="w-full text-[11px] font-semibold truncate leading-tight">
                <ColoredText tokens={tokens.secondaryTokens} fallbackClass="text-[var(--text-muted)]" />
              </div>
            </div>
          {/if}

          <!-- Action Bar: Date Navigation & Audio -->
          <div class="w-full flex items-center justify-between pt-1.5 mt-auto border-t border-[var(--border-card)]/60 text-[10px]">
            {#if item.date && onSelectDate}
              <button
                type="button"
                onclick={() => onSelectDate(item.date)}
                class="font-mono text-[var(--text-muted)] hover:text-[var(--text-primary)] cursor-pointer"
                title="View daily log"
              >
                📅 {item.date.slice(5)}
              </button>
            {:else}
              <span class="font-mono text-[var(--text-muted)] opacity-60">#{index + 1}</span>
            {/if}

            <button
              type="button"
              onclick={(e) => handlePronounce(e, item.native_script)}
              class="w-5 h-5 flex items-center justify-center rounded-md hover:bg-[var(--bg-surface)] text-[var(--text-muted)] hover:text-[var(--text-primary)] active:scale-90 cursor-pointer"
              title="Play Pronunciation"
            >
              🔊
            </button>
          </div>
        </div>

        <!-- Connector '+' Sign Between Cards -->
        {#if index < mixedWords.length - 1}
          <div class="flex items-center justify-center w-6 h-6 rounded-full bg-pink-500/15 border border-pink-500/35 text-pink-500 font-black text-xs shrink-0 select-none pointer-events-none">
            +
          </div>
        {/if}
      {/each}
    </div>
  {/if}

  <!-- Bottom Bar: Pool Count & Roll Combination Action -->
  <div class="flex items-center justify-between flex-wrap gap-2 pt-1 border-t border-[var(--border-card)]">
    <span class="text-[11px] font-mono font-bold text-[var(--text-muted)]">
      Vault Pool: {pool.length} unique words available
    </span>

    <button
      type="button"
      onclick={forgeNewCombination}
      disabled={pool.length === 0}
      class="px-4 py-1.5 rounded-xl font-extrabold text-xs text-white bg-gradient-to-r from-pink-500 to-purple-600 hover:opacity-95 active:scale-95 transition-all shadow-xs cursor-pointer border-none disabled:opacity-50"
    >
      🎲 Forge New Combination
    </button>
  </div>
</div>