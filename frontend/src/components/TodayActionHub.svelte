<script>
  import { metadataStore } from '../lib/stores/metadata.svelte.js';
  import { activeLanguage } from '../lib/stores/activeLanguage.svelte.js';
  import { srsStore } from '../lib/stores/srs.svelte.js';

  import { 
    Sparkles, 
    CheckCircle2, 
    AlertTriangle, 
    Flame, 
    ArrowRight, 
    Clock, 
    Play, 
    Headphones, 
    Mic, 
    BookOpen, 
    MessageSquare,
    Calendar,
    Eye,
    PenTool
  } from '@lucide/svelte';

  let { onSelectDate } = $props();

  function formatLocalDate(d) {
    const year = d.getFullYear();
    const month = String(d.getMonth() + 1).padStart(2, '0');
    const day = String(d.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
  }

  const now = new Date();
  const todayStr = formatLocalDate(now);

  const tomorrow = new Date(now);
  tomorrow.setDate(tomorrow.getDate() + 1);
  const tomorrowStr = formatLocalDate(tomorrow);

  // 1. Reactive Store Bindings
  let langCode = $derived(metadataStore.activeLanguage);
  let goals = $derived(activeLanguage.goals || {});
  let colors = $derived(activeLanguage.colors || {});
  let themeColor = $derived(activeLanguage.themeColor || '#a855f7');

  let todayKey = $derived(`${langCode}:${todayStr}`);
  let todayLog = $derived(metadataStore.calendarIndex?.[todayKey] || null);

  let vocabDone = $derived(todayLog?.word || 0);
  let listeningMinDone = $derived(Math.round((todayLog?.listening_time || 0) / 60));
  let speakingMinDone = $derived(Math.round((todayLog?.speaking_time || 0) / 60));
  let ciDone = $derived(todayLog?.ci || 0);
  let grammarDone = $derived(todayLog?.grammar || 0);

  // 🌟 Tri-Deck SRS Counters (Vision, Listen, Write) 🌟
  let srsCounts = $derived.by(() => {
    const raw = srsStore.cards || {};
    let visualDue = 0;
    let audioDue = 0;
    let writingDue = 0;

    for (const item of Object.values(raw)) {
      if (!item) continue;
      const isDue = !item.due_date || item.due_date <= todayStr;
      if (isDue) {
        if (item.card_type === 'listening' || item.card_type === 'audio') {
          audioDue++;
        } else if (item.card_type === 'writing') {
          writingDue++;
        } else {
          visualDue++;
        }
      }
    }
    return { 
      visualDue, 
      audioDue, 
      writingDue, 
      totalDue: visualDue + audioDue + writingDue 
    };
  });

  // Interactive Hover State
  let hoveredRingId = $state(null);

  function getPct(current, target) {
    if (!target || target <= 0) return 0;
    return Math.min(Math.round((current / target) * 100), 100);
  }

  // 5 concentric rings (Radii calibrated Outer -> Inner)
  const CONCENTRIC_CONFIG = [
    { radius: 84, stroke: 8.5 }, // 1. Vocabulary (Outer)
    { radius: 71, stroke: 8.5 }, // 2. Listening
    { radius: 58, stroke: 8.5 }, // 3. Speaking
    { radius: 45, stroke: 8.5 }, // 4. CI Video
    { radius: 32, stroke: 8.5 }  // 5. Grammar (Inner)
  ];

  let concentricRings = $derived([
    {
      id: 'vocab',
      title: 'Vocabulary',
      icon: MessageSquare,
      current: vocabDone,
      target: goals.vocab || 10,
      unit: 'w',
      color: colors.vocab?.primary || colors.vocab?.dark_primary || '#10b981',
      colorSub: colors.vocab?.light_primary || '#34d399',
      ...CONCENTRIC_CONFIG[0]
    },
    {
      id: 'listening',
      title: 'Listening',
      icon: Headphones,
      current: listeningMinDone,
      target: goals.listening_minutes || 30,
      unit: 'm',
      color: colors.listening?.primary || colors.listening?.dark_primary || '#f97316',
      colorSub: colors.listening?.light_primary || '#fb923c',
      ...CONCENTRIC_CONFIG[1]
    },
    {
      id: 'speaking',
      title: 'Speaking',
      icon: Mic,
      current: speakingMinDone,
      target: goals.speaking_minutes || 15,
      unit: 'm',
      color: colors.speaking?.primary || colors.speaking?.dark_primary || '#ec4899',
      colorSub: colors.speaking?.light_primary || '#f472b6',
      ...CONCENTRIC_CONFIG[2]
    },
    {
      id: 'ci',
      title: 'CI Video',
      icon: Play,
      current: ciDone,
      target: goals.ci || 1,
      unit: 'v',
      color: colors.ci?.primary || colors.ci?.dark_primary || '#a855f7',
      colorSub: colors.ci?.light_primary || '#c084fc',
      ...CONCENTRIC_CONFIG[3]
    },
    {
      id: 'grammar',
      title: 'Grammar',
      icon: BookOpen,
      current: grammarDone,
      target: goals.grammar || 3,
      unit: 'p',
      color: colors.grammar?.primary || colors.grammar?.dark_primary || '#0ea5e9',
      colorSub: colors.grammar?.light_primary || '#38bdf8',
      ...CONCENTRIC_CONFIG[4]
    }
  ]);

  let overallAveragePct = $derived.by(() => {
    if (!concentricRings.length) return 0;
    const total = concentricRings.reduce((acc, r) => acc + getPct(r.current, r.target), 0);
    return Math.round(total / concentricRings.length);
  });

  let activeRingData = $derived.by(() => {
    if (!hoveredRingId) return null;
    const ring = concentricRings.find(r => r.id === hoveredRingId);
    if (!ring) return null;
    return {
      title: ring.title,
      pct: getPct(ring.current, ring.target),
      color: ring.color,
      current: ring.current,
      target: ring.target,
      unit: ring.unit
    };
  });

  // Schedule Logic
  let scheduledActionItems = $derived.by(() => {
    const items = [];
    const entries = metadataStore.sortedCalendarEntries || [];

    for (let i = 0; i < entries.length; i++) {
      const entry = entries[i];
      const rev = Number(entry.revision ?? 0);
      const dueDate = entry.due_date;

      if (rev < 1) {
        if (entry.date < todayStr) {
          const diffDays = Math.max(
            1,
            Math.round((new Date(todayStr) - new Date(entry.date)) / (1000 * 60 * 60 * 24))
          );
          items.push({
            date: entry.date,
            revision: 0,
            statusLabel: `+${diffDays}d LATE`,
            urgencyCategory: 'overdue',
            overdueDays: diffDays,
            sortWeight: -diffDays
          });
        } else if (entry.date === todayStr) {
          items.push({
            date: entry.date,
            revision: 0,
            statusLabel: 'NEW',
            urgencyCategory: 'today',
            overdueDays: 0,
            sortWeight: 0
          });
        }
        continue;
      }

      if (dueDate) {
        if (dueDate < todayStr) {
          const diffDays = Math.max(
            1,
            Math.round((new Date(todayStr) - new Date(dueDate)) / (1000 * 60 * 60 * 24))
          );
          items.push({
            date: entry.date,
            revision: rev,
            statusLabel: `+${diffDays}d LATE`,
            urgencyCategory: 'overdue',
            overdueDays: diffDays,
            sortWeight: -diffDays
          });
        } else if (dueDate === todayStr) {
          items.push({
            date: entry.date,
            revision: rev,
            statusLabel: 'TODAY',
            urgencyCategory: 'today',
            overdueDays: 0,
            sortWeight: 1
          });
        } else if (dueDate === tomorrowStr) {
          items.push({
            date: entry.date,
            revision: rev,
            statusLabel: 'TOMORROW',
            urgencyCategory: 'tomorrow',
            overdueDays: 0,
            sortWeight: 2
          });
        }
      }
    }

    return items.sort((a, b) => a.sortWeight - b.sortWeight);
  });

  let hasTodayLog = $derived(todayLog !== null);
  let overdueCount = $derived(scheduledActionItems.filter((i) => i.urgencyCategory === 'overdue').length);
  let flashcardColor = $derived(colors.flashcard?.primary || colors.flashcard?.dark_primary || '#f43f5e');
  let audioColor = $derived(colors.listening?.primary || colors.listening?.dark_primary || '#f97316');
  let writingColor = $derived(colors.speaking?.primary || colors.speaking?.dark_primary || '#c026d3');
  let vocabColor = $derived(colors.vocab?.primary || colors.vocab?.dark_primary || '#10b981');

  function getUrgencyStyles(item) {
    if (item.urgencyCategory === 'today') {
      return {
        pillBg: `color-mix(in srgb, ${vocabColor} 22%, transparent)`,
        pillBorder: `color-mix(in srgb, ${vocabColor} 55%, transparent)`,
        pillText: vocabColor,
        rowBorder: `color-mix(in srgb, ${vocabColor} 30%, transparent)`,
        rowBg: `color-mix(in srgb, ${vocabColor} 8%, transparent)`,
        glow: `0 0 20px color-mix(in srgb, ${vocabColor} 25%, transparent)`
      };
    }
    if (item.urgencyCategory === 'tomorrow') {
      return {
        pillBg: 'rgba(168, 85, 247, 0.22)',
        pillBorder: 'rgba(168, 85, 247, 0.5)',
        pillText: '#d8b4fe',
        rowBorder: 'rgba(168, 85, 247, 0.28)',
        rowBg: 'rgba(168, 85, 247, 0.06)',
        glow: '0 0 20px rgba(168, 85, 247, 0.18)'
      };
    }
    
    const intensity = Math.min(item.overdueDays, 7);
    const redAlpha = 0.2 + (intensity * 0.04);
    const borderAlpha = 0.45 + (intensity * 0.06);
    return {
      pillBg: `rgba(244, 63, 94, ${redAlpha})`,
      pillBorder: `rgba(244, 63, 94, ${borderAlpha})`,
      pillText: intensity > 3 ? '#ff2a55' : '#fb7185',
      rowBorder: `rgba(244, 63, 94, ${0.28 + intensity * 0.05})`,
      rowBg: `rgba(244, 63, 94, ${0.06 + intensity * 0.02})`,
      glow: `0 0 ${16 + intensity * 3}px rgba(244, 63, 94, ${0.25 + intensity * 0.04})`
    };
  }
</script>

<div class="relative w-full select-none space-y-5 sm:space-y-6 box-border">

  <!-- HEADER -->
  <div class="flex items-center justify-between gap-3 pb-3 sm:pb-4 border-b border-[var(--border-subtle)] relative z-10 flex-wrap sm:flex-nowrap">
    <div class="flex items-center gap-3 min-w-0">
      <div class="relative w-10 h-10 rounded-2xl bg-[var(--bg-surface-elevated)] border border-[var(--border-subtle)] flex items-center justify-center shadow-inner overflow-hidden shrink-0">
        {#if overdueCount > 0}
          <div class="absolute inset-0 bg-rose-500/20 animate-pulse pointer-events-none"></div>
          <AlertTriangle size={18} class="text-rose-400 relative z-10 drop-shadow-[0_0_8px_rgba(244,63,94,0.6)]" />
        {:else if !hasTodayLog}
          <Clock size={18} class="text-amber-400 relative z-10 drop-shadow-[0_0_8px_rgba(251,191,36,0.6)]" />
        {:else}
          <div class="absolute inset-0 pointer-events-none" style="background-color: color-mix(in srgb, {vocabColor} 18%, transparent);"></div>
          <CheckCircle2 size={18} style="color: {vocabColor};" class="relative z-10 drop-shadow-[0_0_8px_{vocabColor}]" />
        {/if}
      </div>

      <div class="space-y-0.5 min-w-0">
        <div class="flex items-center gap-1.5">
          <h2 class="text-xs sm:text-sm font-black tracking-tight uppercase text-[var(--text-primary)] truncate">
            Today Tasks
          </h2>
          <span 
            class="inline-block w-1.5 h-1.5 rounded-full shrink-0"
            style="
              background-color: {hasTodayLog ? vocabColor : '#f59e0b'};
              box-shadow: 0 0 10px {hasTodayLog ? vocabColor : '#f59e0b'};
            "
            class:animate-pulse={!hasTodayLog}
          ></span>
        </div>
        <div class="flex items-center gap-2 text-[10px] font-mono text-[var(--text-muted)]">
          <span>{todayStr}</span>
          <span>•</span>
          <span class="font-bold text-[var(--text-secondary)]">{overallAveragePct}% Completed</span>
        </div>
      </div>
    </div>

    <!-- Status Badges -->
    <div class="flex items-center gap-2 shrink-0">
      {#if !hasTodayLog}
        <span class="inline-flex items-center gap-1.5 text-[10px] font-mono font-bold px-2.5 sm:px-3 py-1 rounded-full bg-amber-500/15 text-amber-400 border border-amber-500/35 shadow-[0_0_14px_rgba(245,158,11,0.25)]">
          <span class="w-1.5 h-1.5 rounded-full bg-amber-400 animate-ping"></span>
          Pending
        </span>
      {:else}
        <span 
          class="inline-flex items-center gap-1.5 text-[10px] font-mono font-bold px-2.5 sm:px-3 py-1 rounded-full border shadow-xs"
          style="
            background-color: color-mix(in srgb, {vocabColor} 16%, transparent);
            border-color: color-mix(in srgb, {vocabColor} 40%, transparent);
            color: {vocabColor};
            box-shadow: 0 0 14px color-mix(in srgb, {vocabColor} 30%, transparent);
          "
        >
          <span class="w-1.5 h-1.5 rounded-full" style="background-color: {vocabColor}; box-shadow: 0 0 8px {vocabColor};"></span>
          Logged
        </span>
      {/if}

      {#if overdueCount > 0}
        <span class="inline-flex items-center gap-1.5 text-[10px] font-mono font-bold px-2.5 sm:px-3 py-1 rounded-full bg-rose-500/20 text-rose-400 border border-rose-500/40 shadow-[0_0_16px_rgba(244,63,94,0.35)] animate-pulse">
          <span class="w-1.5 h-1.5 rounded-full bg-rose-400 shadow-[0_0_6px_#f43f5e]"></span>
          {overdueCount} Late
        </span>
      {/if}
    </div>
  </div>

  <!-- CONCENTRIC RINGS + FULL-WIDTH EXPANDED BARS -->
  <div class="flex flex-col 2xl:flex-row gap-5 sm:gap-6 items-center w-full relative z-10 box-border">
    
    <!-- Concentric Multi-Ring Hero -->
    <div class="shrink-0 flex items-center justify-center">
      <div class="relative w-44 h-44 sm:w-52 sm:h-52 flex items-center justify-center p-2 bg-[var(--bg-base)]/60 rounded-3xl border border-[var(--border-subtle)] shadow-inner group shrink-0">
        
        <!-- Ambient Radial Core Glow -->
        <div 
          class="absolute inset-4 rounded-full blur-md pointer-events-none transition-colors duration-300"
          style="background: radial-gradient(circle, color-mix(in srgb, {activeRingData ? activeRingData.color : themeColor} 20%, transparent) 0%, transparent 70%);"
        ></div>

        <svg class="w-full h-full -rotate-90 transform drop-shadow-md overflow-visible" viewBox="0 0 200 200">
          <defs>
            {#each concentricRings as ring (ring.id)}
              <filter id="glow-{ring.id}" x="-30%" y="-30%" width="160%" height="160%">
                <feGaussianBlur stdDeviation="2.5" result="blur" />
                <feComposite in="SourceGraphic" in2="blur" operator="over" />
              </filter>
            {/each}
          </defs>

          {#each concentricRings as ring (ring.id)}
            {@const circ = 2 * Math.PI * ring.radius}
            {@const offset = circ * (1 - Math.min(Math.max(ring.current / ring.target, 0), 1))}
            {@const isDimmed = hoveredRingId !== null && hoveredRingId !== ring.id}
            {@const isFocused = hoveredRingId === ring.id}

            <!-- Background Track -->
            <circle
              cx="100"
              cy="100"
              r={ring.radius}
              stroke="currentColor"
              stroke-width={ring.stroke}
              fill="none"
              class="text-[var(--border-subtle)] transition-opacity duration-200 cursor-pointer pointer-events-auto {isDimmed ? 'opacity-10' : 'opacity-25'}"
              role="presentation"
              onmouseenter={() => (hoveredRingId = ring.id)}
              onmouseleave={() => (hoveredRingId = null)}
            />

            <!-- Active Glowing Ring -->
            <circle
              cx="100"
              cy="100"
              r={ring.radius}
              stroke={ring.color}
              stroke-width={isFocused ? ring.stroke + 2 : ring.stroke}
              stroke-linecap="round"
              fill="none"
              stroke-dasharray={circ}
              stroke-dashoffset={offset}
              filter={isFocused ? `url(#glow-${ring.id})` : undefined}
              class="transition-all duration-300 ease-out cursor-pointer pointer-events-auto {isDimmed ? 'opacity-20' : 'opacity-100'}"
              style="filter: drop-shadow(0 0 {isFocused ? '12px' : '4px'} {ring.color});"
              role="presentation"
              onmouseenter={() => (hoveredRingId = ring.id)}
              onmouseleave={() => (hoveredRingId = null)}
            />
          {/each}
        </svg>

        <!-- Dynamic Reactive Center Counter -->
        <div class="absolute inset-0 flex flex-col items-center justify-center pointer-events-none text-center">
          {#if activeRingData}
            <span class="text-2xl sm:text-3xl font-black font-mono tracking-tight leading-none animate-in fade-in zoom-in-95 duration-150" style="color: {activeRingData.color};">
              {activeRingData.pct}<span class="text-xs font-bold ml-0.5 opacity-80">%</span>
            </span>
            <span class="text-[9px] font-mono uppercase tracking-widest text-[var(--text-secondary)] mt-1 font-bold truncate max-w-[85px]">
              {activeRingData.title}
            </span>
          {:else}
            <span class="text-2xl sm:text-3xl font-black font-mono tracking-tight leading-none text-[var(--text-primary)]">
              {overallAveragePct}<span class="text-xs font-bold ml-0.5" style="color: {themeColor};">%</span>
            </span>
            <span class="text-[9px] font-mono uppercase tracking-widest text-[var(--text-muted)] mt-1 font-bold">
              Goals
            </span>
          {/if}
        </div>
      </div>
    </div>

    <!-- Right Side: Habit Tracks -->
    <div class="flex-1 w-full min-w-0 flex flex-col gap-2 sm:gap-2.5 box-border">
      {#each concentricRings as ring (ring.id)}
        {@const pct = getPct(ring.current, ring.target)}
        {@const IconComp = ring.icon}
        {@const isHovered = hoveredRingId === ring.id}

        <div class="relative w-full">
          <div 
            class="pointer-events-none absolute -inset-x-6 -inset-y-4 rounded-3xl blur-2xl opacity-0 transition-opacity duration-300 -z-10"
            style="
              background: radial-gradient(ellipse at center, {ring.color} 0%, transparent 75%);
              opacity: {isHovered ? 0.38 : 0};
            "
          ></div>

          <div 
            role="presentation"
            title={ring.title}
            onmouseenter={() => (hoveredRingId = ring.id)}
            onmouseleave={() => (hoveredRingId = null)}
            class="group relative flex items-center justify-between gap-3 sm:gap-4 px-3 sm:px-4 py-2 sm:py-2.5 rounded-2xl border transition-all duration-200 w-full min-w-0 box-border cursor-default {isHovered 
              ? 'bg-[var(--bg-surface-elevated)] border-[var(--border-hover)] shadow-sm -translate-y-0.5' 
              : 'bg-[var(--bg-base)]/80 border-[var(--border-subtle)] hover:bg-[var(--bg-surface-elevated)]'}"
          >
            <div 
              class="absolute left-0 top-2 bottom-2 w-1 rounded-r-full transition-all duration-200"
              style="background-color: {isHovered ? ring.color : 'transparent'}; box-shadow: {isHovered ? `0 0 12px ${ring.color}` : 'none'};"
            ></div>

            <div 
              class="w-8 h-8 rounded-xl flex items-center justify-center shrink-0 border transition-transform duration-200 {isHovered ? 'scale-110 shadow-sm' : ''}"
              style="
                background-color: color-mix(in srgb, {ring.color} 18%, transparent);
                border-color: color-mix(in srgb, {ring.color} 38%, transparent);
                color: {ring.color};
                box-shadow: {isHovered ? `0 0 14px color-mix(in srgb, ${ring.color} 35%, transparent)` : 'none'};
              "
            >
              <IconComp size={15} strokeWidth={2.5} />
            </div>

            <div class="flex-1 min-w-[60px] h-2.5 sm:h-3 rounded-full bg-[var(--bg-surface)] border border-[var(--border-subtle)] overflow-hidden p-[1px] relative">
              <div 
                class="h-full rounded-full transition-all duration-500 relative"
                style="
                  width: {pct}%; 
                  background: linear-gradient(90deg, {ring.color}, {ring.colorSub});
                  box-shadow: 0 0 {isHovered ? '16px' : '9px'} {ring.color}90;
                "
              >
                {#if pct > 0}
                  <div class="absolute right-0 top-0 bottom-0 w-2 bg-white/90 rounded-full shadow-[0_0_8px_#fff]"></div>
                {/if}
              </div>
            </div>

            <div class="text-right font-mono text-xs sm:text-sm shrink-0 min-w-[60px]">
              <span class="font-black" style="color: {ring.color};">{ring.current}{ring.unit}</span>
              <span class="text-[var(--text-muted)] font-medium">/{ring.target}{ring.unit}</span>
            </div>

          </div>
        </div>
      {/each}
    </div>

  </div>

  <!-- 🌟 TRI-DECK SRS REVIEW QUEUE BANNER (Vision, Listen, Write) 🌟 -->
  <div class="relative flex items-center justify-between p-3.5 sm:p-4 rounded-2xl border border-[var(--border-card)] bg-[var(--bg-surface-elevated)]/60 shadow-xs backdrop-blur-xs overflow-hidden group box-border">
    
    <div 
      class="absolute left-0 top-0 bottom-0 w-1 opacity-80 group-hover:opacity-100 transition-opacity"
      style="background-color: {flashcardColor}; box-shadow: 0 0 14px {flashcardColor};"
    ></div>

    <div class="flex items-center gap-3 sm:gap-3.5 pl-1.5 min-w-0">
      <div 
        class="w-9 h-9 sm:w-10 sm:h-10 rounded-2xl flex items-center justify-center border shadow-xs transition-transform duration-200 group-hover:scale-105 shrink-0"
        style="
          background-color: color-mix(in srgb, {flashcardColor} 16%, transparent);
          border-color: color-mix(in srgb, {flashcardColor} 35%, transparent);
          color: {flashcardColor};
          box-shadow: 0 0 12px color-mix(in srgb, {flashcardColor} 20%, transparent);
        "
      >
        <Flame size={18} strokeWidth={2.5} class="group-hover:animate-bounce" />
      </div>

      <div class="space-y-0.5 min-w-0">
        <span class="text-xs font-bold text-[var(--text-primary)] block truncate">
          SRS Queue Status
        </span>
      </div>
    </div>

    <!-- Tri-Deck Due Metrics -->
    <div class="flex items-center gap-2 sm:gap-2.5 shrink-0 ml-2">
      {#if srsCounts.totalDue === 0}
        <div 
          class="inline-flex items-center gap-1.5 px-2.5 sm:px-3 py-1 rounded-full border text-[10px] font-mono font-bold uppercase tracking-wider shadow-xs"
          style="
            background-color: color-mix(in srgb, {vocabColor} 14%, transparent);
            border-color: color-mix(in srgb, {vocabColor} 35%, transparent);
            color: {vocabColor};
            box-shadow: 0 0 12px color-mix(in srgb, {vocabColor} 20%, transparent);
          "
        >
          <CheckCircle2 size={12} />
          <span>Queue Clear</span>
        </div>
      {:else}
        <!-- 1. Vision SRS Count (Formerly 'vis') -->
        <div 
          class="flex items-center gap-1.5 px-2 sm:px-2.5 py-1 rounded-xl border shadow-2xs"
          style="
            background-color: color-mix(in srgb, {flashcardColor} 12%, transparent);
            border-color: color-mix(in srgb, {flashcardColor} 30%, transparent);
          "
          title="Visual Flashcards Due"
        >
          <Eye size={12} style="color: {flashcardColor};" />
          <span class="text-xs sm:text-sm font-mono font-black" style="color: {flashcardColor};">
            {srsCounts.visualDue}
          </span>
          <span class="text-[9px] font-mono font-bold lowercase text-[var(--text-muted)] hidden sm:inline">
            vision
          </span>
        </div>

        <!-- 2. Listen SRS Count (Formerly 'ear') -->
        <div 
          class="flex items-center gap-1.5 px-2 sm:px-2.5 py-1 rounded-xl border shadow-2xs"
          style="
            background-color: color-mix(in srgb, {audioColor} 12%, transparent);
            border-color: color-mix(in srgb, {audioColor} 30%, transparent);
          "
          title="Listening / Ear Training Due"
        >
          <Headphones size={12} style="color: {audioColor};" />
          <span class="text-xs sm:text-sm font-mono font-black" style="color: {audioColor};">
            {srsCounts.audioDue}
          </span>
          <span class="text-[9px] font-mono font-bold lowercase text-[var(--text-muted)] hidden sm:inline">
            listen
          </span>
        </div>

        <!-- 3. Write SRS Count -->
        <div 
          class="flex items-center gap-1.5 px-2 sm:px-2.5 py-1 rounded-xl border shadow-2xs"
          style="
            background-color: color-mix(in srgb, {writingColor} 12%, transparent);
            border-color: color-mix(in srgb, {writingColor} 30%, transparent);
          "
          title="Motor & Stroke Calligraphy Due"
        >
          <PenTool size={12} style="color: {writingColor};" />
          <span class="text-xs sm:text-sm font-mono font-black" style="color: {writingColor};">
            {srsCounts.writingDue}
          </span>
          <span class="text-[9px] font-mono font-bold lowercase text-[var(--text-muted)] hidden sm:inline">
            write
          </span>
        </div>
      {/if}
    </div>
  </div>

  <!-- MONOSPACE SCHEDULED QUEUE -->
  <div class="pt-2 border-t border-[var(--border-subtle)] space-y-2 box-border relative">
    <div class="flex items-center justify-between px-1 mb-1">
      <span class="text-[10px] font-bold uppercase tracking-wider text-[var(--text-muted)]">
        Scheduled Queue
      </span>
      <span class="text-[10px] font-mono text-[var(--text-muted)]">
        {scheduledActionItems.length + (!hasTodayLog ? 1 : 0)} actions
      </span>
    </div>

    <!-- Initialize Today Action Card -->
    {#if !hasTodayLog}
      <div class="relative w-full">
        <div 
          class="pointer-events-none absolute -inset-x-4 -inset-y-2 rounded-2xl blur-xl opacity-30 -z-10"
          style="background: radial-gradient(ellipse at center, rgba(245, 158, 11, 0.4) 0%, transparent 75%);"
        ></div>

        <button
          type="button"
          onclick={() => onSelectDate(todayStr)}
          class="group w-full flex items-center justify-between p-2.5 sm:p-3 rounded-2xl border border-amber-500/40 bg-gradient-to-r from-amber-500/15 via-amber-500/5 to-transparent hover:border-amber-500/70 transition-all duration-150 active:scale-[0.99] text-left cursor-pointer shadow-xs hover:shadow-[0_0_24px_rgba(245,158,11,0.25)] relative"
        >
          <div class="flex items-center gap-3 min-w-0">
            <div class="w-[76px] sm:w-[84px] shrink-0 text-center">
              <span class="block w-full text-[9px] sm:text-[10px] font-black font-mono px-2 py-0.5 rounded-md bg-amber-500/25 text-amber-300 border border-amber-500/40 uppercase tracking-wider shadow-xs">
                START
              </span>
            </div>

            <div class="flex items-center gap-2 truncate">
              <Calendar size={13} class="text-amber-400 shrink-0" />
              <span class="font-mono text-xs sm:text-sm font-bold text-[var(--text-primary)] group-hover:text-amber-400 transition-colors">
                {todayStr}
              </span>
            </div>
          </div>

          <div class="flex items-center gap-1.5 text-xs font-mono font-bold text-amber-400 group-hover:translate-x-1 transition-transform shrink-0 ml-2">
            <span class="hidden sm:inline">Open</span>
            <ArrowRight size={14} />
          </div>
        </button>
      </div>
    {/if}

    <!-- Scheduled Action Items -->
    {#each scheduledActionItems as item (item.date)}
      {@const styles = getUrgencyStyles(item)}
      <div class="relative w-full">
        <div 
          class="pointer-events-none absolute -inset-x-4 -inset-y-2 rounded-2xl blur-xl opacity-35 transition-opacity duration-200 -z-10"
          style="background: radial-gradient(ellipse at center, {styles.pillText} 0%, transparent 75%);"
        ></div>

        <button
          type="button"
          onclick={() => onSelectDate(item.date)}
          class="group w-full flex items-center justify-between p-2.5 sm:p-3 rounded-2xl border transition-all duration-150 active:scale-[0.99] text-left cursor-pointer shadow-xs hover:scale-[1.005] relative"
          style="
            border-color: {styles.rowBorder};
            background-color: {styles.rowBg};
            box-shadow: {styles.glow};
          "
        >
          <div class="flex items-center gap-3 min-w-0 flex-1">
            <div class="w-[76px] sm:w-[84px] shrink-0 text-center">
              <span 
                class="block w-full text-[9px] sm:text-[10px] font-black font-mono px-1.5 py-0.5 rounded-md uppercase tracking-wider border truncate shadow-xs"
                style="
                  background-color: {styles.pillBg};
                  border-color: {styles.pillBorder};
                  color: {styles.pillText};
                "
              >
                {item.statusLabel}
              </span>
            </div>

            <div class="flex items-center gap-2 min-w-0 truncate">
              <Calendar size={13} class="text-[var(--text-muted)] shrink-0 group-hover:text-[var(--text-primary)] transition-colors" />
              <span class="font-mono text-xs sm:text-sm font-bold text-[var(--text-primary)] tracking-wide truncate">
                {item.date}
              </span>
            </div>
          </div>

          <div class="flex items-center gap-2 shrink-0 ml-2">
            <div 
              class="flex items-center justify-center gap-1.5 px-2.5 py-1 rounded-xl font-mono text-[10px] tracking-tight border border-black/25 dark:border-white/[0.08] bg-black/[0.06] dark:bg-black/50 shadow-[inset_0_2px_4px_rgba(0,0,0,0.4),0_1px_0_rgba(255,255,255,0.06)] backdrop-blur-sm"
            >
              <span class="text-[9px] font-extrabold text-[var(--text-muted)] opacity-60 tracking-widest uppercase">
                revision
              </span>
              <span class="w-[1px] h-2.5 bg-black/20 dark:bg-white/10"></span>
              <span class="font-black text-xs text-[var(--text-primary)] tabular-nums">
                {String(item.revision).padStart(2, '0')}
              </span>
            </div>

            <ArrowRight size={13} class="text-[var(--text-muted)] group-hover:text-[var(--text-primary)] group-hover:translate-x-1 transition-transform" />
          </div>
        </button>
      </div>
    {/each}

    {#if hasTodayLog && scheduledActionItems.length === 0}
      <div class="py-3 text-center text-xs text-[var(--text-muted)] flex items-center justify-center gap-2 font-medium">
        <Sparkles size={14} style="color: {vocabColor};" />
        <span>All sessions reviewed and targets up to date for today</span>
      </div>
    {/if}
  </div>

</div>