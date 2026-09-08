<script>
  import { activeLanguage } from '../lib/stores/activeLanguage.svelte.js';
  import { vocabIndexStore } from '../lib/stores/vocabIndex.svelte.js';

  let {
    words = [],
    activeDate = '',
    onAddWord,
    onUpdateWord
  } = $props();

  let linkInput = $state('');
  let nativeInput = $state('');
  let pronInput = $state('');

  let isEditMode = $state(false);
  let isPronManuallyEdited = $state(false);
  let selectedIndex = $state(1);
  let statusMessage = $state('');
  let isSubmitting = $state(false);

  let linkEl = $state(null);
  let nativeEl = $state(null);
  let pronEl = $state(null);

  let goals = $derived(activeLanguage.goals);
  let colors = $derived(activeLanguage.colors);
  let vocabGoal = $derived(goals.vocab || 10);
  let colorPrimary = $derived(colors.vocab?.dark_primary || '#2e7d32');
  let colorSecondary = $derived(colors.vocab?.light_primary || '#4caf50');

  let count = $derived(words.length);
  let pct = $derived(vocabGoal > 0 ? Math.min(100, Math.round((count / vocabGoal) * 100)) : 0);
  let isCompleted = $derived(count >= vocabGoal && vocabGoal > 0);

  let duplicateMatches = $derived.by(() => {
    const query = nativeInput.trim();
    if (!query || query.length === 0) return [];

    return vocabIndexStore.entries.filter((entry) => {
      if (isEditMode) {
        const currentEditWord = words.find((w) => (w.word_index ?? w.id) === selectedIndex);
        if (currentEditWord && currentEditWord.native_script === query && entry.date === activeDate) {
          return false;
        }
      }
      return entry.native_script === query && entry.date !== activeDate;
    });
  });

  // Auto-predict pronunciation when typing native script
  function handleNativeInput(e) {
    nativeInput = e.target.value;

    // 1. If native script is emptied, clear pronunciation and reset manual flag
    if (!nativeInput.trim()) {
      pronInput = '';
      isPronManuallyEdited = false;
      return;
    }

    // 2. Predict pronunciation if not manually locked
    if (!isPronManuallyEdited) {
      pronInput = vocabIndexStore.predictPronunciation(nativeInput) || '';
    }
  }

  function handlePronManualInput(e) {
    pronInput = e.target.value;
    isPronManuallyEdited = true;
  }

  function resetToAutoPronunciation() {
    isPronManuallyEdited = false;
    pronInput = vocabIndexStore.predictPronunciation(nativeInput);
  }

  function selectWordForEdit(wordIdx) {
    selectedIndex = wordIdx;
    const target = words.find((w) => (w.word_index ?? w.id) === wordIdx);
    if (target) {
      linkInput = target.link || '';
      nativeInput = target.native_script || '';
      pronInput = target.pronunciation || '';
      isPronManuallyEdited = true; // Retain saved pronunciation during edit
    }
  }

  function toggleMode() {
    isEditMode = !isEditMode;
    if (isEditMode && words.length > 0) {
      selectWordForEdit(words[0].word_index ?? words[0].id ?? 1);
    } else {
      linkInput = '';
      nativeInput = '';
      pronInput = '';
      isPronManuallyEdited = false;
    }
  }

  async function handleSubmit() {
    const cleanNative = nativeInput.trim();
    const cleanPron = pronInput.trim();
    const cleanLink = linkInput.trim();

    if (!cleanNative && !cleanPron && !cleanLink) {
      statusMessage = '⚠️ Enter word details';
      setTimeout(() => (statusMessage = ''), 2000);
      return;
    }

    isSubmitting = true;

    try {
      const payload = {
        native_script: cleanNative,
        pronunciation: cleanPron,
        link: cleanLink || null
      };

      if (isEditMode) {
        if (onUpdateWord) await onUpdateWord(selectedIndex, payload);
        statusMessage = `🔄 Updated #${selectedIndex}!`;
      } else {
        if (onAddWord) await onAddWord(payload);
        statusMessage = `✅ Added #${words.length + 1}!`;

        linkInput = '';
        nativeInput = '';
        pronInput = '';
        isPronManuallyEdited = false;
        linkEl?.focus();
      }
    } catch (err) {
      console.error('Failed to submit word:', err);
      statusMessage = '❌ Error saving';
    } finally {
      isSubmitting = false;
      setTimeout(() => (statusMessage = ''), 2500);
    }
  }

  function handleKeydown(e, nextEl) {
    if (e.key === 'Enter') {
      e.preventDefault();
      if (nextEl) {
        nextEl.focus();
      } else {
        handleSubmit();
      }
    }
  }
