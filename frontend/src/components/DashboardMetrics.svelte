<script>
  import { metadataStore } from '../lib/stores/metadata.svelte.js';
  import { activeLanguage } from '../lib/stores/activeLanguage.svelte.js';
  import { 
    formatHoursMins, 
    formatMinutes, 
    calculateMedian, 
    calculateETA, 
    buildSmoothPath 
  } from '../lib/stats.js';

  let currentLang = $derived(metadataStore.currentLanguageData);
  let entries = $derived(metadataStore.sortedCalendarEntries);
  let milestones = $derived(activeLanguage.milestones);
  let colors = $derived(activeLanguage.colors);

  let activeChartTab = $state('vocab'); // 'vocab' | 'listening' | 'speaking'
  let activeHeatmapTab = $state('vocab'); // 'vocab' | 'listening' | 'speaking'
  let inspectedDay = $state(null);
  let hoveredPoint = $state(null);

  // 1. Core Aggregate Totals
  let aggregates = $derived.by(() => {
    let vocab = 0, grammar = 0, ci = 0, listeningSec = 0, speakingSec = 0;
    for (const e of entries) {
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

  // 2. Milestones
  let milestoneStats = $derived.by(() => {
    const vocabDailies = [], listenDailies = [], speakDailies = [];
    for (const e of entries) {
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
        title: 'Vocabulary Milestone',
        icon: '📖',
        color: colors.vocab?.dark_primary || '#10b981',
        pct: Math.min(100, Math.round((aggregates.vocab / vocabTarget) * 100)),
        formattedTarget: vocabTarget.toLocaleString(),
        eta: calculateETA(aggregates.vocab, vocabTarget, calculateMedian(vocabDailies), false)
      },
      {
        id: 'listening',
        title: 'Immersion Milestone',
        icon: '🎧',
        color: colors.listening?.dark_primary || '#f97316',
        pct: Math.min(100, Math.round((aggregates.listeningSec / listTargetSec) * 100)),
        formattedTarget: `${milestones.listening_hours || 48}h`,
        eta: calculateETA(aggregates.listeningSec, listTargetSec, calculateMedian(listenDailies), true)
      },
      {
        id: 'speaking',
        title: 'Speaking Milestone',
        icon: '🎙️',
        color: colors.speaking?.dark_primary || '#a855f7',
        pct: Math.min(100, Math.round((aggregates.speakingSec / speakTargetSec) * 100)),
        formattedTarget: `${milestones.speaking_hours || 12}h`,
        eta: calculateETA(aggregates.speakingSec, speakTargetSec, calculateMedian(speakDailies), true)
      }
    ];
  });

  // Vector Chart Geometry (Edge-to-Edge with Minimal Insets)
  const W = 360;
  const H = 140;
  const PAD_X = 6;      // Near zero inset so the curve spans the entire card width
  const PAD_TOP = 14;   // Clearance for floating peak labels
  const PAD_BOTTOM = 22;// Space for baseline and date labels

  let activeChartData = $derived.by(() => {
    if (entries.length === 0) return null;

    const asc = [...entries].reverse();
    let running = 0;
    const rawSeries = [];

    for (let i = 0; i < asc.length; i++) {
      if (activeChartTab === 'vocab') {
        running += asc[i].word || 0;
      } else if (activeChartTab === 'listening') {
        running += (asc[i].listening_time || 0) / 3600;
      } else {
        running += (asc[i].speaking_time || 0) / 3600;
      }
      rawSeries.push({ date: asc[i].date, value: running });
    }

    const peak = rawSeries[rawSeries.length - 1]?.value || 1;
    const maxVal = Math.max(activeChartTab === 'vocab' ? 10 : 1, Math.ceil(peak * 1.12));
    const midVal = Math.round((maxVal / 2) * 10) / 10;

    const usableW = W - PAD_X * 2;
    const usableH = H - PAD_TOP - PAD_BOTTOM;
    const denom = Math.max(1, rawSeries.length - 1);

    const points = rawSeries.map((item, i) => {
      const x = Math.round((PAD_X + (i / denom) * usableW) * 10) / 10;
      const y = Math.round((PAD_TOP + (1 - item.value / maxVal) * usableH) * 10) / 10;
      return { ...item, x, y };
    });

    const coords = points.map(p => [p.x, p.y]);
    const linePath = buildSmoothPath(coords);
    const areaPath = `${linePath} L ${coords[coords.length - 1][0]},${H - PAD_BOTTOM} L ${coords[0][0]},${H - PAD_BOTTOM} Z`;

    const activeColor = activeChartTab === 'vocab'
      ? (colors.vocab?.dark_primary || '#10b981')
      : activeChartTab === 'listening'
        ? (colors.listening?.dark_primary || '#f97316')
        : (colors.speaking?.dark_primary || '#a855f7');

    const startDate = rawSeries[0]?.date ? rawSeries[0].date.slice(5) : '';
    const endDate = rawSeries[rawSeries.length - 1]?.date ? rawSeries[rawSeries.length - 1].date.slice(5) : '';

    return {
      points,
      linePath,
      areaPath,
      activeColor,
      maxVal: activeChartTab === 'vocab' ? Math.round(maxVal) : maxVal.toFixed(1),
      midVal: activeChartTab === 'vocab' ? Math.round(midVal) : midVal.toFixed(1),
      startDate,
      endDate,
      currentTotal: rawSeries[rawSeries.length - 1]?.value || 0
    };
  });

  // Track scrub point across touch/pointer events
  function handleChartPointer(event) {
    if (!activeChartData?.points?.length) return;
    const svgRect = event.currentTarget.getBoundingClientRect();
    const clientX = event.clientX ?? event.touches?.[0]?.clientX;
    if (clientX === undefined) return;

    const relX = ((clientX - svgRect.left) / svgRect.width) * W;
    
    // Find nearest data point by X coordinate
    let closest = activeChartData.points[0];
    let minDiff = Infinity;
    for (const p of activeChartData.points) {
      const diff = Math.abs(p.x - relX);
      if (diff < minDiff) {
        minDiff = diff;
        closest = p;
      }
    }
    hoveredPoint = closest;
  }

  // 4. Heatmap Data Matrix with Absolute Intensity Levels (0-4)
  // 1. Local Date String Helper ('YYYY-MM-DD')
  function toLocalDateStr(d) {
    const year = d.getFullYear();
    const month = String(d.getMonth() + 1).padStart(2, '0');
    const day = String(d.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
  }

  // Helper for human-friendly audio / time tags
  function formatTileTime(sec) {
    if (!sec || sec <= 0) return '0s';
    if (sec < 60) return `${sec}s`;
    const mins = Math.round(sec / 60);
    return `${mins}m`;
  }

  // 4. Heatmap Data Matrix with Dynamic 4-Tier Goals (0-4)
  let heatmapData = $derived.by(() => {
    const today = new Date();
    today.setHours(0, 0, 0, 0);

    const logMap = new Map();
    for (const e of entries) logMap.set(e.date, e);

    // Dynamic targets from active language configuration (with fallbacks)
    const goals = activeLanguage.goals || {};
    const vocabGoal = goals.vocab || 20;
    const listenGoalSec = (goals.listening_minutes || goals.listening || 45) * 60;
    const speakGoalSec = (goals.speaking_minutes || goals.speaking || 10) * 60;

    // Helper: divides any daily target into 4 proportional buckets (25%, 50%, 75%, 100%)
    function calculateTier(value, target) {
      if (!value || value <= 0) return 0;
      if (value >= target) return 4;
      if (value >= target * 0.75) return 3;
      if (value >= target * 0.50) return 2;
      return 1; // Any non-zero progress earns at least Level 1
    }

    // Lock start to exactly 13 weeks ago (90 days)
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
        let label = 'No activity';

        if (activeHeatmapTab === 'vocab') {
          level = calculateTier(wCount, vocabGoal);
          if (wCount > 0) label = `${wCount} / ${vocabGoal} words`;
        } else if (activeHeatmapTab === 'listening') {
          level = calculateTier(lSec, listenGoalSec);
          if (lSec > 0) label = `${formatTileTime(lSec)} / ${Math.round(listenGoalSec / 60)}m listen`;
        } else {
          level = calculateTier(sSec, speakGoalSec);
          if (sSec > 0) label = `${formatTileTime(sSec)} / ${Math.round(speakGoalSec / 60)}m audio`;
        }

        days.push({ date: dt, level, label });
      }
      weeks.push(days);
    }

    const activeColor = activeHeatmapTab === 'vocab'
      ? (colors.vocab?.dark_primary || '#10b981')
      : activeHeatmapTab === 'listening'
        ? (colors.listening?.dark_primary || '#f97316')
        : (colors.speaking?.dark_primary || '#a855f7');

    return { weeks, activeColor };
  });

  // Calculate distinct background tones per level to eliminate blur/muddiness
  function getHeatmapBg(level, baseColor) {
    if (level === 0) return 'var(--bg-base)';
    if (level === 1) return `color-mix(in srgb, ${baseColor} 30%, var(--bg-surface))`;
    if (level === 2) return `color-mix(in srgb, ${baseColor} 55%, var(--bg-surface))`;
    if (level === 3) return `color-mix(in srgb, ${baseColor} 80%, var(--bg-surface))`;
    return baseColor;
  }
</script>

<div class="w-full space-y-6 pt-3 select-none">
  <!-- Minimalist Divider -->
  <div class="flex items-center gap-3">
    <div class="flex-1 h-px bg-[var(--border-card)] opacity-60"></div>
    <span class="text-[10px] font-bold uppercase tracking-widest text-[var(--text-muted)] px-1">
      Milestones & Metrics
    </span>
    <div class="flex-1 h-px bg-[var(--border-card)] opacity-60"></div>
  </div>

  <!-- Metric Digit Cards -->
  <div class="grid grid-cols-3 gap-2">
    <div class="flex flex-col items-center justify-center p-3 rounded-2xl border border-[var(--border-card)] bg-[var(--bg-surface)] shadow-xs">
      <div class="flex items-center gap-1 text-[10px] font-bold uppercase tracking-wider text-[var(--text-muted)]">
        <span>🔥</span>
        <span>Streak</span>
      </div>
      <div class="text-xl font-black mt-1 text-amber-500">
        {aggregates.streak}d
      </div>
    </div>

    <div class="flex flex-col items-center justify-center p-3 rounded-2xl border border-[var(--border-card)] bg-[var(--bg-surface)] shadow-xs">
      <div class="flex items-center gap-1 text-[10px] font-bold uppercase tracking-wider text-[var(--text-muted)]">
        <span>🗣️</span>
        <span>Vocab</span>
      </div>
      <div class="text-xl font-black mt-1" style="color: {colors.vocab?.dark_primary || '#10b981'};">
        {aggregates.vocab}
      </div>
    </div>

    <div class="flex flex-col items-center justify-center p-3 rounded-2xl border border-[var(--border-card)] bg-[var(--bg-surface)] shadow-xs">
      <div class="flex items-center gap-1 text-[10px] font-bold uppercase tracking-wider text-[var(--text-muted)]">
        <span>📚</span>
        <span>Grammar</span>
      </div>
      <div class="text-xl font-black mt-1" style="color: {colors.grammar?.dark_primary || '#0284c7'};">
        {aggregates.grammar}
      </div>
    </div>

    <div class="flex flex-col items-center justify-center p-3 rounded-2xl border border-[var(--border-card)] bg-[var(--bg-surface)] shadow-xs">
      <div class="flex items-center gap-1 text-[10px] font-bold uppercase tracking-wider text-[var(--text-muted)]">
        <span>📺</span>
        <span>CI</span>
      </div>
      <div class="text-xl font-black mt-1" style="color: {colors.ci?.dark_primary || '#9333ea'};">
        {aggregates.ci}
      </div>
    </div>

    <div class="flex flex-col items-center justify-center p-3 rounded-2xl border border-[var(--border-card)] bg-[var(--bg-surface)] shadow-xs">
      <div class="flex items-center gap-1 text-[10px] font-bold uppercase tracking-wider text-[var(--text-muted)]">
        <span>🎧</span>
        <span>Listen</span>
      </div>
      <div class="text-base sm:text-lg font-black mt-1" style="color: {colors.listening?.dark_primary || '#f97316'};">
        {formatHoursMins(aggregates.listeningSec)}
      </div>
    </div>

    <div class="flex flex-col items-center justify-center p-3 rounded-2xl border border-[var(--border-card)] bg-[var(--bg-surface)] shadow-xs">
      <div class="flex items-center gap-1 text-[10px] font-bold uppercase tracking-wider text-[var(--text-muted)]">
        <span>🎙️</span>
        <span>Speak</span>
      </div>
      <div class="text-base sm:text-lg font-black mt-1" style="color: {colors.speaking?.dark_primary || '#a855f7'};">
        {formatHoursMins(aggregates.speakingSec)}
      </div>
    </div>
  </div>

  <!-- Milestone Progress Bars -->
  <div class="space-y-2.5">
    {#each milestoneStats as m (m.id)}
      <div class="p-3.5 rounded-2xl border border-[var(--border-card)] bg-[var(--bg-surface)] shadow-xs space-y-2">
        <div class="flex items-center justify-between text-xs">
          <div class="flex items-center gap-1.5 font-bold text-[var(--text-primary)]">
            <span>{m.icon}</span>
            <span>{m.title}</span>
          </div>
          <div class="flex items-center gap-2">
            <span class="text-[10px] font-extrabold px-2 py-0.5 rounded-md border" style="color: {m.color}; background-color: {m.color}18; border-color: {m.color}35;">
              {m.eta.badge}
            </span>
            <span class="font-mono font-bold text-[var(--text-muted)]">
              {m.pct}%
            </span>
          </div>
        </div>

        <div class="w-full h-1.5 rounded-full bg-[var(--bg-base)] border border-[var(--border-card)] overflow-hidden">
          <div
            class="h-full rounded-full transition-all duration-700 ease-out"
            style="width: {m.pct}%; background-color: {m.color};"
          ></div>
        </div>

        <div class="flex items-center justify-between text-[11px] font-medium text-[var(--text-muted)] pt-0.5">
          <span>Pace: {m.eta.pace} • Est: {m.eta.est}</span>
          <span class="font-semibold">Target: {m.formattedTarget}</span>
        </div>
      </div>
    {/each}
  </div>

  <!-- SECTION 1: CUMULATIVE GROWTH CHART (FULL-WIDTH EDGE-TO-EDGE) -->
  <div class="p-4 rounded-2xl border border-[var(--border-card)] bg-[var(--bg-surface)] shadow-xs space-y-3">
    <!-- Header with Toggle Pill -->
    <div class="flex items-center justify-between gap-2">
      <div class="text-xs font-bold text-[var(--text-primary)] flex items-center gap-1.5">
        <span>📈</span>
        <span>Growth Trend</span>
      </div>

      <div class="flex rounded-xl bg-[var(--bg-base)] p-0.5 border border-[var(--border-card)]">
        <button
          onclick={() => { activeChartTab = 'vocab'; hoveredPoint = null; }}
          class="px-2.5 py-1 text-[10px] font-bold rounded-lg transition-colors {activeChartTab === 'vocab' ? 'bg-[var(--bg-surface)] text-[var(--text-primary)] shadow-xs' : 'text-[var(--text-muted)]'}"
        >
          Vocab
        </button>
        <button
          onclick={() => { activeChartTab = 'listening'; hoveredPoint = null; }}
          class="px-2.5 py-1 text-[10px] font-bold rounded-lg transition-colors {activeChartTab === 'listening' ? 'bg-[var(--bg-surface)] text-[var(--text-primary)] shadow-xs' : 'text-[var(--text-muted)]'}"
        >
          Listen
        </button>
        <button
          onclick={() => { activeChartTab = 'speaking'; hoveredPoint = null; }}
          class="px-2.5 py-1 text-[10px] font-bold rounded-lg transition-colors {activeChartTab === 'speaking' ? 'bg-[var(--bg-surface)] text-[var(--text-primary)] shadow-xs' : 'text-[var(--text-muted)]'}"
        >
          Speak
        </button>
      </div>
    </div>

    <!-- Dynamic Value Header / Scrub Inspector -->
    <div class="flex items-center justify-between text-[11px] font-mono">
      {#if hoveredPoint}
        <span class="text-[var(--text-muted)] font-medium">{hoveredPoint.date}</span>
        <span class="font-bold text-sm" style="color: {activeChartData?.activeColor};">
          {activeChartTab === 'vocab' ? `${hoveredPoint.value} words` : `${hoveredPoint.value.toFixed(1)} hrs`}
        </span>
      {:else}
        <span class="text-[var(--text-muted)]">Cumulative Total</span>
        <span class="font-bold text-sm" style="color: {activeChartData?.activeColor};">
          {activeChartTab === 'vocab' ? `${activeChartData?.currentTotal || 0} words` : `${(activeChartData?.currentTotal || 0).toFixed(1)} hrs`}
        </span>
      {/if}
    </div>

    <!-- Edge-to-Edge SVG Viewport -->
    <div class="w-full h-[145px] relative">
      {#if activeChartData?.linePath}
        <svg 
          viewBox="0 0 {W} {H}" 
          preserveAspectRatio="none"
          class="w-full h-full overflow-visible touch-none cursor-crosshair"
          role="application"
          aria-label="Interactive growth trend chart. Drag or hover to inspect data points."
          onpointermove={handleChartPointer}
          onpointerleave={() => (hoveredPoint = null)}
        >
          <defs>
            <linearGradient id="chartGrad" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stop-color={activeChartData.activeColor} stop-opacity="0.32" />
              <stop offset="100%" stop-color={activeChartData.activeColor} stop-opacity="0.0" />
            </linearGradient>
          </defs>

          <!-- Top Grid Line + Floating Ceiling Metric -->
          <line x1={PAD_X} y1={PAD_TOP} x2={W - PAD_X} y2={PAD_TOP} stroke="var(--border-card)" stroke-dasharray="2 3" opacity="0.5" />
          <text x={PAD_X + 2} y={PAD_TOP - 4} fill="var(--text-muted)" font-size="8" font-family="monospace" opacity="0.8">{activeChartData.maxVal}</text>

          <!-- Mid Grid Line + Floating Mid Metric -->
          <line x1={PAD_X} y1={PAD_TOP + (H - PAD_TOP - PAD_BOTTOM) / 2} x2={W - PAD_X} y2={PAD_TOP + (H - PAD_TOP - PAD_BOTTOM) / 2} stroke="var(--border-card)" stroke-dasharray="2 3" opacity="0.3" />
          <text x={PAD_X + 2} y={PAD_TOP + (H - PAD_TOP - PAD_BOTTOM) / 2 - 4} fill="var(--text-muted)" font-size="8" font-family="monospace" opacity="0.6">{activeChartData.midVal}</text>

          <!-- Solid Floor Line -->
          <line x1={PAD_X} y1={H - PAD_BOTTOM} x2={W - PAD_X} y2={H - PAD_BOTTOM} stroke="var(--border-card)" opacity="0.8" />

          <!-- X-Axis Temporal Boundaries -->
          <text x={PAD_X} y={H - 6} fill="var(--text-muted)" font-size="8" font-family="monospace">{activeChartData.startDate}</text>
          <text x={W - PAD_X} y={H - 6} fill="var(--text-muted)" font-size="8" font-family="monospace" text-anchor="end">{activeChartData.endDate}</text>

          <!-- Data Fill & Stroke -->
          <path d={activeChartData.areaPath} fill="url(#chartGrad)" />
          <path d={activeChartData.linePath} fill="none" stroke={activeChartData.activeColor} stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" />

          <!-- Scrubbing Vertical Guideline & Indicator Point -->
          {#if hoveredPoint}
            <line 
              x1={hoveredPoint.x} 
              y1={PAD_TOP} 
              x2={hoveredPoint.x} 
              y2={H - PAD_BOTTOM} 
              stroke={activeChartData.activeColor} 
              stroke-width="1.2" 
              stroke-dasharray="2 2" 
            />
            <circle 
              cx={hoveredPoint.x} 
              cy={hoveredPoint.y} 
              r="4.5" 
              fill="var(--bg-surface)" 
              stroke={activeChartData.activeColor} 
              stroke-width="2.5" 
            />
          {/if}
        </svg>
      {:else}
        <div class="w-full h-full flex items-center justify-center text-xs text-[var(--text-muted)] italic">
          No records to map yet
        </div>
      {/if}
    </div>
  </div>

  <!-- SECTION 2: 90-DAY ACTIVITY MATRIX (TIGHT COMPACT CELLS WITH LOCKED M-W-F-S ALIGNMENT) -->
  <div class="p-4 rounded-2xl border border-[var(--border-card)] bg-[var(--bg-surface)] shadow-xs space-y-3">
    <!-- Header with Toggle Pill -->
    <div class="flex items-center justify-between gap-2">
      <div class="text-xs font-bold text-[var(--text-primary)] flex items-center gap-1.5">
        <span>🟩</span>
        <span>Activity Grid</span>
      </div>

      <div class="flex rounded-xl bg-[var(--bg-base)] p-0.5 border border-[var(--border-card)]">
        <button
          onclick={() => { activeHeatmapTab = 'vocab'; inspectedDay = null; }}
          class="px-2.5 py-1 text-[10px] font-bold rounded-lg transition-colors {activeHeatmapTab === 'vocab' ? 'bg-[var(--bg-surface)] text-[var(--text-primary)] shadow-xs' : 'text-[var(--text-muted)]'}"
        >
          Vocab
        </button>
        <button
          onclick={() => { activeHeatmapTab = 'listening'; inspectedDay = null; }}
          class="px-2.5 py-1 text-[10px] font-bold rounded-lg transition-colors {activeHeatmapTab === 'listening' ? 'bg-[var(--bg-surface)] text-[var(--text-primary)] shadow-xs' : 'text-[var(--text-muted)]'}"
        >
          Listen
        </button>
        <button
          onclick={() => { activeHeatmapTab = 'speaking'; inspectedDay = null; }}
          class="px-2.5 py-1 text-[10px] font-bold rounded-lg transition-colors {activeHeatmapTab === 'speaking' ? 'bg-[var(--bg-surface)] text-[var(--text-primary)] shadow-xs' : 'text-[var(--text-muted)]'}"
        >
          Speak
        </button>
      </div>
    </div>

    <!-- Active Tile Inspection Banner -->
    <div class="h-6 flex items-center justify-between px-2.5 rounded-lg bg-[var(--bg-base)] border border-[var(--border-card)] text-[10px] font-mono">
      {#if inspectedDay}
        <span class="text-[var(--text-primary)] font-semibold">{inspectedDay.date}</span>
        <span class="font-bold" style="color: {heatmapData.activeColor};">{inspectedDay.label}</span>
      {:else}
        <span class="text-[var(--text-muted)]">Tap any square to inspect</span>
        <span class="text-[var(--text-muted)] opacity-60">Past 13 Weeks</span>
      {/if}
    </div>

    <!-- Compact Grid Container with Fixed Synchronized Day Rows -->
    <div class="w-full overflow-x-auto pb-1">
      <div class="inline-flex gap-1.5 items-center">
        <!-- Weekday Labels: Fixed 10px row heights strictly matching the cells -->
        <div class="flex flex-col gap-1 text-[8px] font-mono text-[var(--text-muted)] shrink-0 select-none leading-none">
          <span class="h-2.5 flex items-center">M</span>
          <span class="h-2.5 flex items-center opacity-0">T</span>
          <span class="h-2.5 flex items-center">W</span>
          <span class="h-2.5 flex items-center opacity-0">T</span>
          <span class="h-2.5 flex items-center">F</span>
          <span class="h-2.5 flex items-center opacity-0">S</span>
          <span class="h-2.5 flex items-center">S</span>
        </div>

        <!-- 13 Weekly Columns (Fixed 10px x 10px Squares) -->
        <div class="flex gap-1">
          {#each heatmapData.weeks as week}
            <div class="flex flex-col gap-1">
              {#each week as day}
                <button
                  type="button"
                  onclick={() => (inspectedDay = day)}
                  class="w-2.5 h-2.5 rounded-[2px] border transition-transform duration-75 active:scale-125 focus:outline-none shrink-0 {inspectedDay?.date === day.date ? 'ring-1 ring-[var(--text-primary)] scale-110 z-10' : ''}"
                  style="background-color: {getHeatmapBg(day.level, heatmapData.activeColor)}; border-color: {day.level === 0 ? 'var(--border-card)' : 'transparent'};"
                  aria-label="{day.date}: {day.label}"
                ></button>
              {/each}
            </div>
          {/each}
        </div>
      </div>
    </div>

    <!-- 5-Step Compact Intensity Legend -->
    <div class="flex items-center justify-between text-[9px] font-mono text-[var(--text-muted)] pt-0.5">
      <span>Consistency</span>
      <div class="flex items-center gap-1">
        <span>Less</span>
        <div class="w-2 h-2 rounded-[1.5px] border border-[var(--border-card)] bg-[var(--bg-base)]"></div>
        <div class="w-2 h-2 rounded-[1.5px]" style="background-color: {getHeatmapBg(1, heatmapData.activeColor)};"></div>
        <div class="w-2 h-2 rounded-[1.5px]" style="background-color: {getHeatmapBg(2, heatmapData.activeColor)};"></div>
        <div class="w-2 h-2 rounded-[1.5px]" style="background-color: {getHeatmapBg(3, heatmapData.activeColor)};"></div>
        <div class="w-2 h-2 rounded-[1.5px]" style="background-color: {getHeatmapBg(4, heatmapData.activeColor)};"></div>
        <span>More</span>
      </div>
    </div>
  </div>
</div>