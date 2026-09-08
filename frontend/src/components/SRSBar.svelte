<!-- frontend/src/components/SRSBar.svelte -->
<script>
  import { getIntervalPreview } from '../lib/srsEngine.js';

  let {
    session = {},
    activeDate = '',
    onReview = null
  } = $props();

  // Reactively unpack from the session object proxy
  let curRev = $derived(Number(session?.revision ?? 0));
  let curInterval = $derived(Number(session?.interval ?? 0));
  let curEase = $derived(Number(session?.ease ?? 2.50));
  let displayDueDate = $derived(session?.due_date || activeDate);

  let isSubmitting = $state(false);
  let statusMessage = $state('');

  async function handleGrade(grade) {
    if (isSubmitting) return;
    isSubmitting = true;
    statusMessage = '⏳ Saving...';

    try {
      if (onReview) await onReview(grade);
      statusMessage = '✨ Recorded!';
      setTimeout(() => (statusMessage = ''), 1500);
    } catch (err) {
      console.error('SRS Review Error:', err);
      statusMessage = '❌ Error';
      setTimeout(() => (statusMessage = ''), 2000);
    } finally {
      isSubmitting = false;
    }
  }
</script>

<div class="flex items-center justify-between gap-3 p-3 px-4 rounded-2xl bg-[var(--bg-surface)] border border-[var(--border-card)] shadow-xs flex-wrap select-none">
  <!-- Left: Pass & Interval Info -->
  <div class="flex items-center gap-2.5 flex-shrink-0">
    <span class="text-xs font-mono font-black px-2.5 py-1 rounded-lg border border-[var(--border-card)] bg-[var(--bg-base)] text-[var(--interactive-accent,var(--text-primary))]">
      🎯 Pass {curRev}
    </span>

    <span class="text-xs font-semibold text-[var(--text-muted)]">
      Interval: <strong class="font-mono text-[var(--text-primary)]">{curInterval}d</strong> • Due: <strong class="font-mono text-[var(--text-primary)]">{displayDueDate}</strong>
    </span>
  </div>

  <!-- Right: Actions & Status Message -->
  <div class="flex items-center gap-2 ml-auto flex-wrap">
    {#if statusMessage}
      <span class="text-xs font-bold text-[var(--interactive-accent,var(--text-primary))] pr-1">
        {statusMessage}
      </span>
    {/if}

    {#if curRev < 2}
      <!-- Initial Passes (Pass 1 -> Pass 2) -->
      <button
        onclick={() => handleGrade('increment_initial')}
        disabled={isSubmitting}
        class="px-3.5 py-1.5 rounded-xl text-xs font-bold bg-[var(--text-primary)] text-[var(--bg-base)] hover:opacity-90 active:scale-95 transition-all cursor-pointer disabled:opacity-50"
      >
        ➕ Pass {curRev + 1}
      </button>
    {:else}
      <!-- SM-2 Grade Buttons with Dynamic Preview -->
      <div class="flex items-center gap-1.5 flex-wrap">
        <!-- Again (1d) -->
        <button
          onclick={() => handleGrade('again')}
          disabled={isSubmitting}
          class="px-2.5 py-1.5 rounded-xl text-xs font-bold bg-rose-500/15 text-rose-500 hover:bg-rose-500/25 border border-rose-500/30 active:scale-95 transition-all cursor-pointer disabled:opacity-50"
        >
          ❌ Again ({getIntervalPreview({ interval: curInterval, ease: curEase, grade: 'again' })})
        </button>

        <!-- Hard -->
        <button
          onclick={() => handleGrade('hard')}
          disabled={isSubmitting}
          class="px-2.5 py-1.5 rounded-xl text-xs font-bold bg-amber-500/15 text-amber-500 hover:bg-amber-500/25 border border-amber-500/30 active:scale-95 transition-all cursor-pointer disabled:opacity-50"
        >
          ⚡ Hard ({getIntervalPreview({ interval: curInterval, ease: curEase, grade: 'hard' })})
        </button>

        <!-- Good -->
        <button
          onclick={() => handleGrade('good')}
          disabled={isSubmitting}
          class="px-2.5 py-1.5 rounded-xl text-xs font-bold bg-emerald-500/15 text-emerald-500 hover:bg-emerald-500/25 border border-emerald-500/30 active:scale-95 transition-all cursor-pointer disabled:opacity-50"
        >
          👍 Good ({getIntervalPreview({ interval: curInterval, ease: curEase, grade: 'good' })})
        </button>

        <!-- Easy -->
        <button
          onclick={() => handleGrade('easy')}
          disabled={isSubmitting}
          class="px-2.5 py-1.5 rounded-xl text-xs font-bold bg-indigo-500/15 text-indigo-500 hover:bg-indigo-500/25 border border-indigo-500/30 active:scale-95 transition-all cursor-pointer disabled:opacity-50"
        >
          🌟 Easy ({getIntervalPreview({ interval: curInterval, ease: curEase, grade: 'easy' })})
        </button>
      </div>
    {/if}
  </div>
</div>