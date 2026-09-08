<script>
  import { metadataStore } from '../lib/stores/metadata.svelte.js';
  import { activeLanguage } from '../lib/stores/activeLanguage.svelte.js';
  import { srsStore } from '../lib/stores/srs.svelte.js';

  let { onSelectDate } = $props();

  function formatLocalDate(d) {
    const year = d.getFullYear();
    const month = String(d.getMonth() + 1).padStart(2, '0');
    const day = String(d.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
  }

  const now = new Date();
  const todayStr = formatLocalDate(now);

  // 1. Reactive State
  let langCode = $derived(metadataStore.activeLanguage);
  let goals = $derived(activeLanguage.goals);
  let colors = $derived(activeLanguage.colors);

  let todayKey = $derived(`${langCode}:${todayStr}`);
  let todayLog = $derived(metadataStore.calendarIndex[todayKey] || null);

  let vocabDone = $derived(todayLog?.word || 0);
  let grammarDone = $derived(todayLog?.grammar || 0);
  let ciDone = $derived(todayLog?.ci || 0);
  let listeningMinDone = $derived(Math.round((todayLog?.listening_time || 0) / 60));
  let speakingMinDone = $derived(Math.round((todayLog?.speaking_time || 0) / 60));

  // Visual-only SRS due count
  let flashcardsDue = $derived(srsStore.getVisualDueCount(todayStr));

  // 2. SVG Ring Math (Radius: 28, Circumference ~ 175.93)
  const RADIUS = 28;
  const CIRCUMFERENCE = 2 * Math.PI * RADIUS;

  function getOffset(current, target) {
    if (!target || target <= 0) return CIRCUMFERENCE;
    const progress = Math.min(Math.max(current / target, 0), 1);
    return CIRCUMFERENCE * (1 - progress);
  }

  function getPct(current, target) {
    if (!target || target <= 0) return 0;
    return Math.min(Math.round((current / target) * 100), 100);
  }

  // 3. Ring Specifications (Habits with targets)
  let ringItems = $derived([
    {
      id: 'vocab',
      title: 'Vocab',
      icon: '🗣️',
      current: vocabDone,
      target: goals.vocab,
      unit: '',
      color: colors.vocab?.dark_primary || '#2e7d32'
    },
    {
      id: 'grammar',
      title: 'Grammar',
      icon: '📚',
      current: grammarDone,
      target: goals.grammar,
      unit: '',
      color: colors.grammar?.dark_primary || '#01579b'
    },
    {
      id: 'ci',
      title: 'CI Video',
      icon: '📺',
      current: ciDone,
      target: goals.ci,
      unit: '',
      color: colors.ci?.dark_primary || '#6a1b9a'
    },
    {
      id: 'listening',
      title: 'Listen',
      icon: '🎧',
      current: listeningMinDone,
      target: goals.listening_minutes,
      unit: 'm',
      color: colors.listening?.dark_primary || '#bf360c'
    },
    {
      id: 'speaking',
      title: 'Speak',
      icon: '🎙️',
      current: speakingMinDone,
      target: goals.speaking_minutes,
      unit: 'm',
      color: colors.speaking?.dark_primary || '#b388ff'
    }
  ]);

  // Action Items & Overdue Logic
  let scheduledActionItems = $derived.by(() => {
    const items = [];
    const entries = metadataStore.sortedCalendarEntries;

    for (const entry of entries) {
      if (!entry.due_date) continue;

      if (entry.due_date < todayStr) {
        const diffDays = Math.max(
          1,
          Math.round((new Date(todayStr) - new Date(entry.due_date)) / (1000 * 60 * 60 * 24))
        );
        items.push({
          date: entry.date,
          revision: entry.revision,
          status: `${diffDays}d LATE`,
          isOverdue: true
        });
      } else if (entry.due_date === todayStr) {
        items.push({
          date: entry.date,
          revision: entry.revision,
          status: 'DUE',
          isOverdue: false
        });
      }
    }
    return items;
  });

  let hasTodayLog = $derived(todayLog !== null);
  let overdueCount = $derived(scheduledActionItems.filter((i) => i.isOverdue).length);
  let flashcardColor = $derived(colors.flashcard?.dark_primary || '#f43f5e');
</script>

<div class="relative w-full rounded-2xl border border-[var(--border-card)] bg-[var(--bg-surface)] p-4 shadow-xs space-y-5 overflow-hidden select-none">
  <!-- Status Accent Strip -->
  <div 
    class="absolute top-0 left-0 right-0 h-[3px] transition-colors duration-300 {overdueCount > 0 ? 'bg-rose-500' : hasTodayLog ? 'bg-emerald-500' : 'bg-amber-500'}"
  ></div>

  <!-- Fitness Rings & SRS Stat Grid -->
  <div class="grid grid-cols-3 gap-2 sm:gap-3">
    <!-- 1–5: Target-based Habit Rings -->
    {#each ringItems as ring (ring.id)}
      {@const pct = getPct(ring.current, ring.target)}
      {@const offset = getOffset(ring.current, ring.target)}

      <div class="flex flex-col items-center justify-between p-2.5 rounded-xl border border-[var(--border-card)] bg-[var(--bg-base)] transition-all duration-200">
        <!-- Card Header -->
        <div class="flex items-center gap-1 text-[10px] uppercase font-bold tracking-wider text-[var(--text-muted)] truncate max-w-full">
          <span>{ring.icon}</span>
          <span class="truncate">{ring.title}</span>
        </div>

        <!-- SVG Fitness Ring -->
        <div class="relative w-[70px] h-[70px] my-1.5 flex items-center justify-center">
          <svg class="w-full h-full -rotate-90 transform" viewBox="0 0 70 70">
            <!-- Background Inactive Track -->
            <circle
              cx="35"
              cy="35"
              r={RADIUS}
              stroke="currentColor"
              stroke-width="6"
              fill="none"
              class="text-[var(--border-card)] opacity-35"
            />
            <!-- Animated Progress Ring -->
            <circle
              cx="35"
              cy="35"
              r={RADIUS}
              stroke={ring.color}
              stroke-width="6"
              stroke-linecap="round"
              fill="none"
              stroke-dasharray={CIRCUMFERENCE}
              stroke-dashoffset={offset}
              class="transition-[stroke-dashoffset] duration-700 ease-out"
            />
          </svg>

          <!-- Centered Data Values -->
          <div class="absolute inset-0 flex flex-col items-center justify-center pointer-events-none text-center">
            <span class="text-[11px] font-black tracking-tight leading-tight" style="color: {ring.color};">
              {ring.current}{ring.unit}
            </span>
            <span class="text-[9px] font-bold text-[var(--text-muted)] opacity-80 leading-tight">
              {pct}%
            </span>
          </div>
        </div>

        <!-- Target Label -->
        <div class="text-[9px] font-semibold text-[var(--text-muted)]">
          Goal: {ring.target}{ring.unit}
        </div>
      </div>
    {/each}

    <!-- 6: Number-Only Due Cards Counter (No SVG circle) -->
    <div class="flex flex-col items-center justify-between p-2.5 rounded-xl border border-[var(--border-card)] bg-[var(--bg-base)] transition-all duration-200">
      <div class="flex items-center gap-1 text-[10px] uppercase font-bold tracking-wider text-[var(--text-muted)] truncate max-w-full">
        <span>🀄</span>
        <span class="truncate">Cards</span>
      </div>

      <!-- Plain Large Number Badge -->
      <div class="my-1.5 h-[70px] w-full flex flex-col items-center justify-center">
        {#if flashcardsDue === 0}
          <span class="text-2xl font-black text-emerald-500 leading-none">
            ✓
          </span>
          <span class="text-[10px] font-bold font-mono text-emerald-500 mt-1 uppercase tracking-wide">
            Done
          </span>
        {:else}
          <span class="text-3xl font-black tracking-tight leading-none font-mono" style="color: {flashcardColor};">
            {flashcardsDue}
          </span>
          <span class="text-[9px] font-bold uppercase tracking-wider text-[var(--text-muted)] mt-1">
            Due Now
          </span>
        {/if}
      </div>

      <div class="text-[9px] font-semibold text-[var(--text-muted)]">
        Review Queue
      </div>
    </div>
  </div>

  <!-- Priority Actions Header -->
  <div class="pt-1 flex items-center justify-between border-t border-[var(--border-card)]">
    <div class="flex items-center gap-2">
      <span class="text-sm">
        {overdueCount > 0 ? '🚨' : !hasTodayLog ? '📝' : '⚡'}
      </span>
      <span class="text-xs font-bold uppercase tracking-wider text-[var(--text-primary)]">
        Today's Priority Actions
      </span>
    </div>

    <div class="flex items-center gap-1.5">
      {#if !hasTodayLog}
        <span class="text-[10px] font-bold px-2 py-0.5 rounded-md bg-amber-500/15 text-amber-500 border border-amber-500/30">
          Pending
        </span>
      {/if}
      {#if overdueCount > 0}
        <span class="text-[10px] font-bold px-2 py-0.5 rounded-md bg-rose-500/15 text-rose-500 border border-rose-500/30">
          {overdueCount} Late
        </span>
      {/if}
    </div>
  </div>

  <!-- Action Track Items -->
  <div class="space-y-2">
    {#if !hasTodayLog}
      <button
        onclick={() => onSelectDate(todayStr)}
        class="w-full flex items-center justify-between p-3 rounded-xl border border-amber-500/40 bg-amber-500/5 transition-transform duration-75 active:scale-[0.98] text-left cursor-pointer"
      >
        <div class="flex items-center gap-2.5">
          <span class="text-[10px] font-extrabold px-1.5 py-0.5 rounded bg-amber-500/20 text-amber-500 border border-amber-500/30 uppercase">
            CREATE
          </span>
          <span class="text-xs font-semibold text-[var(--text-primary)]">
            Create Today's Log ({todayStr})
          </span>
        </div>
        <span class="text-xs font-bold text-amber-500">+ Open</span>
      </button>
    {/if}

    {#each scheduledActionItems as item (item.date)}
      <button
        onclick={() => onSelectDate(item.date)}
        class="w-full flex items-center justify-between p-3 rounded-xl border border-[var(--border-card)] bg-[var(--bg-base)] transition-transform duration-75 active:scale-[0.98] text-left cursor-pointer {item.isOverdue ? 'border-rose-500/40 bg-rose-500/5' : ''}"
      >
        <div class="flex items-center gap-2.5 truncate">
          <span 
            class="text-[10px] font-extrabold px-1.5 py-0.5 rounded uppercase flex-shrink-0 {item.isOverdue ? 'bg-rose-500/20 text-rose-400 border border-rose-500/30' : 'bg-sky-500/20 text-sky-400 border border-sky-500/30'}"
          >
            {item.status}
          </span>
          <span class="text-xs font-semibold text-[var(--text-primary)] truncate">
            {item.date}
          </span>
        </div>

        <div class="text-[11px] font-medium text-[var(--text-muted)] flex-shrink-0 ml-2">
          Rev {item.revision}
        </div>
      </button>
    {/each}

    {#if hasTodayLog && scheduledActionItems.length === 0}
      <div class="py-3 text-center text-xs text-[var(--text-muted)] italic">
        ✨ All caught up for today!
      </div>
    {/if}
  </div>
</div>