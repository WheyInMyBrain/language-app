<!-- frontend/src/components/GlyphHologram.svelte -->
<script>
  import { onMount, onDestroy } from 'svelte';
  import { pointsToSvgPath } from '../lib/services/glyphLexicon.js';
  import { 
    resolveMorphPartitions, 
    parseMorphDecomposition, 
    getSpatialLayout 
  } from '../lib/services/morphologyStory.js';
  import { getStrokesCentroid } from '../lib/services/decompositionResolver.js';
  import { activeLanguage } from '../lib/stores/activeLanguage.svelte.js';
  import { playTTS } from '../lib/tts.js';
  import { portal } from '../lib/actions/portal.js';
  import GlyphMiniCard from './GlyphMiniCard.svelte';
  import { Volume2, RotateCcw, X, ArrowRight, Sparkles } from '@lucide/svelte';

  let {
    data = null,
    lang = 'zh-CN',
    onClose = () => {}
  } = $props();

  let currentStroke = $state(0);
  let isAnimating = $state(true);
  let animTimer = null;
  let medianLengths = $state([]);
  let focusedComponent = $state(null);

  let comp1Indices = $state(new Set());
  let comp2Indices = $state(new Set());

  let langConfig = $derived(activeLanguage.current || {});
  let glyphConfig = $derived(langConfig.glyphConfig || {});
  let isRTL = $derived(langConfig.dir === 'rtl' || lang.startsWith('ar'));
  let gridType = $derived(glyphConfig.gridType || 'rice');

  // Tone or Harakat color accent
  let chroma = $derived.by(() => {
    if (typeof glyphConfig.resolveChroma === 'function') {
      return glyphConfig.resolveChroma(data, langConfig.tones);
    }
    return {
      accentColor: langConfig.colors?.theme?.primary || '#38bdf8',
      badgeText: ''
    };
  });

  // Secondary color for Root / Radical
  let comp1Color = $derived(
    langConfig.colors?.vocab?.dark_primary || 
    langConfig.colors?.vocab?.primary || 
    '#34d399'
  );

  let hasStrokeData = $derived(
    Array.isArray(data?.strokes) && data.strokes.length > 0 && Array.isArray(data?.medians)
  );

  let decompInfo = $derived(parseMorphDecomposition(data?.component2 || data?.decomposition));
  let spatial = $derived(getSpatialLayout(decompInfo.operator));

  let comp1Char = $derived(data?.component1 || decompInfo.parts[0] || '');
  let comp2Char = $derived(decompInfo.parts[1] || (decompInfo.parts[0] !== data?.component1 ? decompInfo.parts[0] : ''));

  let labels = $derived(glyphConfig.labels || {
    primaryPhonetic: 'Phonetic',
    component1: 'Root',
    component2: 'Pattern / Body',
    mnemonic: 'Mnemonic'
  });

  let comp1Center = $derived(
    hasStrokeData ? getStrokesCentroid(data?.medians, Array.from(comp1Indices)) : { x: 512, y: 512 }
  );
  let comp2Center = $derived(
    hasStrokeData ? getStrokesCentroid(data?.medians, Array.from(comp2Indices)) : { x: 512, y: 512 }
  );

  function calculateLengths() {
    if (!data?.medians) return;
    medianLengths = data.medians.map((pts) => {
      let len = 0;
      for (let i = 0; i < pts.length - 1; i++) {
        len += Math.hypot(pts[i + 1][0] - pts[i][0], pts[i + 1][1] - pts[i][1]);
      }
      return Math.max(len * 1.25, 200);
    });
  }

  function playAnimation() {
    if (!hasStrokeData) return;
    if (animTimer) clearTimeout(animTimer);

    currentStroke = 0;
    isAnimating = true;

    function step() {
      if (currentStroke < data.strokes.length) {
        currentStroke++;
        animTimer = setTimeout(step, 380);
      } else {
        isAnimating = false;
      }
    }
    step();
  }

  onMount(async () => {
    if (hasStrokeData) {
      calculateLengths();
      playAnimation();
    } else {
      isAnimating = false;
    }

    if (typeof resolveMorphPartitions === 'function') {
      try {
        const partitions = await resolveMorphPartitions(lang, data);
        comp1Indices = partitions.comp1Indices || new Set();
        comp2Indices = partitions.comp2Indices || new Set();
      } catch (_) {}
    }

    const prevOverflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden';

    return () => {
      document.body.style.overflow = prevOverflow;
    };
  });

  onDestroy(() => {
    if (animTimer) clearTimeout(animTimer);
  });

  function handlePronounce() {
    if (data?.character) {
      playTTS(data.character, lang);
    }
  }
