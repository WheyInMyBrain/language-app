<!-- frontend/src/components/ListeningBar.svelte -->
<script>
  import { activeLanguage } from '../lib/stores/activeLanguage.svelte.js';
  import { listeningIndexStore } from '../lib/stores/listeningIndex.svelte.js';
  import { 
    canonicalizeVideoUrl, 
    parseTimerToSeconds, 
    formatSecondsToTimer 
  } from '../lib/mediaResolver.js';

  let {
    listeningActivities = [], // [{ item_index, link, link_duration, audio_duration }]
    activeDate = '',
    onAddListening,           // async ({ link, durationSec }) => void
    onUpdateListening         // async (itemIndex, { link, durationSec }) => void
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
  let listeningGoalMins = $derived(goals.listening_minutes || goals.listening || 45);
  let colorPrimary = $derived(colors.listening?.dark_primary || '#bf360c');
  let colorSecondary = $derived(colors.listening?.light_primary || '#ff7043');

  // Time-based Metrics
  let totalDurationSec = $derived(
    listeningActivities.reduce((acc, it) => acc + (it.link_duration || 0), 0)
  );
  let totalMinutes = $derived(Math.floor(totalDurationSec / 60));
  let goalSeconds = $derived(listeningGoalMins * 60);
  let pct = $derived(
    goalSeconds > 0 ? Math.min(100, Math.round((totalDurationSec / goalSeconds) * 100)) : 0
  );
  let isCompleted = $derived(totalDurationSec >= goalSeconds && goalSeconds > 0);

  // Live duplicate check against {lang}:listening_index
  let duplicateMatches = $derived.by(() => {
    const raw = linkInput.trim();
    if (!raw) return [];

    if (isEditMode) {
      const current = listeningActivities.find((a) => a.item_index === selectedIndex);
      if (current && canonicalizeVideoUrl(current.link) === canonicalizeVideoUrl(raw)) {
        return [];
      }
    }
    return listeningIndexStore.findMatches(raw, activeDate);
  });

  function selectItemForEdit(itemIdx) {
    selectedIndex = itemIdx;
    const target = listeningActivities.find((a) => a.item_index === itemIdx);
    if (target) {
      linkInput = target.link || '';
      durationInput = formatSecondsToTimer(target.link_duration || 0);
    }
  }

  function toggleMode() {
    isEditMode = !isEditMode;
    if (isEditMode && listeningActivities.length > 0) {
      selectItemForEdit(listeningActivities[0].item_index || 1);
    } else {
      linkInput = '';
      durationInput = '';
    }
  }

  async function handleSubmit() {
    const rawUrl = linkInput.trim();
    const cleanUrl = canonicalizeVideoUrl(rawUrl);
    const durationSec = parseTimerToSeconds(durationInput);

    if (!cleanUrl && durationSec <= 0) {
      statusMessage = '⚠️ Enter a link or duration';
      setTimeout(() => (statusMessage = ''), 2000);
      return;
    }

    isSubmitting = true;

    try {
      const payload = {
        link: cleanUrl || '',
        durationSec
      };

      if (isEditMode) {
        if (onUpdateListening) await onUpdateListening(selectedIndex, payload);
        statusMessage = `🔄 Updated #${selectedIndex}!`;
      } else {
        if (onAddListening) await onAddListening(payload);
        statusMessage = `✅ Added #${listeningActivities.length + 1}!`;

        linkInput = '';
        durationInput = '';
        linkEl?.focus();
      }
    } catch (err) {
      console.error('Failed to save listening item:', err);
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
        🎉 Listening Immersion Completed!
      </div>

      <p class="text-xs text-[var(--text-muted)] max-w-sm">
        Logged {totalMinutes}m / {listeningGoalMins}m immersion today. Excellent focus!
      </p>

      <div class="flex items-center justify-between w-full pt-2">
        <span
          class="text-xs font-mono font-bold px-2.5 py-1 rounded-lg border border-[var(--border-card)] bg-[var(--bg-base)]"
          style="color: {colorSecondary};"
        >
          🎧 {totalMinutes}m ({pct}%) • {listeningActivities.length} logs
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
    <!-- Vertical Stacked Input Form -->
    <div class="flex flex-col gap-2 w-full pt-1">
      <!-- 1. URL Input with Live History Alert -->
      <div class="relative w-full flex items-center">
        <input
          bind:this={linkEl}
          bind:value={linkInput}
          onkeydown={(e) => handleKeydown(e, durationEl)}
          type="text"
          placeholder="1. Paste YouTube, Podcast, or Video URL..."
          class="w-full px-3 py-2 rounded-xl text-xs font-semibold bg-[var(--bg-base)] border border-[var(--border-card)] text-[var(--text-primary)] placeholder-[var(--text-muted)] outline-none focus:border-[var(--border-hover)] transition-colors pr-20"
        />

        {#if duplicateMatches.length > 0}
          <span
            title="Listened on {duplicateMatches.map((m) => m.date).join(', ')}"
            class="absolute right-2 text-[9px] font-bold font-mono px-1.5 py-0.5 rounded bg-amber-500/15 text-amber-500 border border-amber-500/30 whitespace-nowrap pointer-events-none"
          >
            ⚠️ {duplicateMatches.length === 1 ? duplicateMatches[0].date : `${duplicateMatches.length} logs`}
          </span>
        {/if}
      </div>

      <!-- 2. Duration Input -->
      <div class="relative w-full">
        <input
          bind:this={durationEl}
          bind:value={durationInput}
          onkeydown={(e) => handleKeydown(e, null)}
          type="text"
          placeholder="2. Duration (e.g. 15:30, 45m, or mm:ss)..."
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
          {isEditMode ? `🔄 Update #${selectedIndex}` : '➕ Add Listening'}
        </button>

        {#if listeningActivities.length > 0}
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

      <!-- Right HUD / Time Progress / Item Selector -->
      <div class="flex items-center gap-2 ml-auto">
        {#if !isEditMode}
          <!-- Time-based Progress HUD -->
          <div class="flex items-center gap-2.5 px-3 py-1 rounded-xl bg-[var(--bg-base)] border border-[var(--border-card)]">
            <span class="text-xs font-bold font-mono">
              <span style="color: {colorSecondary};">{totalMinutes}m</span> / {listeningGoalMins}m
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
          <!-- Edit Mode Item Pills -->
          <div class="flex items-center gap-1.5 overflow-x-auto max-w-[200px] p-1 rounded-xl bg-[var(--bg-base)] border border-[var(--border-card)]">
            {#each listeningActivities as item (item.item_index)}
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