</script>

<div class="relative flex flex-col gap-3.5 p-4 rounded-2xl bg-[var(--bg-surface)] border border-[var(--border-card)] shadow-xs overflow-hidden select-none">
  <div
    class="absolute top-0 left-0 right-0 h-[3px] opacity-90"
    style="background: linear-gradient(90deg, {colorPrimary}, {colorSecondary});"
  ></div>

  {#if isCompleted && !isEditMode}
    <div class="flex flex-col items-center justify-center text-center py-2 space-y-2">
      <div
        class="inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-[11px] font-extrabold uppercase tracking-wider border"
        style="background: {colorPrimary}18; color: {colorSecondary}; border-color: {colorSecondary}40;"
      >
        <span>✨</span>
        <span>Daily Target Hit</span>
      </div>

      <div class="text-base font-black text-[var(--text-primary)]">
        🎉 Vocabulary Goal Completed!
      </div>

      <p class="text-xs text-[var(--text-muted)] max-w-sm">
        You logged {count} / {vocabGoal} words today. Great job!
      </p>

      <div class="flex items-center justify-between w-full pt-2">
        <span
          class="text-xs font-mono font-bold px-2.5 py-1 rounded-lg border border-[var(--border-card)] bg-[var(--bg-base)]"
          style="color: {colorSecondary};"
        >
          🔥 {count} ({pct}%)
        </span>

        <div class="flex items-center gap-2">
          <button
            onclick={toggleMode}
            class="px-3 py-1.5 rounded-xl text-xs font-bold bg-[var(--bg-base)] text-[var(--text-primary)] border border-[var(--border-card)] hover:border-[var(--border-hover)] transition-all cursor-pointer"
          >
            ✏️ Edit Items
          </button>
          <button
            onclick={() => (isCompleted = false)}
            class="px-3 py-1.5 rounded-xl text-xs font-bold text-[var(--text-muted)] hover:text-[var(--text-primary)] border border-transparent hover:border-[var(--border-card)] transition-all cursor-pointer"
          >
            ➕ Add More
          </button>
        </div>
      </div>
    </div>
  {:else}
    <div class="grid grid-cols-2 gap-2 w-full pt-1">
      <div class="col-span-2 relative">
        <input
          bind:this={linkEl}
          bind:value={linkInput}
          onkeydown={(e) => handleKeydown(e, nativeEl)}
          type="text"
          placeholder="1. Paste Image, GIF, Video link..."
          class="w-full px-3 py-2 rounded-xl text-xs font-semibold bg-[var(--bg-base)] border border-[var(--border-card)] text-[var(--text-primary)] placeholder-[var(--text-muted)] outline-none focus:border-[var(--border-hover)] transition-colors"
        />
      </div>

      <div class="relative flex items-center">
        <input
          bind:this={nativeEl}
          value={nativeInput}
          oninput={handleNativeInput}
          onkeydown={(e) => handleKeydown(e, pronEl)}
          type="text"
          placeholder="2. Native script (汉语)..."
          class="w-full px-3 py-2 rounded-xl text-xs font-semibold bg-[var(--bg-base)] border border-[var(--border-card)] text-[var(--text-primary)] placeholder-[var(--text-muted)] outline-none focus:border-[var(--border-hover)] transition-colors"
        />

        {#if duplicateMatches.length > 0}
          <span
            title="Logged on {duplicateMatches.map((m) => m.date).join(', ')}"
            class="absolute right-2 text-[9px] font-bold font-mono px-1.5 py-0.5 rounded bg-amber-500/15 text-amber-500 border border-amber-500/30 whitespace-nowrap pointer-events-none"
          >
            ⚠️ {duplicateMatches.length === 1 ? duplicateMatches[0].date : `${duplicateMatches.length}x`}
          </span>
        {/if}
      </div>

      <div class="relative flex items-center">
        <input
          bind:this={pronEl}
          value={pronInput}
          oninput={handlePronManualInput}
          onkeydown={(e) => handleKeydown(e, null)}
          type="text"
          placeholder="3. Pronunciation (hàn yǔ)..."
          class="w-full px-3 py-2 pr-7 rounded-xl text-xs font-semibold bg-[var(--bg-base)] border border-[var(--border-card)] text-[var(--text-primary)] placeholder-[var(--text-muted)] outline-none focus:border-[var(--border-hover)] transition-colors font-mono"
        />

        {#if isPronManuallyEdited && nativeInput}
          <button
            type="button"
            onclick={resetToAutoPronunciation}
            title="Reset to auto-predicted pronunciation"
            class="absolute right-1.5 p-1 rounded-md text-[10px] text-[var(--text-muted)] hover:text-[var(--text-primary)] bg-[var(--bg-surface)] hover:bg-[var(--bg-surface-active)] transition-colors cursor-pointer border border-[var(--border-card)]"
          >
            ↺
          </button>
        {/if}
      </div>
    </div>

    <div class="flex items-center justify-between gap-2 flex-wrap pt-0.5">
      <div class="flex items-center gap-2">
        <button
          onclick={handleSubmit}
          disabled={isSubmitting}
          class="px-4 py-1.5 rounded-xl text-xs font-bold text-white shadow-xs active:scale-95 transition-all cursor-pointer disabled:opacity-50"
          style="background: linear-gradient(135deg, {colorPrimary}, {colorSecondary});"
        >
          {isEditMode ? `🔄 Update #${selectedIndex}` : '➕ Add Word'}
        </button>

        {#if words.length > 0}
          <button
            onclick={toggleMode}
            class="px-3 py-1.5 rounded-xl text-xs font-semibold bg-[var(--bg-base)] text-[var(--text-muted)] hover:text-[var(--text-primary)] border border-[var(--border-card)] active:scale-95 transition-all cursor-pointer"
          >
            {isEditMode ? '➕ Add Mode' : '✏️ Edit'}
          </button>
        {/if}

        {#if statusMessage}
          <span class="text-xs font-bold" style="color: {colorSecondary};">
            {statusMessage}
          </span>
        {/if}
      </div>

      <div class="flex items-center gap-2 ml-auto">
        {#if !isEditMode}
          <div class="flex items-center gap-2.5 px-3 py-1 rounded-xl bg-[var(--bg-base)] border border-[var(--border-card)]">
            <span class="text-xs font-bold font-mono">
              <span style="color: {colorSecondary};">{count}</span> / {vocabGoal}
            </span>

            <div class="w-16 h-1.5 rounded-full bg-[var(--bg-surface)] border border-[var(--border-card)] overflow-hidden">
              <div
                class="h-full rounded-full transition-all duration-300"
                style="width: {pct}%; background: linear-gradient(90deg, {colorPrimary}, {colorSecondary});"
              ></div>
            </div>

            <span class="text-[10px] font-bold font-mono text-[var(--text-muted)] min-w-[28px] text-right">
              {pct}%
            </span>
          </div>
        {:else}
          <div class="flex items-center gap-1.5 overflow-x-auto max-w-[200px] p-1 rounded-xl bg-[var(--bg-base)] border border-[var(--border-card)]">
            {#each words as item (item.word_index ?? item.id)}
              {@const idx = item.word_index ?? item.id}
              {@const isSelected = idx === selectedIndex}
              <button
                onclick={() => selectWordForEdit(idx)}
                class="px-2 py-0.5 rounded-lg text-[10px] font-bold font-mono transition-colors cursor-pointer {isSelected
                  ? 'text-white shadow-xs'
                  : 'text-[var(--text-muted)] hover:text-[var(--text-primary)]'}"
                style={isSelected ? `background-color: ${colorPrimary};` : ''}
              >
                #{idx}
              </button>
            {/each}
          </div>
        {/if}
      </div>
    </div>
  {/if}
</div>