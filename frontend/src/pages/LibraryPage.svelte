<!-- frontend/src/pages/LibraryPage.svelte -->
<script>
  import { activeLanguage } from '../lib/stores/activeLanguage.svelte.js';
  import { ciIndexStore } from '../lib/stores/ciIndex.svelte.js';
  import { listeningIndexStore } from '../lib/stores/listeningIndex.svelte.js';
  import { getUnprocessedCICandidates } from '../lib/services/ciCandidateService.js';
  import VideoPlayer from '../components/VideoPlayer.svelte';

  let { onSelectDate = null } = $props();

  let colors = $derived(activeLanguage.colors);
  let accentColor = $derived(colors.ci?.dark_primary || '#6a1b9a');

  let candidateData = $derived(
    getUnprocessedCICandidates(
      listeningIndexStore.entries,
      ciIndexStore.links
    )
  );

  let totalAvailable = $derived(candidateData.candidates.length);
  let sortedDates = $derived(candidateData.sortedDates);
  let groupedByDate = $derived(candidateData.groupedByDate);

  // Tracks open state per date so hidden accordions mount 0 DOM elements
  let openAccordions = $state({});

  function toggleDate(dateKey, isOpen) {
    openAccordions = { ...openAccordions, [dateKey]: isOpen };
  }

  let copiedUrl = $state(null);

  async function handleCopy(url) {
    try {
      await navigator.clipboard.writeText(url);
      copiedUrl = url;
      setTimeout(() => {
        if (copiedUrl === url) copiedUrl = null;
      }, 1800);
    } catch (err) {
      console.error('Clipboard copy failed:', err);
    }
  }
</script>

<div class="w-full max-w-2xl mx-auto space-y-4 pt-2 pb-16 px-1 select-none">
  <!-- Header Card -->
  <div class="flex items-center justify-between p-3.5 sm:p-4 rounded-2xl border border-[var(--border-card)] bg-[var(--bg-surface)] shadow-xs">
    <div class="flex items-center gap-2.5 min-w-0">
      <span class="text-xl">🎧</span>
      <div>
        <h1 class="text-sm sm:text-base font-black text-[var(--text-primary)]">
          CI Candidate Queue
        </h1>
        <p class="text-[11px] text-[var(--text-muted)] font-medium">
          Listened media ready to be processed into Comprehensible Input
        </p>
      </div>
    </div>

    <span
      class="text-xs font-mono font-bold px-2.5 py-1 rounded-xl border shrink-0"
      style="color: {accentColor}; background-color: {accentColor}18; border-color: {accentColor}35;"
    >
      {totalAvailable} available
    </span>
  </div>

  <!-- Content Section -->
  {#if sortedDates.length === 0}
    <div class="p-8 text-center rounded-2xl border border-dashed border-[var(--border-card)] bg-[var(--bg-surface)] text-xs text-[var(--text-muted)] space-y-1">
      <div class="text-2xl mb-1">✨</div>
      <p class="font-bold text-[var(--text-primary)]">All caught up!</p>
      <p>All listened videos have been processed into Comprehensible Input.</p>
    </div>
  {:else}
    <div class="space-y-2.5">
      {#each sortedDates as dateKey (dateKey)}
        {@const videos = groupedByDate[dateKey]}
        {@const isOpen = !!openAccordions[dateKey]}
        <details
          open={isOpen}
          ontoggle={(e) => toggleDate(dateKey, e.currentTarget.open)}
          class="group rounded-2xl border border-[var(--border-card)] bg-[var(--bg-surface)] overflow-hidden transition-colors"
        >
          <summary class="flex items-center justify-between p-3.5 cursor-pointer list-none hover:bg-[var(--bg-surface-active)] transition-colors select-none">
            <div class="flex items-center gap-2 font-mono font-bold text-xs text-[var(--text-primary)]">
              <span>📅</span>
              <span>{dateKey}</span>
            </div>

            <div class="flex items-center gap-2">
              <span class="text-[10px] font-mono font-bold px-2 py-0.5 rounded-md border border-[var(--border-card)] bg-[var(--bg-base)] text-[var(--text-muted)]">
                🎬 {videos.length} available
              </span>
              <span class="text-xs text-[var(--text-muted)] group-open:rotate-180 transition-transform duration-200">
                ▼
              </span>
            </div>
          </summary>

          <!-- Accordion Grid: Only evaluated in DOM when open -->
          {#if isOpen}
            <div class="p-3.5 border-t border-[var(--border-card)] bg-[var(--bg-base)] grid grid-cols-1 sm:grid-cols-2 gap-3">
              {#each videos as item, i (`${dateKey}_${item.url}_${i}`)}
                <div class="flex flex-col rounded-xl border border-[var(--border-card)] bg-[var(--bg-surface)] overflow-hidden shadow-xs hover:border-[var(--border-hover)] transition-all">
                  <div class="w-full">
                    <VideoPlayer src={item.url} {accentColor} />
                  </div>

                  <div class="p-2.5 flex items-center justify-between gap-2 border-t border-[var(--border-card)] bg-[var(--bg-surface)]">
                    {#if onSelectDate}
                      <button
                        type="button"
                        onclick={() => onSelectDate(dateKey)}
                        class="text-[11px] font-mono font-bold text-[var(--text-primary)] hover:underline truncate text-left cursor-pointer"
                      >
                        📄 {dateKey}
                      </button>
                    {:else}
                      <span class="text-[11px] font-mono font-bold text-[var(--text-muted)] truncate">
                        {dateKey}
                      </span>
                    {/if}

                    <div class="flex items-center gap-1.5 shrink-0">
                      <button
                        type="button"
                        onclick={() => handleCopy(item.url)}
                        class="px-2.5 py-1 text-[10px] font-bold rounded-lg border border-[var(--border-card)] bg-[var(--bg-base)] hover:border-[var(--border-hover)] text-[var(--text-primary)] transition-all active:scale-95 cursor-pointer"
                        style={copiedUrl === item.url ? `color: ${accentColor}; border-color: ${accentColor};` : ''}
                      >
                        {copiedUrl === item.url ? 'Copied! ✓' : '📋 Copy'}
                      </button>

                      <a
                        href={item.url}
                        target="_blank"
                        rel="noopener noreferrer"
                        class="px-2 py-1 text-[10px] font-bold rounded-lg text-[var(--text-muted)] hover:text-[var(--text-primary)] transition-colors"
                        title="Open source in new tab"
                      >
                        ↗
                      </a>
                    </div>
                  </div>
                </div>
              {/each}
            </div>
          {/if}
        </details>
      {/each}
    </div>
  {/if}
</div>