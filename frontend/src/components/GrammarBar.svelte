<!-- frontend/src/components/GrammarBar.svelte -->
<script>
  import { activeLanguage } from '../lib/stores/activeLanguage.svelte.js';

  let {
    grammarActivities = [], // [{ item_index, link, metadata: { title, pronunciation, structure, meaning } }]
    activeDate = '',
    onAddGrammar,           // async (payload) => void
    onUpdateGrammar         // async (itemIndex, payload) => void
  } = $props();

  let titleInput = $state('');
  let pronInput = $state('');
  let structureInput = $state('');
  let meaningInput = $state('');
  let linkInput = $state('');

  let isEditMode = $state(false);
  let selectedIndex = $state(1);
  let statusMessage = $state('');
  let isSubmitting = $state(false);

  let titleEl = $state(null);
  let pronEl = $state(null);
  let structureEl = $state(null);
  let meaningEl = $state(null);
  let linkEl = $state(null);

  // Configuration
  let goals = $derived(activeLanguage.goals);
  let colors = $derived(activeLanguage.colors);
  let grammarGoal = $derived(goals.grammar || 1);
  let colorPrimary = $derived(colors.grammar?.dark_primary || '#01579b');
  let colorSecondary = $derived(colors.grammar?.light_primary || '#0288d1');

  // Metrics
  let count = $derived(grammarActivities.length);
  let pct = $derived(grammarGoal > 0 ? Math.min(100, Math.round((count / grammarGoal) * 100)) : 0);
  let isCompleted = $derived(count >= grammarGoal && grammarGoal > 0);

  function selectItemForEdit(itemIdx) {
    selectedIndex = itemIdx;
    const target = grammarActivities.find((a) => a.item_index === itemIdx);
    if (target) {
      const meta = target.metadata || {};
      titleInput = meta.title || '';
      pronInput = meta.pronunciation || '';
      structureInput = meta.structure || '';
      meaningInput = meta.meaning || '';
      linkInput = target.link || '';
    }
  }

  function toggleMode() {
    isEditMode = !isEditMode;
    if (isEditMode && grammarActivities.length > 0) {
      selectItemForEdit(grammarActivities[0].item_index || 1);
    } else {
      titleInput = '';
      pronInput = '';
      structureInput = '';
      meaningInput = '';
      linkInput = '';
    }
  }

  async function handleSubmit() {
    const cleanTitle = titleInput.trim();
    const cleanLink = linkInput.trim();

    if (!cleanTitle && !cleanLink) {
      statusMessage = '⚠️ Enter a grammar title or diagram';
      setTimeout(() => (statusMessage = ''), 2000);
      return;
    }

    isSubmitting = true;

    try {
      const payload = {
        title: cleanTitle,
        pronunciation: pronInput.trim(),
        structure: structureInput.trim(),
        meaning: meaningInput.trim(),
        link: cleanLink || null
      };

      if (isEditMode) {
        if (onUpdateGrammar) await onUpdateGrammar(selectedIndex, payload);
        statusMessage = `🔄 Updated #${selectedIndex}!`;
      } else {
        if (onAddGrammar) await onAddGrammar(payload);
        statusMessage = `✅ Added #${grammarActivities.length + 1}!`;

        titleInput = '';
        pronInput = '';
        structureInput = '';
        meaningInput = '';
        linkInput = '';
        titleEl?.focus();
      }
    } catch (err) {
      console.error('Failed to save grammar item:', err);
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
  <!-- Accent Top Line -->
  <div
    class="absolute top-0 left-0 right-0 h-[3px] opacity-90"
    style="background: linear-gradient(90deg, {colorPrimary}, {colorSecondary});"
  ></div>

  {#if isCompleted && !isEditMode}
    <!-- Target Met Celebration Card -->
    <div class="flex flex-col items-center justify-center text-center py-2 space-y-2">
      <div
        class="inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-[11px] font-extrabold uppercase tracking-wider border"
        style="background: {colorPrimary}18; color: {colorSecondary}; border-color: {colorSecondary}40;"
      >
        <span>✨</span>
        <span>Daily Target Hit</span>
      </div>

      <div class="text-base font-black text-[var(--text-primary)]">
        🎉 Grammar Practice Completed!
      </div>

      <p class="text-xs text-[var(--text-muted)] max-w-sm">
        Logged {count} / {grammarGoal} grammar pattern today. Great job!
      </p>

      <div class="flex items-center justify-between w-full pt-2">
        <span
          class="text-xs font-mono font-bold px-2.5 py-1 rounded-lg border border-[var(--border-card)] bg-[var(--bg-base)]"
          style="color: {colorSecondary};"
        >
          📚 {count} ({pct}%)
        </span>

        <div class="flex items-center gap-2">
          <button
            onclick={toggleMode}
            class="px-3 py-1.5 rounded-xl text-xs font-bold bg-[var(--bg-base)] text-[var(--text-primary)] border border-[var(--border-card)] hover:border-[var(--border-hover)] transition-all cursor-pointer"
          >
            ✏️ Edit Patterns
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
    <!-- Inputs Grid -->
    <div class="grid grid-cols-2 gap-2 w-full pt-1">
      <!-- 1. Grammar Point / Title (Span 2) -->
      <div class="col-span-2 relative">
        <input
          bind:this={titleEl}
          bind:value={titleInput}
          onkeydown={(e) => handleKeydown(e, pronEl)}
          type="text"
          placeholder="1. Pattern / Grammar Point (e.g. 把字句, 虽然...但是...)..."
          class="w-full px-3 py-2 rounded-xl text-xs font-semibold bg-[var(--bg-base)] border border-[var(--border-card)] text-[var(--text-primary)] placeholder-[var(--text-muted)] outline-none focus:border-[var(--border-hover)] transition-colors"
        />
      </div>

      <!-- 2. Reading / Pinyin (Span 1) -->
      <div>
        <input
          bind:this={pronEl}
          bind:value={pronInput}
          onkeydown={(e) => handleKeydown(e, structureEl)}
          type="text"
          placeholder="2. Reading (e.g. bǎ zìjù)..."
          class="w-full px-3 py-2 rounded-xl text-xs font-semibold bg-[var(--bg-base)] border border-[var(--border-card)] text-[var(--text-primary)] placeholder-[var(--text-muted)] outline-none focus:border-[var(--border-hover)] transition-colors"
        />
      </div>

      <!-- 3. Structure Formula (Span 1) -->
      <div>
        <input
          bind:this={structureEl}
          bind:value={structureInput}
          onkeydown={(e) => handleKeydown(e, meaningEl)}
          type="text"
          placeholder="3. Formula (Subject + 把 + Object + Verb)..."
          class="w-full px-3 py-2 rounded-xl text-xs font-semibold bg-[var(--bg-base)] border border-[var(--border-card)] text-[var(--text-primary)] placeholder-[var(--text-muted)] outline-none focus:border-[var(--border-hover)] transition-colors"
        />
      </div>

      <!-- 4. Meaning / Usage (Span 2) -->
      <div class="col-span-2 relative">
        <input
          bind:this={meaningEl}
          bind:value={meaningInput}
          onkeydown={(e) => handleKeydown(e, linkEl)}
          type="text"
          placeholder="4. Meaning / Usage explanation..."
          class="w-full px-3 py-2 rounded-xl text-xs font-semibold bg-[var(--bg-base)] border border-[var(--border-card)] text-[var(--text-primary)] placeholder-[var(--text-muted)] outline-none focus:border-[var(--border-hover)] transition-colors"
        />
      </div>

      <!-- 5. Diagram / Media URL (Span 2) -->
      <div class="col-span-2 relative">
        <input
          bind:this={linkEl}
          bind:value={linkInput}
          onkeydown={(e) => handleKeydown(e, null)}
          type="text"
          placeholder="5. Image, Diagram, or Video link (optional)..."
          class="w-full px-3 py-2 rounded-xl text-xs font-semibold bg-[var(--bg-base)] border border-[var(--border-card)] text-[var(--text-primary)] placeholder-[var(--text-muted)] outline-none focus:border-[var(--border-hover)] transition-colors"
        />
      </div>
    </div>

    <!-- Bottom Controls & Selector -->
    <div class="flex items-center justify-between gap-2 flex-wrap pt-0.5">
      <!-- Left Action Buttons -->
      <div class="flex items-center gap-2">
        <button
          onclick={handleSubmit}
          disabled={isSubmitting}
          class="px-4 py-1.5 rounded-xl text-xs font-bold text-white shadow-xs active:scale-95 transition-all cursor-pointer disabled:opacity-50"
          style="background: linear-gradient(135deg, {colorPrimary}, {colorSecondary});"
        >
          {isEditMode ? `🔄 Update #${selectedIndex}` : '➕ Add Grammar'}
        </button>

        {#if grammarActivities.length > 0}
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

      <!-- Right HUD / Item Selector -->
      <div class="flex items-center gap-2 ml-auto">
        {#if !isEditMode}
          <div class="flex items-center gap-2.5 px-3 py-1 rounded-xl bg-[var(--bg-base)] border border-[var(--border-card)]">
            <span class="text-xs font-bold font-mono">
              <span style="color: {colorSecondary};">{count}</span> / {grammarGoal}
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
            {#each grammarActivities as item (item.item_index)}
              {@const isSelected = item.item_index === selectedIndex}
              <button
                onclick={() => selectItemForEdit(item.item_index)}
                class="px-2 py-0.5 rounded-lg text-[10px] font-bold font-mono transition-colors cursor-pointer {isSelected
                  ? 'text-white shadow-xs'
                  : 'text-[var(--text-muted)] hover:text-[var(--text-primary)]'}"
                style={isSelected ? `background-color: ${colorPrimary};` : ''}
              >
                #{item.item_index}
              </button>
            {/each}
          </div>
        {/if}
      </div>
    </div>
  {/if}
</div>