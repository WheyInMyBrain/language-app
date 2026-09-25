<!-- frontend/src/components/DashboardMetrics.svelte -->
<script>
  import { metadataStore } from '../lib/stores/metadata.svelte.js';
  import { activeLanguage } from '../lib/stores/activeLanguage.svelte.js';
  import { 
    formatHoursMins, 
    calculateMedian, 
    calculateETA 
  } from '../lib/stats.js';

  // D3 Scales & Curve Generators
  import { scaleTime, scaleLinear } from 'd3-scale';
  import { line, area, curveMonotoneX } from 'd3-shape';

  // Vector Icons
  import { 
    TrendingUp, 
    Calendar, 
    Flame, 
    BookOpen, 
    Headphones, 
    Mic, 
    Play, 
    Layers, 
    Sparkles 
  } from '@lucide/svelte';

  let currentLang = $derived(metadataStore.currentLanguageData || {});
  let entries = $derived(metadataStore.sortedCalendarEntries || []);
  let milestones = $derived(activeLanguage.milestones || {});
  let colors = $derived(activeLanguage.colors || {});

  let activeChartTab = $state('vocab'); // 'vocab' | 'listening' | 'speaking'
  let activeHeatmapTab = $state('vocab'); // 'vocab' | 'listening' | 'speaking'
  let inspectedDay = $state(null);
  let hoveredPoint = $state(null);

  // 1. Core Aggregate Totals
  let aggregates = $derived.by(() => {
    let vocab = 0, grammar = 0, ci = 0, listeningSec = 0, speakingSec = 0;
    for (let i = 0; i < entries.length; i++) {
      const e = entries[i];
      vocab += e.word || 0;
      grammar += e.grammar || 0;
      ci += e.ci || 0;
      listeningSec += e.listening_time || 0;
      speakingSec += e.speaking_time || 0;
    }
    return {
      streak: currentLang.current_streak || 0,
      vocab, grammar, ci, listeningSec, speakingSec
    };
  });

  // 2. Active Theme Color Resolvers
  let chartColor = $derived.by(() => {
    if (activeChartTab === 'vocab') return colors.vocab?.dark_primary || colors.vocab?.primary || '#10b981';
    if (activeChartTab === 'listening') return colors.listening?.dark_primary || colors.listening?.primary || '#f97316';
    return colors.speaking?.dark_primary || colors.speaking?.primary || '#a855f7';
  });

  let chartColorSub = $derived.by(() => {
    if (activeChartTab === 'vocab') return colors.vocab?.light_primary || '#34d399';
    if (activeChartTab === 'listening') return colors.listening?.light_primary || '#fb923c';
    return colors.speaking?.light_primary || '#c084fc';
  });

  let heatmapColor = $derived.by(() => {
    if (activeHeatmapTab === 'vocab') return colors.vocab?.dark_primary || colors.vocab?.primary || '#10b981';
    if (activeHeatmapTab === 'listening') return colors.listening?.dark_primary || colors.listening?.primary || '#f97316';
    return colors.speaking?.dark_primary || colors.speaking?.primary || '#a855f7';
  });

  let heatmapColorSub = $derived.by(() => {
    if (activeHeatmapTab === 'vocab') return colors.vocab?.light_primary || '#34d399';
    if (activeHeatmapTab === 'listening') return colors.listening?.light_primary || '#fb923c';
    return colors.speaking?.light_primary || '#c084fc';
  });

  // 3. Milestones with ETA Forecasts
  let milestoneStats = $derived.by(() => {
    const vocabDailies = [], listenDailies = [], speakDailies = [];
    for (let i = 0; i < entries.length; i++) {
      const e = entries[i];
      if (e.word > 0) vocabDailies.push(e.word);
      if (e.listening_time > 0) listenDailies.push(e.listening_time);
      if (e.speaking_time > 0) speakDailies.push(e.speaking_time);
    }

    const listTargetSec = (milestones.listening_hours || 48) * 3600;
    const speakTargetSec = (milestones.speaking_hours || 12) * 3600;
    const vocabTarget = milestones.vocab_total || 1000;

    return [
      {
        id: 'vocab',
        title: 'Vocabulary Acquisition',
        icon: BookOpen,
        color: colors.vocab?.dark_primary || colors.vocab?.primary || '#10b981',
        pct: Math.min(100, Math.round((aggregates.vocab / vocabTarget) * 100)),
        formattedTarget: vocabTarget.toLocaleString() + ' words',
        eta: calculateETA(aggregates.vocab, vocabTarget, calculateMedian(vocabDailies), false)
      },
      {
        id: 'listening',
        title: 'Immersion Audio',
        icon: Headphones,
        color: colors.listening?.dark_primary || colors.listening?.primary || '#f97316',
        pct: Math.min(100, Math.round((aggregates.listeningSec / listTargetSec) * 100)),
        formattedTarget: `${milestones.listening_hours || 48}h logged`,
        eta: calculateETA(aggregates.listeningSec, listTargetSec, calculateMedian(listenDailies), true)
      },
      {
        id: 'speaking',
        title: 'Speaking Production',
        icon: Mic,
        color: colors.speaking?.dark_primary || colors.speaking?.primary || '#a855f7',
        pct: Math.min(100, Math.round((aggregates.speakingSec / speakTargetSec) * 100)),
        formattedTarget: `${milestones.speaking_hours || 12}h logged`,
        eta: calculateETA(aggregates.speakingSec, speakTargetSec, calculateMedian(speakDailies), true)
      }
    ];
  });

  // 4. D3 Math Engine
  const WIDTH = 480;
  const HEIGHT = 180;
  const MARGIN = { top: 24, right: 16, bottom: 28, left: 16 };

  let chartModel = $derived.by(() => {
    if (entries.length === 0) return null;

    const asc = [...entries].reverse();
    let running = 0;
    const data = [];

    for (let i = 0; i < asc.length; i++) {
      if (activeChartTab === 'vocab') {
        running += asc[i].word || 0;
      } else if (activeChartTab === 'listening') {
        running += (asc[i].listening_time || 0) / 3600;
      } else {
        running += (asc[i].speaking_time || 0) / 3600;
      }
      data.push({
        dateStr: asc[i].date,
        date: new Date(asc[i].date),
        value: running
      });
    }

    const peak = data[data.length - 1]?.value || 1;
    const maxVal = Math.max(
      activeChartTab === 'vocab' ? 10 : 1, 
      Math.ceil(peak * 1.15)
    );

    const xScale = scaleTime()
      .domain([data[0].date, data[data.length - 1].date])
      .range([MARGIN.left, WIDTH - MARGIN.right]);

    const yScale = scaleLinear()
      .domain([0, maxVal])
      .range([HEIGHT - MARGIN.bottom, MARGIN.top]);

    const lineGen = line()
      .x(d => xScale(d.date))
      .y(d => yScale(d.value))
      .curve(curveMonotoneX);

    const areaGen = area()
      .x(d => xScale(d.date))
      .y0(HEIGHT - MARGIN.bottom)
      .y1(d => yScale(d.value))
      .curve(curveMonotoneX);

    const linePath = lineGen(data);
    const areaPath = areaGen(data);

    const points = data.map(d => ({
      ...d,
      x: xScale(d.date),
      y: yScale(d.value)
    }));

    return {
      points,
      linePath,
      areaPath,
      maxVal: activeChartTab === 'vocab' ? Math.round(maxVal) : maxVal.toFixed(1),
      midVal: activeChartTab === 'vocab' ? Math.round(maxVal / 2) : (maxVal / 2).toFixed(1),
      startDate: data[0]?.dateStr.slice(5),
      endDate: data[data.length - 1]?.dateStr.slice(5),
      currentTotal: data[data.length - 1]?.value || 0
    };
  });

  // Fast cursor tracking lookup
  function handlePointerMove(e) {
    if (!chartModel?.points?.length) return;
    const rect = e.currentTarget.getBoundingClientRect();
    const clientX = e.clientX ?? e.touches?.[0]?.clientX;
    if (clientX === undefined) return;

    const svgX = ((clientX - rect.left) / rect.width) * WIDTH;

    let closest = chartModel.points[0];
    let minDiff = Infinity;
    const pts = chartModel.points;
    for (let i = 0; i < pts.length; i++) {
      const diff = Math.abs(pts[i].x - svgX);
      if (diff < minDiff) {
        minDiff = diff;
        closest = pts[i];
      }
    }
    hoveredPoint = closest;
  }

  // 5. Heatmap Matrix
  function toLocalDateStr(d) {
    const year = d.getFullYear();
    const month = String(d.getMonth() + 1).padStart(2, '0');
    const day = String(d.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
  }

  function formatTileTime(sec) {
    if (!sec || sec <= 0) return '0s';
    if (sec < 60) return `${sec}s`;
    const mins = Math.round(sec / 60);
    return `${mins}m`;
  }

  let heatmapWeeks = $derived.by(() => {
    const today = new Date();
    today.setHours(0, 0, 0, 0);

    const logMap = new Map();
    for (let i = 0; i < entries.length; i++) {
      logMap.set(entries[i].date, entries[i]);
    }

    const goals = activeLanguage.goals || {};
    const vocabGoal = goals.vocab || 20;
    const listenGoalSec = (goals.listening_minutes || goals.listening || 45) * 60;
    const speakGoalSec = (goals.speaking_minutes || goals.speaking || 10) * 60;

    function calculateTier(value, target) {
      if (!value || value <= 0) return 0;
      if (value >= target) return 4;
      if (value >= target * 0.75) return 3;
      if (value >= target * 0.50) return 2;
      return 1;
    }

    const start = new Date(today);
    start.setDate(today.getDate() - (13 * 7 - 1));

    const weeks = [];
    for (let w = 0; w < 13; w++) {
      const days = [];
      for (let d = 0; d < 7; d++) {
        const cur = new Date(start);
        cur.setDate(start.getDate() + (w * 7 + d));
        const dt = toLocalDateStr(cur);
        const log = logMap.get(dt);

        const wCount = log?.word || 0;
        const lSec = log?.listening_time || 0;
        const sSec = log?.speaking_time || 0;

        let level = 0;
        let label = 'No activity logged';

        if (activeHeatmapTab === 'vocab') {
          level = calculateTier(wCount, vocabGoal);
          if (wCount > 0) label = `${wCount} / ${vocabGoal} words`;
        } else if (activeHeatmapTab === 'listening') {
          level = calculateTier(lSec, listenGoalSec);
          if (lSec > 0) label = `${formatTileTime(lSec)} / ${Math.round(listenGoalSec / 60)}m audio`;
        } else {
          level = calculateTier(sSec, speakGoalSec);
          if (sSec > 0) label = `${formatTileTime(sSec)} / ${Math.round(speakGoalSec / 60)}m speech`;
        }

        days.push({ date: dt, level, label });
      }
      weeks.push(days);
    }
    return weeks;
  });

  function getHeatmapBg(level, baseColor) {
    if (level === 0) return 'var(--bg-base)';
    if (level === 1) return `color-mix(in srgb, ${baseColor} 30%, var(--bg-surface))`;
    if (level === 2) return `color-mix(in srgb, ${baseColor} 55%, var(--bg-surface))`;
    if (level === 3) return `color-mix(in srgb, ${baseColor} 80%, var(--bg-surface))`;
    return baseColor;
  }
</script>

<div class="relative w-full space-y-6 pt-2 select-none box-border" style="contain: style;">
  
  <!-- SECTION DIVIDER -->
  <div class="flex items-center gap-3">
    <div class="flex-1 h-px bg-gradient-to-r from-transparent via-[var(--border-subtle)] to-transparent"></div>
    <div class="flex items-center gap-2 px-3 py-1 rounded-full bg-[var(--bg-surface)] border border-[var(--border-subtle)] shadow-xs">
      <Sparkles size={11} class="text-[var(--accent)]" />
      <span class="text-[10px] font-mono font-bold uppercase tracking-widest text-[var(--text-muted)]">
        Milestones & Trajectory
      </span>
    </div>
    <div class="flex-1 h-px bg-gradient-to-r from-transparent via-[var(--border-subtle)] to-transparent"></div>
  </div>

  <!-- ADAPTIVE METRIC TELEMETRY TILES -->
  <div class="grid grid-cols-2 sm:grid-cols-3 xl:grid-cols-6 gap-2 sm:gap-2.5 w-full box-border">
    <!-- Streak -->
    <div class="group relative flex flex-col items-center justify-between p-3 sm:p-3.5 rounded-2xl border border-[var(--border-card)] bg-[var(--bg-surface)] hover:bg-[var(--bg-surface-elevated)] shadow-xs transition-transform duration-100 hover:-translate-y-0.5 hover:border-amber-500/40">
      <div class="flex items-center gap-1.5 text-[10px] font-bold uppercase tracking-wider text-[var(--text-muted)]">
        <Flame size={12} class="text-amber-500 fill-amber-500/20" />
        <span>Streak</span>
      </div>
      <div class="text-xl sm:text-2xl font-black font-mono text-amber-500 my-1">
        {aggregates.streak}<span class="text-xs text-[var(--text-muted)] font-bold ml-0.5">d</span>
      </div>
      <span class="text-[9px] font-mono font-bold text-[var(--text-muted)]">Active</span>
    </div>

    <!-- Vocab -->
    <div class="group relative flex flex-col items-center justify-between p-3 sm:p-3.5 rounded-2xl border border-[var(--border-card)] bg-[var(--bg-surface)] hover:bg-[var(--bg-surface-elevated)] shadow-xs transition-transform duration-100 hover:-translate-y-0.5 hover:border-emerald-500/40">
      <div class="flex items-center gap-1.5 text-[10px] font-bold uppercase tracking-wider text-[var(--text-muted)]">
        <BookOpen size={12} class="text-emerald-500" />
        <span>Vocab</span>
      </div>
      <div class="text-xl sm:text-2xl font-black font-mono my-1" style="color: {colors.vocab?.dark_primary || colors.vocab?.primary || '#10b981'};">
        {aggregates.vocab}
      </div>
      <span class="text-[9px] font-mono font-bold text-[var(--text-muted)]">Words</span>
    </div>

    <!-- Grammar -->
    <div class="group relative flex flex-col items-center justify-between p-3 sm:p-3.5 rounded-2xl border border-[var(--border-card)] bg-[var(--bg-surface)] hover:bg-[var(--bg-surface-elevated)] shadow-xs transition-transform duration-100 hover:-translate-y-0.5 hover:border-sky-500/40">
      <div class="flex items-center gap-1.5 text-[10px] font-bold uppercase tracking-wider text-[var(--text-muted)]">
        <Layers size={12} class="text-sky-400" />
        <span>Grammar</span>
      </div>
      <div class="text-xl sm:text-2xl font-black font-mono my-1" style="color: {colors.grammar?.dark_primary || colors.grammar?.primary || '#0284c7'};">
        {aggregates.grammar}
      </div>
      <span class="text-[9px] font-mono font-bold text-[var(--text-muted)]">Patterns</span>
    </div>

    <!-- CI Video -->
    <div class="group relative flex flex-col items-center justify-between p-3 sm:p-3.5 rounded-2xl border border-[var(--border-card)] bg-[var(--bg-surface)] hover:bg-[var(--bg-surface-elevated)] shadow-xs transition-transform duration-100 hover:-translate-y-0.5 hover:border-purple-500/40">
      <div class="flex items-center gap-1.5 text-[10px] font-bold uppercase tracking-wider text-[var(--text-muted)]">
        <Play size={12} class="text-purple-400" />
        <span>CI Video</span>
      </div>
      <div class="text-xl sm:text-2xl font-black font-mono my-1" style="color: {colors.ci?.dark_primary || colors.ci?.primary || '#9333ea'};">
        {aggregates.ci}
      </div>
      <span class="text-[9px] font-mono font-bold text-[var(--text-muted)]">Episodes</span>
    </div>

    <!-- Listening -->
    <div class="group relative flex flex-col items-center justify-between p-3 sm:p-3.5 rounded-2xl border border-[var(--border-card)] bg-[var(--bg-surface)] hover:bg-[var(--bg-surface-elevated)] shadow-xs transition-transform duration-100 hover:-translate-y-0.5 hover:border-orange-500/40">
      <div class="flex items-center gap-1.5 text-[10px] font-bold uppercase tracking-wider text-[var(--text-muted)]">
        <Headphones size={12} class="text-orange-400" />
        <span>Listen</span>
      </div>
      <div class="text-sm sm:text-base font-black font-mono my-1 truncate max-w-full" style="color: {colors.listening?.dark_primary || colors.listening?.primary || '#f97316'};">
        {formatHoursMins(aggregates.listeningSec)}
      </div>
      <span class="text-[9px] font-mono font-bold text-[var(--text-muted)]">Time</span>
    </div>

    <!-- Speaking -->
    <div class="group relative flex flex-col items-center justify-between p-3 sm:p-3.5 rounded-2xl border border-[var(--border-card)] bg-[var(--bg-surface)] hover:bg-[var(--bg-surface-elevated)] shadow-xs transition-transform duration-100 hover:-translate-y-0.5 hover:border-pink-500/40">
      <div class="flex items-center gap-1.5 text-[10px] font-bold uppercase tracking-wider text-[var(--text-muted)]">
        <Mic size={12} class="text-pink-400" />
        <span>Speech</span>
      </div>
      <div class="text-sm sm:text-base font-black font-mono my-1 truncate max-w-full" style="color: {colors.speaking?.dark_primary || colors.speaking?.primary || '#a855f7'};">
        {formatHoursMins(aggregates.speakingSec)}
      </div>
      <span class="text-[9px] font-mono font-bold text-[var(--text-muted)]">Recorded</span>
    </div>
  </div>

  <!-- MILESTONES WITH LUMINESCENT PROGRESS BARS -->
  <div class="space-y-3">
    {#each milestoneStats as m (m.id)}
      {@const IconComp = m.icon}
      <div class="group relative p-3.5 sm:p-4 rounded-3xl border border-[var(--border-card)] bg-[var(--bg-surface)]/80 hover:bg-[var(--bg-surface-elevated)] shadow-xs space-y-2.5 transition-colors duration-150 hover:border-[var(--border-hover)]">
        
        <div class="flex items-center justify-between text-xs relative z-10 gap-2">
          <div class="flex items-center gap-2 font-bold text-[var(--text-primary)] min-w-0">
            <div 
              class="w-7 h-7 rounded-xl flex items-center justify-center shrink-0 border shadow-xs"
              style="background-color: {m.color}15; border-color: {m.color}35; color: {m.color};"
            >
              <IconComp size={13} strokeWidth={2.5} />
            </div>
            <span class="tracking-tight truncate">{m.title}</span>
          </div>

          <div class="flex items-center gap-1.5 sm:gap-2 shrink-0">
            <span 
              class="text-[9px] sm:text-[10px] font-mono font-black px-2 py-0.5 rounded-full border shadow-xs" 
              style="color: {m.color}; background-color: {m.color}15; border-color: {m.color}40; box-shadow: 0 0 10px {m.color}25;"
            >
              {m.eta.badge}
            </span>
            <span class="font-mono font-bold text-xs text-[var(--text-primary)]">
              {m.pct}%
            </span>
          </div>
        </div>

        <!-- Glowing Progress Track -->
        <div class="w-full h-2 sm:h-2.5 rounded-full bg-[var(--bg-base)] border border-[var(--border-subtle)] overflow-hidden p-[1px] relative z-10">
          <div
            class="h-full rounded-full transition-all duration-500 ease-out relative"
            style="width: {m.pct}%; background-color: {m.color}; box-shadow: 0 0 14px {m.color}90;"
          >
            {#if m.pct > 0}
              <div class="absolute right-0 top-0 bottom-0 w-2.5 bg-white/90 rounded-full shadow-[0_0_8px_#fff]"></div>
            {/if}
          </div>
        </div>

        <div class="flex items-center justify-between text-[10px] sm:text-[11px] font-mono text-[var(--text-muted)] pt-0.5 relative z-10 flex-wrap gap-1">
          <span>Pace: <strong class="text-[var(--text-secondary)]">{m.eta.pace}</strong> • Est: {m.eta.est}</span>
          <span class="font-bold text-[var(--text-secondary)]">Goal: {m.formattedTarget}</span>
        </div>

      </div>
    {/each}
  </div>

  <!-- SECTION 1: CUMULATIVE TRAJECTORY (ZERO-GPU AMBIENT GLASS) -->
  <div 
    class="relative p-4 sm:p-6 rounded-3xl border border-[var(--border-card)] shadow-md space-y-4 transition-colors duration-200"
    style="
      background-color: var(--bg-surface);
      background-image: radial-gradient(circle 320px at 0% 0%, {chartColor}18, transparent 100%);
    "
  >
    <!-- Header with Glass Toggle Pill -->
    <div class="flex items-center justify-between gap-2 sm:gap-3 relative z-10 flex-wrap">
      <div class="flex items-center gap-2.5">
        <div 
          class="w-7 h-7 rounded-xl flex items-center justify-center border shadow-xs transition-colors duration-200"
          style="background-color: {chartColor}15; border-color: {chartColor}35; color: {chartColor};"
        >
          <TrendingUp size={14} strokeWidth={2.5} />
        </div>
        <div>
          <span class="text-xs font-black text-[var(--text-primary)] uppercase tracking-wider block">
            Cumulative Trajectory
          </span>
          <span class="text-[9px] sm:text-[10px] font-mono text-[var(--text-muted)]">
            D3 Vector Monotone Projection
          </span>
        </div>
      </div>

      <!-- 🌟 VISIONOS LIQUID GLASS TAB TRENCH 🌟 -->
      <div class="flex items-center p-0.5 sm:p-1 rounded-2xl bg-white/50 dark:bg-white/[0.05] border border-black/[0.06] dark:border-white/[0.08] backdrop-blur-xl shadow-[inset_0_1px_2px_rgba(0,0,0,0.03)] gap-1">
        <button
          type="button"
          onclick={() => { activeChartTab = 'vocab'; hoveredPoint = null; }}
          class="group relative flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-[10px] sm:text-[11px] font-mono font-bold transition-all duration-150 cursor-pointer active:scale-95 {activeChartTab === 'vocab' 
            ? 'text-white shadow-xs' 
            : 'text-neutral-500 dark:text-white/50 hover:text-neutral-900 dark:hover:text-white hover:bg-black/[0.03] dark:hover:bg-white/[0.06]'}"
          style={activeChartTab === 'vocab' ? `background: linear-gradient(135deg, ${chartColor}, ${chartColorSub}); box-shadow: 0 2px 10px -2px ${chartColor};` : ''}
        >
          <span class="w-1.5 h-1.5 rounded-full {activeChartTab === 'vocab' ? 'bg-white shadow-[0_0_6px_#fff]' : 'bg-transparent'}"></span>
          <span>Vocab</span>
        </button>

        <button
          type="button"
          onclick={() => { activeChartTab = 'listening'; hoveredPoint = null; }}
          class="group relative flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-[10px] sm:text-[11px] font-mono font-bold transition-all duration-150 cursor-pointer active:scale-95 {activeChartTab === 'listening' 
            ? 'text-white shadow-xs' 
            : 'text-neutral-500 dark:text-white/50 hover:text-neutral-900 dark:hover:text-white hover:bg-black/[0.03] dark:hover:bg-white/[0.06]'}"
          style={activeChartTab === 'listening' ? `background: linear-gradient(135deg, ${chartColor}, ${chartColorSub}); box-shadow: 0 2px 10px -2px ${chartColor};` : ''}
        >
          <span class="w-1.5 h-1.5 rounded-full {activeChartTab === 'listening' ? 'bg-white shadow-[0_0_6px_#fff]' : 'bg-transparent'}"></span>
          <span>Listen</span>
        </button>

        <button
          type="button"
          onclick={() => { activeChartTab = 'speaking'; hoveredPoint = null; }}
          class="group relative flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-[10px] sm:text-[11px] font-mono font-bold transition-all duration-150 cursor-pointer active:scale-95 {activeChartTab === 'speaking' 
            ? 'text-white shadow-xs' 
            : 'text-neutral-500 dark:text-white/50 hover:text-neutral-900 dark:hover:text-white hover:bg-black/[0.03] dark:hover:bg-white/[0.06]'}"
          style={activeChartTab === 'speaking' ? `background: linear-gradient(135deg, ${chartColor}, ${chartColorSub}); box-shadow: 0 2px 10px -2px ${chartColor};` : ''}
        >
          <span class="w-1.5 h-1.5 rounded-full {activeChartTab === 'speaking' ? 'bg-white shadow-[0_0_6px_#fff]' : 'bg-transparent'}"></span>
          <span>Speak</span>
        </button>
      </div>
    </div>

    <!-- Scrubber Telemetry Capsule -->
    <div class="flex items-center justify-between px-3 sm:px-3.5 py-2 sm:py-2.5 rounded-2xl bg-white/40 dark:bg-black/30 border border-black/[0.06] dark:border-white/[0.08] backdrop-blur-md font-mono text-[10px] sm:text-[11px] relative z-10 shadow-inner">
      {#if hoveredPoint}
        <div class="flex items-center gap-1.5 sm:gap-2">
          <span class="w-1.5 h-1.5 rounded-full" style="background-color: {chartColor}; box-shadow: 0 0 6px {chartColor};"></span>
          <span class="text-[var(--text-muted)]">Session {hoveredPoint.dateStr}</span>
        </div>
        <span class="font-bold text-xs sm:text-sm" style="color: {chartColor};">
          {activeChartTab === 'vocab' ? `${hoveredPoint.value} words` : `${hoveredPoint.value.toFixed(1)} hrs`}
        </span>
      {:else}
        <span class="text-[var(--text-muted)]">Net Production</span>
        <span class="font-bold text-xs sm:text-sm" style="color: {chartColor};">
          {activeChartTab === 'vocab' ? `${Math.round(chartModel?.currentTotal || 0)} words` : `${(chartModel?.currentTotal || 0).toFixed(1)} hrs`}
        </span>
      {/if}
    </div>

    <!-- Responsive SVG Viewport -->
    <div class="w-full h-44 sm:h-48 relative z-10">
      {#if chartModel?.linePath}
        <svg 
          viewBox="0 0 {WIDTH} {HEIGHT}" 
          preserveAspectRatio="none"
          class="w-full h-full overflow-visible touch-none cursor-crosshair"
          role="application"
          aria-label="Interactive growth curve"
          onpointermove={handlePointerMove}
          onpointerleave={() => (hoveredPoint = null)}
        >
          <defs>
            <linearGradient id="neonGradient-{activeChartTab}" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stop-color={chartColor} stop-opacity="0.45" />
              <stop offset="60%" stop-color={chartColor} stop-opacity="0.08" />
              <stop offset="100%" stop-color={chartColor} stop-opacity="0.0" />
            </linearGradient>

            <filter id="neonFilter-{activeChartTab}" x="-20%" y="-20%" width="140%" height="140%">
              <feGaussianBlur stdDeviation="3.5" result="blur" />
              <feMerge>
                <feMergeNode in="blur" />
                <feMergeNode in="SourceGraphic" />
              </feMerge>
            </filter>
          </defs>

          <!-- Grid Lines -->
          <line x1={MARGIN.left} y1={MARGIN.top} x2={WIDTH - MARGIN.right} y2={MARGIN.top} stroke="var(--border-card)" stroke-dasharray="2 3" opacity="0.35" />
          <text x={MARGIN.left + 2} y={MARGIN.top - 4} fill="var(--text-muted)" font-size="8" font-family="monospace" opacity="0.8">{chartModel.maxVal}</text>

          <line x1={MARGIN.left} y1={MARGIN.top + (HEIGHT - MARGIN.top - MARGIN.bottom) / 2} x2={WIDTH - MARGIN.right} y2={MARGIN.top + (HEIGHT - MARGIN.top - MARGIN.bottom) / 2} stroke="var(--border-card)" stroke-dasharray="2 3" opacity="0.2" />
          <text x={MARGIN.left + 2} y={MARGIN.top + (HEIGHT - MARGIN.top - MARGIN.bottom) / 2 - 4} fill="var(--text-muted)" font-size="8" font-family="monospace" opacity="0.6">{chartModel.midVal}</text>

          <line x1={MARGIN.left} y1={HEIGHT - MARGIN.bottom} x2={WIDTH - MARGIN.right} y2={HEIGHT - MARGIN.bottom} stroke="var(--border-card)" opacity="0.7" />

          <!-- X Dates -->
          <text x={MARGIN.left} y={HEIGHT - 8} fill="var(--text-muted)" font-size="8" font-family="monospace">{chartModel.startDate}</text>
          <text x={WIDTH - MARGIN.right} y={HEIGHT - 8} fill="var(--text-muted)" font-size="8" font-family="monospace" text-anchor="end">{chartModel.endDate}</text>

          <!-- Area Fill -->
          <path d={chartModel.areaPath} fill="url(#neonGradient-{activeChartTab})" />

          <!-- Main Neon Line -->
          <path 
            d={chartModel.linePath} 
            fill="none" 
            stroke={chartColor} 
            stroke-width="2.6" 
            stroke-linecap="round" 
            stroke-linejoin="round" 
            filter="url(#neonFilter-{activeChartTab})"
          />

          <!-- Laser Crosshair -->
          {#if hoveredPoint}
            <line 
              x1={hoveredPoint.x} 
              y1={MARGIN.top} 
              x2={hoveredPoint.x} 
              y2={HEIGHT - MARGIN.bottom} 
              stroke={chartColor} 
              stroke-width="1.5" 
              stroke-dasharray="3 3" 
            />
            <circle 
              cx={hoveredPoint.x} 
              cy={hoveredPoint.y} 
              r="5" 
              fill="var(--bg-surface)" 
              stroke={chartColor} 
              stroke-width="2.5" 
              style="filter: drop-shadow(0 0 8px {chartColor});"
            />
            <circle 
              cx={hoveredPoint.x} 
              cy={hoveredPoint.y} 
              r="2" 
              fill="#ffffff" 
            />
          {/if}
        </svg>
      {:else}
        <div class="w-full h-full flex items-center justify-center text-xs text-[var(--text-muted)] italic">
          No records logged to plot trajectory
        </div>
      {/if}
    </div>
  </div>

  <!-- SECTION 2: 90-DAY ACTIVITY GRID (TOUCH-SCROLL OPTIMIZED) -->
  <div 
    class="relative p-4 sm:p-6 rounded-3xl border border-[var(--border-card)] shadow-md space-y-4 transition-colors duration-200"
    style="
      background-color: var(--bg-surface);
      background-image: radial-gradient(circle 320px at 100% 100%, {heatmapColor}18, transparent 100%);
    "
  >
    <!-- Header with Glass Toggle Pill -->
    <div class="flex items-center justify-between gap-2 sm:gap-3 relative z-10 flex-wrap">
      <div class="flex items-center gap-2.5">
        <div 
          class="w-7 h-7 rounded-xl flex items-center justify-center border shadow-xs transition-colors duration-200"
          style="background-color: {heatmapColor}15; border-color: {heatmapColor}35; color: {heatmapColor};"
        >
          <Calendar size={14} strokeWidth={2.5} />
        </div>
        <div>
          <span class="text-xs font-black text-[var(--text-primary)] uppercase tracking-wider block">
            Consistency Matrix
          </span>
          <span class="text-[9px] sm:text-[10px] font-mono text-[var(--text-muted)]">
            Past 13 Weeks Daily Breakdown
          </span>
        </div>
      </div>

      <!-- 🌟 VISIONOS LIQUID GLASS TAB TRENCH 🌟 -->
      <div class="flex items-center p-0.5 sm:p-1 rounded-2xl bg-white/50 dark:bg-white/[0.05] border border-black/[0.06] dark:border-white/[0.08] backdrop-blur-xl shadow-[inset_0_1px_2px_rgba(0,0,0,0.03)] gap-1">
        <button
          type="button"
          onclick={() => { activeHeatmapTab = 'vocab'; inspectedDay = null; }}
          class="group relative flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-[10px] sm:text-[11px] font-mono font-bold transition-all duration-150 cursor-pointer active:scale-95 {activeHeatmapTab === 'vocab' 
            ? 'text-white shadow-xs' 
            : 'text-neutral-500 dark:text-white/50 hover:text-neutral-900 dark:hover:text-white hover:bg-black/[0.03] dark:hover:bg-white/[0.06]'}"
          style={activeHeatmapTab === 'vocab' ? `background: linear-gradient(135deg, ${heatmapColor}, ${heatmapColorSub}); box-shadow: 0 2px 10px -2px ${heatmapColor};` : ''}
        >
          <span class="w-1.5 h-1.5 rounded-full {activeHeatmapTab === 'vocab' ? 'bg-white shadow-[0_0_6px_#fff]' : 'bg-transparent'}"></span>
          <span>Vocab</span>
        </button>

        <button
          type="button"
          onclick={() => { activeHeatmapTab = 'listening'; inspectedDay = null; }}
          class="group relative flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-[10px] sm:text-[11px] font-mono font-bold transition-all duration-150 cursor-pointer active:scale-95 {activeHeatmapTab === 'listening' 
            ? 'text-white shadow-xs' 
            : 'text-neutral-500 dark:text-white/50 hover:text-neutral-900 dark:hover:text-white hover:bg-black/[0.03] dark:hover:bg-white/[0.06]'}"
          style={activeHeatmapTab === 'listening' ? `background: linear-gradient(135deg, ${heatmapColor}, ${heatmapColorSub}); box-shadow: 0 2px 10px -2px ${heatmapColor};` : ''}
        >
          <span class="w-1.5 h-1.5 rounded-full {activeHeatmapTab === 'listening' ? 'bg-white shadow-[0_0_6px_#fff]' : 'bg-transparent'}"></span>
          <span>Listen</span>
        </button>

        <button
          type="button"
          onclick={() => { activeHeatmapTab = 'speaking'; inspectedDay = null; }}
          class="group relative flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-[10px] sm:text-[11px] font-mono font-bold transition-all duration-150 cursor-pointer active:scale-95 {activeHeatmapTab === 'speaking' 
            ? 'text-white shadow-xs' 
            : 'text-neutral-500 dark:text-white/50 hover:text-neutral-900 dark:hover:text-white hover:bg-black/[0.03] dark:hover:bg-white/[0.06]'}"
          style={activeHeatmapTab === 'speaking' ? `background: linear-gradient(135deg, ${heatmapColor}, ${heatmapColorSub}); box-shadow: 0 2px 10px -2px ${heatmapColor};` : ''}
        >
          <span class="w-1.5 h-1.5 rounded-full {activeHeatmapTab === 'speaking' ? 'bg-white shadow-[0_0_6px_#fff]' : 'bg-transparent'}"></span>
          <span>Speak</span>
        </button>
      </div>
    </div>

    <!-- Active Tile Inspection Capsule -->
    <div class="h-9 flex items-center justify-between px-3 sm:px-3.5 rounded-2xl bg-white/40 dark:bg-black/30 border border-black/[0.06] dark:border-white/[0.08] backdrop-blur-md text-[10px] font-mono relative z-10 shadow-inner">
      {#if inspectedDay}
        <div class="flex items-center gap-1.5 sm:gap-2">
          <span class="w-1.5 h-1.5 rounded-full" style="background-color: {heatmapColor}; box-shadow: 0 0 8px {heatmapColor};"></span>
          <span class="text-[var(--text-primary)] font-bold">{inspectedDay.date}</span>
        </div>
        <span class="font-bold text-xs" style="color: {heatmapColor};">{inspectedDay.label}</span>
      {:else}
        <span class="text-[var(--text-muted)] truncate">Tap any tile to inspect day</span>
        <span class="text-[var(--text-muted)] font-bold shrink-0">90 Days</span>
      {/if}
    </div>

    <!-- Heatmap Grid (Smooth touch scrolling on iPad) -->
    <div class="w-full overflow-x-auto pb-1 relative z-10 overscroll-x-contain" style="-webkit-overflow-scrolling: touch;">
      <div class="inline-flex gap-2 items-center min-w-full justify-between sm:justify-start">
        <!-- Weekday Labels -->
        <div class="flex flex-col gap-1 text-[8px] font-mono text-[var(--text-muted)] shrink-0 select-none leading-none">
          <span class="h-3 sm:h-3.5 flex items-center font-bold">M</span>
          <span class="h-3 sm:h-3.5 flex items-center opacity-0">T</span>
          <span class="h-3 sm:h-3.5 flex items-center font-bold">W</span>
          <span class="h-3 sm:h-3.5 flex items-center opacity-0">T</span>
          <span class="h-3 sm:h-3.5 flex items-center font-bold">F</span>
          <span class="h-3 sm:h-3.5 flex items-center opacity-0">S</span>
          <span class="h-3 sm:h-3.5 flex items-center font-bold">S</span>
        </div>

        <!-- 13 Weekly Columns -->
        <div class="flex gap-1.5">
          {#each heatmapWeeks as week}
            <div class="flex flex-col gap-1">
              {#each week as day}
                {@const isSelected = inspectedDay?.date === day.date}
                {@const isLit = day.level > 0}
                <button
                  type="button"
                  onclick={() => (inspectedDay = day)}
                  class="w-3 sm:w-3.5 h-3 sm:h-3.5 rounded-[4px] border transition-transform duration-75 hover:scale-125 focus:outline-none shrink-0 cursor-pointer relative {isSelected ? 'ring-2 ring-[var(--text-primary)] scale-125 z-20' : ''}"
                  style="
                    background-color: {getHeatmapBg(day.level, heatmapColor)}; 
                    border-color: {day.level === 0 ? 'var(--border-subtle)' : 'transparent'};
                    box-shadow: {isLit ? `0 0 ${day.level * 3}px ${heatmapColor}${day.level * 24}` : 'none'};
                  "
                  aria-label="{day.date}: {day.label}"
                ></button>
              {/each}
            </div>
          {/each}
        </div>
      </div>
    </div>

    <!-- 5-Tier Intensity Legend -->
    <div class="flex items-center justify-between text-[9px] font-mono text-[var(--text-muted)] pt-2 border-t border-[var(--border-subtle)] relative z-10 flex-wrap gap-1">
      <span class="font-bold">Consistency Scale</span>
      <div class="flex items-center gap-1.5">
        <span>Less</span>
        <div class="w-2.5 sm:w-3 h-2.5 sm:h-3 rounded-[3px] border border-[var(--border-subtle)] bg-[var(--bg-base)]"></div>
        <div class="w-2.5 sm:w-3 h-2.5 sm:h-3 rounded-[3px]" style="background-color: {getHeatmapBg(1, heatmapColor)}; box-shadow: 0 0 5px {heatmapColor}35;"></div>
        <div class="w-2.5 sm:w-3 h-2.5 sm:h-3 rounded-[3px]" style="background-color: {getHeatmapBg(2, heatmapColor)}; box-shadow: 0 0 7px {heatmapColor}55;"></div>
        <div class="w-2.5 sm:w-3 h-2.5 sm:h-3 rounded-[3px]" style="background-color: {getHeatmapBg(3, heatmapColor)}; box-shadow: 0 0 9px {heatmapColor}75;"></div>
        <div class="w-2.5 sm:w-3 h-2.5 sm:h-3 rounded-[3px]" style="background-color: {getHeatmapBg(4, heatmapColor)}; box-shadow: 0 0 12px {heatmapColor}99;"></div>
        <span>More</span>
      </div>
    </div>

  </div>

</div>