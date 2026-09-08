<!-- frontend/src/components/CIBar.svelte -->
<script>
  import { activeLanguage } from '../lib/stores/activeLanguage.svelte.js';
  import { 
    canonicalizeVideoUrl, 
    parseTimerToSeconds, 
    formatSecondsToTimer 
  } from '../lib/mediaResolver.js';

  let {
    ciActivities = [],   // [{ item_index, link, link_duration, audio_duration }]
    activeDate = '',
    onAddCI,             // async ({ link, durationSec }) => void
    onUpdateCI           // async (itemIndex, { link, durationSec }) => void
  } = $props();

  let linkInput = $state('');
  let durationInput = $state('');

  let isEditMode = $state(false);
  let selectedIndex = $state(1);
  let statusMessage = $state('');
  let isSubmitting = $state(false);

  let linkEl = $state(null);
  let durationEl = $state(null);

  // Configuration
  let goals = $derived(activeLanguage.goals);
  let colors = $derived(activeLanguage.colors);
  let ciGoal = $derived(goals.ci || 1);
  let colorPrimary = $derived(colors.ci?.dark_primary || '#6a1b9a');
  let colorSecondary = $derived(colors.ci?.light_primary || '#ab47bc');

  // Metrics
  let count = $derived(ciActivities.length);
  let totalDurationSec = $derived(
    ciActivities.reduce((acc, it) => acc + (it.link_duration || 0), 0)
  );
  let pct = $derived(ciGoal > 0 ? Math.min(100, Math.round((count / ciGoal) * 100)) : 0);
  let isCompleted = $derived(count >= ciGoal && ciGoal > 0);

  function selectItemForEdit(itemIdx) {
    selectedIndex = itemIdx;
    const target = ciActivities.find((a) => a.item_index === itemIdx);
    if (target) {
      linkInput = target.link || '';
      durationInput = formatSecondsToTimer(target.link_duration || 0);
    }
  }

  function toggleMode() {
    isEditMode = !isEditMode;
    if (isEditMode && ciActivities.length > 0) {
      selectItemForEdit(ciActivities[0].item_index || 1);
    } else {
      linkInput = '';
      durationInput = '';
    }
  }

  async function handleSubmit() {
    const rawUrl = linkInput.trim();
    const cleanUrl = canonicalizeVideoUrl(rawUrl);
    const durationSec = parseTimerToSeconds(durationInput);

    if (!cleanUrl) {
      statusMessage = '⚠️ Enter a video link';
      setTimeout(() => (statusMessage = ''), 2000);
      return;
    }

    isSubmitting = true;

    try {
      const payload = {
        link: cleanUrl,
        durationSec
      };

      if (isEditMode) {
        if (onUpdateCI) await onUpdateCI(selectedIndex, payload);
        statusMessage = `🔄 Updated #${selectedIndex}!`;
      } else {
        if (onAddCI) await onAddCI(payload);
        statusMessage = `✅ Added #${ciActivities.length + 1}!`;

        linkInput = '';
        durationInput = '';
        linkEl?.focus();
      }
    } catch (err) {
      console.error('Failed to save CI item:', err);
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
  <!-- Accent Border Line -->
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
        🎉 Comprehensible Input Completed!
      </div>

      <p class="text-xs text-[var(--text-muted)] max-w-sm">
        Logged {count} / {ciGoal} video ({formatSecondsToTimer(totalDurationSec)} total).
      </p>

      <div class="flex items-center justify-between w-full pt-2">
        <span
          class="text-xs font-mono font-bold px-2.5 py-1 rounded-lg border border-[var(--border-card)] bg-[var(--bg-base)]"
          style="color: {colorSecondary};"
        >
          📺 {count} ({pct}%) • {formatSecondsToTimer(totalDurationSec)}
        </span>

        <div class="flex items-center gap-2">
          <button
            onclick={toggleMode}
            class="px-3 py-1.5 rounded-xl text-xs font-bold bg-[var(--bg-base)] text-[var(--text-primary)] border border-[var(--border-card)] hover:border-[var(--border-hover)] transition-all cursor-pointer"
          >
            ✏️ Edit Videos
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
    <!-- Vertical Stacked Input Form -->
    <div class="flex flex-col gap-2 w-full pt-1">
      <!-- 1. Video URL Input -->
      <div class="relative w-full">
        <input
          bind:this={linkEl}
          bind:value={linkInput}
          onkeydown={(e) => handleKeydown(e, durationEl)}
          type="text"
          placeholder="1. Paste YouTube or Bilibili video URL..."
          class="w-full px-3 py-2 rounded-xl text-xs font-semibold bg-[var(--bg-base)] border border-[var(--border-card)] text-[var(--text-primary)] placeholder-[var(--text-muted)] outline-none focus:border-[var(--border-hover)] transition-colors"
        />
      </div>

      <!-- 2. Duration Input -->
      <div class="relative w-full">
        <input
          bind:this={durationEl}
          bind:value={durationInput}
          onkeydown={(e) => handleKeydown(e, null)}
          type="text"
          placeholder="2. Duration (e.g. 14:20 or mm:ss)..."
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
          {isEditMode ? `🔄 Update #${selectedIndex}` : '➕ Add CI'}
        </button>

        {#if ciActivities.length > 0}
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

      <!-- Right HUD / Edit Pills -->
      <div class="flex items-center gap-2 ml-auto">
        {#if !isEditMode}
          <div class="flex items-center gap-2.5 px-3 py-1 rounded-xl bg-[var(--bg-base)] border border-[var(--border-card)]">
            <span class="text-xs font-bold font-mono">
              <span style="color: {colorSecondary};">{count}</span> / {ciGoal}
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
            {#each ciActivities as item (item.item_index)}
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