</script>

<div
  use:portal
  class="fixed inset-0 z-[9999] flex items-center justify-center p-4 sm:p-6 bg-black/80 backdrop-blur-xl animate-fade-in select-none"
  onclick={(e) => { if (e.target === e.currentTarget) onClose(); }}
  role="presentation"
>
  <div
    class="relative w-full max-w-4xl rounded-3xl border border-white/15 bg-neutral-900/95 shadow-2xl overflow-hidden flex flex-col p-6 sm:p-7 space-y-5"
    style="--glyph-accent: {chroma.accentColor}; --radical-color: {comp1Color};"
  >
    <!-- Top Accent Line -->
    <div
      class="absolute top-0 left-0 right-0 h-[2px] opacity-90 transition-colors duration-300"
      style="background: linear-gradient(90deg, transparent 5%, var(--glyph-accent) 50%, transparent 95%);"
    ></div>

    <!-- 1. TOP HEADER: MAIN WORD/CHAR + PHONETIC + DEFINITION -->
    <header class="flex items-start justify-between border-b border-white/10 pb-4">
      <div class="space-y-1">
        <div class="flex items-center gap-3" dir={isRTL ? 'rtl' : 'ltr'}>
          <span class="text-4xl sm:text-5xl font-black text-white {isRTL ? 'font-arabic tracking-normal' : 'font-serif'}">
            {data?.character}
          </span>
          <span class="text-2xl sm:text-3xl font-black font-mono" style="color: var(--glyph-accent);" dir="ltr">
            {data?.phonetic || data?.pinyin || data?.transliteration || ''}
          </span>

          {#if chroma.badgeText}
            <span
              class="px-2.5 py-0.5 rounded-lg text-xs font-mono font-bold border"
              style="
                color: var(--glyph-accent);
                background-color: color-mix(in srgb, var(--glyph-accent) 15%, transparent);
                border-color: color-mix(in srgb, var(--glyph-accent) 30%, transparent);
              "
              dir="ltr"
            >
              {chroma.badgeText}
            </span>
          {/if}

          <button
            type="button"
            onclick={handlePronounce}
            class="w-8 h-8 rounded-xl border border-white/15 bg-white/5 hover:bg-white/15 text-white flex items-center justify-center cursor-pointer active:scale-90 transition-all shrink-0"
          >
            <Volume2 size={15} style="color: var(--glyph-accent);" />
          </button>
        </div>

        <p class="text-sm sm:text-base font-medium text-white/90">
          {data?.definition || '—'}
        </p>
      </div>

      <button
        type="button"
        onclick={onClose}
        class="w-8 h-8 rounded-full border border-white/10 bg-white/5 hover:bg-white/15 text-white/60 hover:text-white flex items-center justify-center cursor-pointer active:scale-90 transition-all shrink-0"
      >
        <X size={16} />
      </button>
    </header>

    <!-- 2. STAGE: COMPONENT 1 + MAIN VIEWPORT + COMPONENT 2 -->
    <div class="grid grid-cols-1 md:grid-cols-12 gap-5 items-center">

      <!-- LEFT: Root / Component 1 Satellite -->
      <div class="md:col-span-3 order-2 md:order-1">
        {#if comp1Char}
          <GlyphMiniCard
            char={comp1Char}
            role={labels.component1 || 'Root'}
            accentColor="var(--radical-color)"
            {lang}
            isFocused={focusedComponent === 'comp1'}
            onHover={() => (focusedComponent = 'comp1')}
            onLeave={() => (focusedComponent = null)}
          />
        {/if}
      </div>

      <!-- CENTER: Main Stage Viewport -->
      <div class="md:col-span-6 relative aspect-square w-full max-w-[340px] mx-auto rounded-2xl border border-white/15 bg-black/70 shadow-inner p-3 flex items-center justify-center order-1 md:order-2 overflow-hidden">
        
        <!-- GRID OVERLAYS -->
        {#if gridType === 'rice'}
          <!-- Chinese Mi-Zi-Ge (米字格) -->
          <svg class="absolute inset-0 w-full h-full pointer-events-none opacity-10" viewBox="0 0 100 100">
            <line x1="50" y1="0" x2="50" y2="100" stroke="white" stroke-width="0.8" stroke-dasharray="3,3" />
            <line x1="0" y1="50" x2="100" y2="50" stroke="white" stroke-width="0.8" stroke-dasharray="3,3" />
            <line x1="0" y1="0" x2="100" y2="100" stroke="white" stroke-width="0.8" stroke-dasharray="3,3" />
            <line x1="100" y1="0" x2="0" y2="100" stroke="white" stroke-width="0.8" stroke-dasharray="3,3" />
          </svg>
        {:else if gridType === 'lined'}
          <!-- Arabic Calligraphy Baseline & Proportion Guides (Mizan) -->
          <svg class="absolute inset-0 w-full h-full pointer-events-none opacity-20" viewBox="0 0 100 100">
            <line x1="0" y1="30" x2="100" y2="30" stroke="white" stroke-width="0.5" stroke-dasharray="2,3" /> <!-- Ascender Line -->
            <line x1="0" y1="48" x2="100" y2="48" stroke="var(--glyph-accent)" stroke-width="0.8" />           <!-- Median Line -->
            <line x1="0" y1="62" x2="100" y2="62" stroke="white" stroke-width="1.2" />                          <!-- Primary Baseline (Khat) -->
            <line x1="0" y1="78" x2="100" y2="78" stroke="white" stroke-width="0.5" stroke-dasharray="2,3" /> <!-- Descender Line -->
          </svg>
        {/if}

        <!-- 🌟 BRANCH A: Vector Animated Engine (Chinese / Hanzi) 🌟 -->
        {#if hasStrokeData}
          <svg viewBox="0 0 1024 1024" class="w-full h-full drop-shadow-xl relative z-10">
            <defs>
              {#if data?.strokes}
                {#each data.strokes as strokeD, idx}
                  <clipPath id="main-clip-{idx}">
                    <path d={strokeD} transform="scale(1, -1) translate(0, -900)" />
                  </clipPath>
                {/each}
              {/if}
            </defs>

            <!-- Ghost Trace -->
            <g transform="scale(1, -1) translate(0, -900)" opacity="0.08">
              {#each data.strokes as strokeD}
                <path d={strokeD} fill="white" />
              {/each}
            </g>

            <!-- Animated Medians -->
            {#each data.medians as medianPts, idx}
              {@const isVisible = idx < currentStroke}
              {@const isCurrent = idx === currentStroke - 1 && isAnimating}
              {@const len = medianLengths[idx] || 300}
              {@const isComp1 = comp1Indices.has(idx)}
              {@const isDimmed = (focusedComponent === 'comp1' && !isComp1) || (focusedComponent === 'comp2' && isComp1)}
              {@const strokeColor = isComp1 ? 'var(--radical-color)' : 'var(--glyph-accent)'}

              <g 
                clip-path="url(#main-clip-{idx})" 
                opacity={isDimmed ? 0.15 : 1}
                class="transition-opacity duration-200"
              >
                <path
                  d={pointsToSvgPath(medianPts)}
                  transform="scale(1, -1) translate(0, -900)"
                  fill="none"
                  stroke={strokeColor}
                  stroke-width="136"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  style="
                    stroke-dasharray: {len};
                    stroke-dashoffset: {isVisible ? 0 : len};
                    transition: stroke-dashoffset {isCurrent ? '380ms' : '0ms'} cubic-bezier(0.25, 1, 0.5, 1);
                  "
                />
              </g>
            {/each}
          </svg>

          <!-- Replay Button -->
          <button
            type="button"
            onclick={playAnimation}
            class="absolute bottom-3 right-3 z-20 flex items-center gap-1 px-2.5 py-1 rounded-xl bg-white/10 hover:bg-white/20 border border-white/15 text-[11px] font-mono font-bold text-white transition-all active:scale-90 cursor-pointer backdrop-blur-md"
          >
            <RotateCcw size={11} class={isAnimating ? 'animate-spin' : ''} />
            <span>Replay</span>
          </button>

          <div class="absolute top-3 left-3 z-20 px-2 py-0.5 rounded-lg bg-black/60 border border-white/10 text-[10px] font-mono text-white/60">
            {Math.min(currentStroke, data?.strokes?.length || 0)} / {data?.strokes?.length || 0}
          </div>

        <!-- 🌟 BRANCH B: Typographic Stage (Arabic / Alphabetic) 🌟 -->
        {:else}
          <div class="relative z-10 flex flex-col items-center justify-center w-full h-full text-center select-text">
            <span 
              class="text-6xl sm:text-7xl font-bold font-arabic leading-relaxed drop-shadow-2xl transition-transform duration-200 hover:scale-105"
              style="color: var(--glyph-accent);"
              dir={isRTL ? 'rtl' : 'ltr'}
            >
              {data?.character}
            </span>
            {#if data?.root || comp1Char}
              <span class="mt-2 text-xs font-mono text-white/50 px-2 py-0.5 rounded-md bg-white/5 border border-white/10">
                {labels.component1}: <strong class="text-white">{data?.root || comp1Char}</strong>
              </span>
            {/if}
          </div>
        {/if}
      </div>

      <!-- RIGHT: Pattern / Component 2 Satellite -->
      <div class="md:col-span-3 order-3">
        {#if comp2Char}
          <GlyphMiniCard
            char={comp2Char}
            role={labels.component2 || 'Pattern'}
            accentColor="var(--glyph-accent)"
            {lang}
            isFocused={focusedComponent === 'comp2'}
            onHover={() => (focusedComponent = 'comp2')}
            onLeave={() => (focusedComponent = null)}
          />
        {/if}
      </div>

    </div>

    <!-- 3. 🌟 GENERALIZED MORPHOLOGY FORMULA BANNER 🌟 -->
    <div class="p-3.5 rounded-2xl bg-white/5 border border-white/10 flex items-center justify-between text-xs font-mono">
      <div class="flex items-center gap-2.5 sm:gap-3 flex-wrap">
        <!-- Part 1 -->
        <span 
          class="flex items-center gap-1.5 px-2.5 py-1 rounded-xl border font-bold"
          style="
            color: var(--radical-color); 
            background: color-mix(in srgb, var(--radical-color) 12%, transparent);
            border-color: color-mix(in srgb, var(--radical-color) 30%, transparent);
          "
        >
          <span class="text-base {isRTL ? 'font-arabic' : 'font-serif'} font-black">{comp1Char || '—'}</span>
          <span class="text-[10px] uppercase opacity-75">{labels.component1}</span>
        </span>

        <span class="text-white/40 font-bold text-sm">+</span>

        <!-- Part 2 -->
        <span 
          class="flex items-center gap-1.5 px-2.5 py-1 rounded-xl border font-bold"
          style="
            color: var(--glyph-accent); 
            background: color-mix(in srgb, var(--glyph-accent) 12%, transparent);
            border-color: color-mix(in srgb, var(--glyph-accent) 30%, transparent);
          "
        >
          <span class="text-base {isRTL ? 'font-arabic' : 'font-serif'} font-black">{comp2Char || '—'}</span>
          <span class="text-[10px] uppercase opacity-75">{labels.component2}</span>
        </span>

        <ArrowRight size={14} class="text-white/40" />

        <!-- Full Word -->
        <span class="flex items-center gap-1.5 px-3 py-1 rounded-xl bg-white/10 border border-white/20 text-white font-bold">
          <span class="text-lg {isRTL ? 'font-arabic' : 'font-serif'} font-black">{data?.character}</span>
          <span class="text-[10px] opacity-75 font-mono">{labels.primaryPhonetic}</span>
        </span>
      </div>

      {#if decompInfo.operator && gridType === 'rice'}
        <span class="text-[11px] font-mono text-white/40 hidden sm:inline-block">
          Operator: {decompInfo.operator}
        </span>
      {/if}
    </div>

    <!-- 4. ETYMOLOGY / ROOT MNEMONIC -->
    {#if data?.mnemonic || data?.etymology_hint}
      <div class="px-4 py-3 rounded-xl bg-white/5 border border-white/5 text-xs text-white/80 flex items-baseline gap-2">
        <span class="font-bold text-white/40 uppercase font-mono text-[10px] tracking-wider shrink-0">
          {labels.mnemonic || 'Mnemonic'}
        </span>
        <span class="leading-relaxed font-sans">{data.mnemonic || data.etymology_hint}</span>
      </div>
    {/if}

  </div>
</div>

<style>
  @keyframes fadeIn {
    from { opacity: 0; transform: scale(0.97); }
    to { opacity: 1; transform: scale(1); }
  }
  .animate-fade-in {
    animation: fadeIn 0.15s cubic-bezier(0.16, 1, 0.3, 1) forwards;
  }
  :global(.font-arabic) {
    font-family: 'Amiri', 'Scheherazade New', 'Noto Naskh Arabic', serif, system-ui;
  }
</style>