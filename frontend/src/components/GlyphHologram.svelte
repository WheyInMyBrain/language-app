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
  import { Volume2, RotateCcw, X, ArrowRight } from '@lucide/svelte';

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

  // Tone color for phonetic body / main accents
  let chroma = $derived.by(() => {
    if (typeof glyphConfig.resolveChroma === 'function') {
      return glyphConfig.resolveChroma(data, langConfig.tones);
    }
    return {
      accentColor: langConfig.colors?.theme?.primary || '#38bdf8',
      badgeText: ''
    };
  });

  // Radical color from existing user configuration
  let radicalColor = $derived(
    langConfig.colors?.vocab?.dark_primary || 
    langConfig.colors?.vocab?.primary || 
    '#34d399'
  );

  let decompInfo = $derived(parseMorphDecomposition(data?.component2 || data?.decomposition));
  let spatial = $derived(getSpatialLayout(decompInfo.operator));

  let comp1Char = $derived(data?.component1 || decompInfo.parts[0] || '');
  let comp2Char = $derived(decompInfo.parts[1] || (decompInfo.parts[0] !== data?.component1 ? decompInfo.parts[0] : ''));

  let comp1Center = $derived(getStrokesCentroid(data?.medians, Array.from(comp1Indices)));
  let comp2Center = $derived(getStrokesCentroid(data?.medians, Array.from(comp2Indices)));

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
    if (!data?.strokes) return;
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
    calculateLengths();
    playAnimation();

    const partitions = await resolveMorphPartitions(lang, data);
    comp1Indices = partitions.comp1Indices;
    comp2Indices = partitions.comp2Indices;

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
    style="--glyph-accent: {chroma.accentColor}; --radical-color: {radicalColor};"
  >
    <!-- Top Accent Line -->
    <div
      class="absolute top-0 left-0 right-0 h-[2px] opacity-90 transition-colors duration-300"
      style="background: linear-gradient(90deg, transparent 5%, var(--glyph-accent) 50%, transparent 95%);"
    ></div>

    <!-- 1. TOP HEADER: MAIN CHARACTER + PINYIN + MEANING -->
    <header class="flex items-start justify-between border-b border-white/10 pb-4">
      <div class="space-y-1">
        <div class="flex items-center gap-3">
          <span class="text-4xl sm:text-5xl font-black text-white font-serif">
            {data?.character}
          </span>
          <span class="text-3xl sm:text-4xl font-black font-mono" style="color: var(--glyph-accent);">
            {data?.phonetic || data?.pinyin || ''}
          </span>

          {#if chroma.badgeText}
            <span
              class="px-2.5 py-0.5 rounded-lg text-xs font-mono font-bold border"
              style="
                color: var(--glyph-accent);
                background-color: color-mix(in srgb, var(--glyph-accent) 15%, transparent);
                border-color: color-mix(in srgb, var(--glyph-accent) 30%, transparent);
              "
            >
              {chroma.badgeText}
            </span>
          {/if}

          <button
            type="button"
            onclick={handlePronounce}
            class="w-8 h-8 rounded-xl border border-white/15 bg-white/5 hover:bg-white/15 text-white flex items-center justify-center cursor-pointer active:scale-90 transition-all"
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
        class="w-8 h-8 rounded-full border border-white/10 bg-white/5 hover:bg-white/15 text-white/60 hover:text-white flex items-center justify-center cursor-pointer active:scale-90 transition-all"
      >
        <X size={16} />
      </button>
    </header>

    <!-- 2. STAGE: LEFT COMPONENT + MAIN STAGE (WITH SPATIAL OVERLAYS) + RIGHT COMPONENT -->
    <div class="grid grid-cols-1 md:grid-cols-12 gap-5 items-center">

      <!-- LEFT: Radical / Root Satellite -->
      <div class="md:col-span-3 order-2 md:order-1">
        {#if comp1Char}
          <GlyphMiniCard
            char={comp1Char}
            role={spatial.type === 'horizontal' ? 'Left Radical' : spatial.type === 'vertical' ? 'Top Radical' : 'Radical'}
            accentColor="var(--radical-color)"
            {lang}
            isFocused={focusedComponent === 'comp1'}
            onHover={() => (focusedComponent = 'comp1')}
            onLeave={() => (focusedComponent = null)}
          />
        {/if}
      </div>

      <!-- CENTER: Main Canvas with Spatial Layout Overlay -->
      <div class="md:col-span-6 relative aspect-square w-full max-w-[340px] mx-auto rounded-2xl border border-white/15 bg-black/70 shadow-inner p-3 flex items-center justify-center order-1 md:order-2 overflow-hidden">
        
        <!-- Standard Rice Grid Background -->
        <svg class="absolute inset-0 w-full h-full pointer-events-none opacity-10" viewBox="0 0 100 100">
          <line x1="50" y1="0" x2="50" y2="100" stroke="white" stroke-width="0.8" stroke-dasharray="3,3" />
          <line x1="0" y1="50" x2="100" y2="50" stroke="white" stroke-width="0.8" stroke-dasharray="3,3" />
          <line x1="0" y1="0" x2="100" y2="100" stroke="white" stroke-width="0.8" stroke-dasharray="3,3" />
          <line x1="100" y1="0" x2="0" y2="100" stroke="white" stroke-width="0.8" stroke-dasharray="3,3" />
        </svg>

        <!-- 🌟 DYNAMIC SPATIAL ANATOMY REGIONS 🌟 -->
        <svg class="absolute inset-0 w-full h-full pointer-events-none" viewBox="0 0 1024 1024">
          {#if spatial.type === 'horizontal'}
            <!-- Left Half Region -->
            <rect 
              x="20" y="20" width="470" height="984" rx="24"
              fill="var(--radical-color)"
              opacity={focusedComponent === 'comp1' ? 0.08 : 0.02}
              stroke="var(--radical-color)"
              stroke-width={focusedComponent === 'comp1' ? 2 : 1}
              stroke-dasharray="6,6"
              class="transition-all duration-300"
            />
            <!-- Right Half Region -->
            <rect 
              x="534" y="20" width="470" height="984" rx="24"
              fill="var(--glyph-accent)"
              opacity={focusedComponent === 'comp2' ? 0.08 : 0.02}
              stroke="var(--glyph-accent)"
              stroke-width={focusedComponent === 'comp2' ? 2 : 1}
              stroke-dasharray="6,6"
              class="transition-all duration-300"
            />
          {:else if spatial.type === 'vertical'}
            <!-- Top Half Region -->
            <rect 
              x="20" y="20" width="984" height="470" rx="24"
              fill="var(--radical-color)"
              opacity={focusedComponent === 'comp1' ? 0.08 : 0.02}
              stroke="var(--radical-color)"
              stroke-width={focusedComponent === 'comp1' ? 2 : 1}
              stroke-dasharray="6,6"
              class="transition-all duration-300"
            />
            <!-- Bottom Half Region -->
            <rect 
              x="20" y="534" width="984" height="470" rx="24"
              fill="var(--glyph-accent)"
              opacity={focusedComponent === 'comp2' ? 0.08 : 0.02}
              stroke="var(--glyph-accent)"
              stroke-width={focusedComponent === 'comp2' ? 2 : 1}
              stroke-dasharray="6,6"
              class="transition-all duration-300"
            />
          {:else if spatial.type === 'enclosure'}
            <!-- Surround Outer Region -->
            <rect 
              x="30" y="30" width="964" height="964" rx="32"
              fill="none"
              stroke="var(--radical-color)"
              stroke-width={focusedComponent === 'comp1' ? 3 : 1}
              opacity={focusedComponent === 'comp1' ? 0.6 : 0.2}
              stroke-dasharray="6,6"
              class="transition-all duration-300"
            />
            <!-- Inner Sanctum Region -->
            <rect 
              x="260" y="260" width="504" height="504" rx="16"
              fill="none"
              stroke="var(--glyph-accent)"
              stroke-width={focusedComponent === 'comp2' ? 3 : 1}
              opacity={focusedComponent === 'comp2' ? 0.6 : 0.2}
              stroke-dasharray="4,4"
              class="transition-all duration-300"
            />
          {/if}
        </svg>

        <!-- SVG Calligraphy Vector Engine -->
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
            {#if data?.strokes}
              {#each data.strokes as strokeD}
                <path d={strokeD} fill="white" />
              {/each}
            {/if}
          </g>

          <!-- Animated Strokes -->
          {#if data?.medians}
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
          {/if}

          <!-- Direct Targeted Laser Pointers -->
          {#if focusedComponent === 'comp1'}
            <g class="animate-pulse">
              <circle cx={comp1Center.x} cy={comp1Center.y} r="14" fill="none" stroke="var(--radical-color)" stroke-width="3" />
              <path 
                d="M {comp1Center.x} {comp1Center.y} L 0 {comp1Center.y}" 
                fill="none" 
                stroke="var(--radical-color)" 
                stroke-width="2.5" 
                stroke-dasharray="4,4" 
              />
            </g>
          {:else if focusedComponent === 'comp2'}
            <g class="animate-pulse">
              <circle cx={comp2Center.x} cy={comp2Center.y} r="14" fill="none" stroke="var(--glyph-accent)" stroke-width="3" />
              <path 
                d="M {comp2Center.x} {comp2Center.y} L 1024 {comp2Center.y}" 
                fill="none" 
                stroke="var(--glyph-accent)" 
                stroke-width="2.5" 
                stroke-dasharray="4,4" 
              />
            </g>
          {/if}
        </svg>

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
      </div>

      <!-- RIGHT: Phonetic / Body Satellite -->
      <div class="md:col-span-3 order-3">
        {#if comp2Char}
          <GlyphMiniCard
            char={comp2Char}
            role={spatial.type === 'horizontal' ? 'Right Body' : spatial.type === 'vertical' ? 'Bottom Body' : 'Component'}
            accentColor="var(--glyph-accent)"
            {lang}
            isFocused={focusedComponent === 'comp2'}
            onHover={() => (focusedComponent = 'comp2')}
            onLeave={() => (focusedComponent = null)}
          />
        {/if}
      </div>

    </div>

    <!-- 3. 🌟 SPATIAL FUSION EQUATION BANNER (this + this = this) 🌟 -->
    <div class="p-3.5 rounded-2xl bg-white/5 border border-white/10 flex items-center justify-between text-xs font-mono">
      <div class="flex items-center gap-2.5 sm:gap-3 flex-wrap">
        <!-- Component 1 Chip -->
        <span 
          class="flex items-center gap-1.5 px-2.5 py-1 rounded-xl border font-bold"
          style="
            color: var(--radical-color); 
            background: color-mix(in srgb, var(--radical-color) 12%, transparent);
            border-color: color-mix(in srgb, var(--radical-color) 30%, transparent);
          "
        >
          <span class="text-base font-serif font-black">{comp1Char || '—'}</span>
          <span class="text-[10px] uppercase opacity-75">
            {spatial.type === 'horizontal' ? 'Left' : spatial.type === 'vertical' ? 'Top' : 'Root'}
          </span>
        </span>

        <span class="text-white/40 font-bold text-sm">+</span>

        <!-- Component 2 Chip -->
        <span 
          class="flex items-center gap-1.5 px-2.5 py-1 rounded-xl border font-bold"
          style="
            color: var(--glyph-accent); 
            background: color-mix(in srgb, var(--glyph-accent) 12%, transparent);
            border-color: color-mix(in srgb, var(--glyph-accent) 30%, transparent);
          "
        >
          <span class="text-base font-serif font-black">{comp2Char || '—'}</span>
          <span class="text-[10px] uppercase opacity-75">
            {spatial.type === 'horizontal' ? 'Right' : spatial.type === 'vertical' ? 'Bottom' : 'Body'}
          </span>
        </span>

        <ArrowRight size={14} class="text-white/40" />

        <!-- Target Composite Glyph -->
        <span class="flex items-center gap-1.5 px-3 py-1 rounded-xl bg-white/10 border border-white/20 text-white font-bold">
          <span class="text-lg font-serif font-black">{data?.character}</span>
          <span class="text-[10px] opacity-75 font-mono">{spatial.label}</span>
        </span>
      </div>

      <!-- Spatial Operator Badge -->
      <span class="text-[11px] font-mono text-white/40 hidden sm:inline-block">
        Format: {decompInfo.operator}
      </span>
    </div>

    <!-- 4. ETYMOLOGY MNEMONIC (Placed cleanly below the formula) -->
    {#if data?.mnemonic || data?.etymology_hint}
      <div class="px-4 py-3 rounded-xl bg-white/5 border border-white/5 text-xs text-white/80 flex items-baseline gap-2">
        <span class="font-bold text-white/40 uppercase font-mono text-[10px] tracking-wider shrink-0">
          Mnemonic
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
</style>