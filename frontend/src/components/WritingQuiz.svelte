<!-- frontend/src/components/WritingQuiz.svelte -->
<script>
  import { onMount, onDestroy } from 'svelte';
  import { srsStore } from '../lib/stores/srs.svelte.js';
  import { activeLanguage } from '../lib/stores/activeLanguage.svelte.js';
  import { getIntervalPreview } from '../lib/srsEngine.js';
  import { fetchGlyphDetails, pointsToSvgPath } from '../lib/services/glyphLexicon.js';
  import { playTTS } from '../lib/tts.js';
  import { portal } from '../lib/actions/portal.js';

  import { 
    PenTool, 
    RotateCcw, 
    Eye, 
    EyeOff, 
    Volume2, 
    Eraser, 
    Check, 
    Target, 
    Zap, 
    Calendar, 
    Clock, 
    CheckCircle2, 
    Play,
    X,
    Layers,
    BookOpen,
    Sparkles
  } from '@lucide/svelte';

  let { langCode } = $props();

  let todayStr = new Date().toISOString().substring(0, 10);
  let mode = $state('review'); // 'review' | 'cram'
  let isPracticeDone = $state(false);
  let isSubmitting = $state(false);
  let isSpeaking = $state(false);

  let cramQueue = $state([]);
  let cramIndex = $state(0);

  // 🌟 3D GYRO / TILT / MOUSE SHEEN 🌟
  let cardStageEl = $state(null);
  let tiltX = $state(0);
  let tiltY = $state(0);
  let glareX = $state(50);
  let glareY = $state(50);
  let isStageHovered = $state(false);
  let tiltTicking = false;

  function handleStageMouseMove(e) {
    if (!cardStageEl || tiltTicking) return;
    tiltTicking = true;

    const rect = cardStageEl.getBoundingClientRect();
    const clientX = e.clientX;
    const clientY = e.clientY;

    requestAnimationFrame(() => {
      const normX = ((clientX - rect.left) / rect.width) * 2 - 1;
      const normY = ((clientY - rect.top) / rect.height) * 2 - 1;

      tiltX = -normY * 4;
      tiltY = normX * 4;
      glareX = ((clientX - rect.left) / rect.width) * 100;
      glareY = ((clientY - rect.top) / rect.height) * 100;

      tiltTicking = false;
    });
  }

  function handleStageMouseLeave() {
    isStageHovered = false;
    tiltX = 0;
    tiltY = 0;
    glareX = 50;
    glareY = 50;
  }

  let langConfig = $derived(activeLanguage.current);
  let colors = $derived(activeLanguage.colors || {});
  let writeColor = $derived(
    colors.speaking?.primary || 
    colors.speaking?.dark_primary || 
    '#c026d3'
  );
  let writeColorSub = $derived(
    colors.speaking?.light_primary || 
    '#e879f9'
  );

  let allCards = $derived.by(() => {
    const raw = srsStore.cards || {};
    const cards = [];
    for (const [key, item] of Object.entries(raw)) {
      if (item) {
        const isDue = !item.due_date || item.due_date <= todayStr;
        cards.push({ key, ...item, isDue });
      }
    }
    return cards;
  });

  let dueCards = $derived(
    allCards
      .filter((c) => c.isDue)
      .sort((a, b) => (a.due_date || '').localeCompare(b.due_date || ''))
  );

  let currCard = $derived.by(() => {
    if (mode === 'review') {
      return dueCards[0] || null;
    } else {
      return cramQueue[cramIndex] || null;
    }
  });

  let curInt = $derived(Number(currCard?.interval ?? 0));
  let curEase = $derived(Number(currCard?.ease ?? 2.50));

  // Extract all characters of the compound word
  let charList = $derived.by(() => {
    if (!currCard?.native) return [];
    return Array.from(currCard.native.trim()).filter((ch) => !/^\s+$/.test(ch));
  });

  let activeCharIdx = $state(0);
  let glyphDataMap = $state({});
  let strokeLengthsMap = $state({});

  // Animation timeline state
  let isPlayingAnimation = $state(false);
  let animCharIdx = $state(0);
  let animStrokeIdx = $state(0);
  let animTimer = null;

  $effect(() => {
    const list = charList;
    activeCharIdx = 0;
    isPracticeDone = false;
    isPlayingAnimation = false;
    if (animTimer) clearTimeout(animTimer);

    if (list.length === 0) {
      glyphDataMap = {};
      return;
    }

    const currentLang = langCode || langConfig?.code || 'zh-CN';
    list.forEach(async (ch) => {
      const data = await fetchGlyphDetails(currentLang, ch);
      if (data) {
        glyphDataMap[ch] = data;
        if (data.medians) {
          strokeLengthsMap[ch] = data.medians.map((pts) => {
            let len = 0;
            for (let i = 0; i < pts.length - 1; i++) {
              len += Math.hypot(pts[i + 1][0] - pts[i][0], pts[i + 1][1] - pts[i][1]);
            }
            return Math.max(len * 1.25, 200);
          });
        }
      }
    });
  });

  let selectedChar = $derived(charList[activeCharIdx] || '');
  let activeGlyph = $derived(glyphDataMap[selectedChar] || null);

  // Play animation across the whole compound word in sequence
  function playSequentialAnimation() {
    if (charList.length === 0) return;
    if (animTimer) clearTimeout(animTimer);

    isPlayingAnimation = true;
    animCharIdx = 0;
    animStrokeIdx = 0;

    function step() {
      const currentChar = charList[animCharIdx];
      const data = glyphDataMap[currentChar];
      const totalStrokes = data?.strokes?.length || 0;

      if (animStrokeIdx < totalStrokes) {
        animStrokeIdx++;
        animTimer = setTimeout(step, 340);
      } else {
        if (animCharIdx < charList.length - 1) {
          animCharIdx++;
          animStrokeIdx = 0;
          animTimer = setTimeout(step, 200);
        } else {
          isPlayingAnimation = false;
        }
      }
    }

    step();
  }

  // 🌟 CONTINUOUS MULTI-CHARACTER CANVAS MODAL 🌟
  let isCanvasOpen = $state(false);
  let canvasEl = $state(null);
  let ctx = null;
  let isDrawing = false;
  let showGuidelines = $state(false);
  let userStrokes = $state([]); // Array of raw paths drawn on the full board
  let currentLine = [];

  function openCanvasModal() {
    isCanvasOpen = true;
    showGuidelines = false;
    currentLine = [];
    setTimeout(initCanvasContext, 60);
  }

  function initCanvasContext() {
    if (!canvasEl) return;
    const dpr = window.devicePixelRatio || 1;
    const rect = canvasEl.getBoundingClientRect();
    canvasEl.width = rect.width * dpr;
    canvasEl.height = rect.height * dpr;
    ctx = canvasEl.getContext('2d');
    ctx.scale(dpr, dpr);
    redrawCanvasStrokes();
  }

  function getCanvasCoords(e) {
    const rect = canvasEl.getBoundingClientRect();
    const clientX = e.touches ? e.touches[0].clientX : e.clientX;
    const clientY = e.touches ? e.touches[0].clientY : e.clientY;
    return {
      x: clientX - rect.left,
      y: clientY - rect.top
    };
  }

  function startDraw(e) {
    isDrawing = true;
    const { x, y } = getCanvasCoords(e);
    currentLine = [{ x, y }];
  }

  function moveDraw(e) {
    if (!isDrawing) return;
    e.preventDefault();
    const { x, y } = getCanvasCoords(e);
    currentLine.push({ x, y });

    if (!ctx) ctx = canvasEl.getContext('2d');
    ctx.strokeStyle = writeColor;
    ctx.lineWidth = 14;
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';

    const len = currentLine.length;
    if (len >= 2) {
      ctx.beginPath();
      ctx.moveTo(currentLine[len - 2].x, currentLine[len - 2].y);
      ctx.lineTo(currentLine[len - 1].x, currentLine[len - 1].y);
      ctx.stroke();
    }
  }

  function endDraw() {
    if (!isDrawing) return;
    isDrawing = false;
    if (currentLine.length > 0) {
      userStrokes.push([...currentLine]);
      currentLine = [];
    }
  }

  function clearCanvas() {
    userStrokes = [];
    currentLine = [];
    if (canvasEl && ctx) {
      const rect = canvasEl.getBoundingClientRect();
      ctx.clearRect(0, 0, rect.width, rect.height);
    }
  }

  function undoLastStroke() {
    if (userStrokes.length === 0) return;
    userStrokes.pop();
    redrawCanvasStrokes();
  }

  function redrawCanvasStrokes() {
    if (!canvasEl) return;
    const rect = canvasEl.getBoundingClientRect();
    if (!ctx) ctx = canvasEl.getContext('2d');
    ctx.clearRect(0, 0, rect.width, rect.height);

    ctx.strokeStyle = writeColor;
    ctx.lineWidth = 14;
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';

    for (const line of userStrokes) {
      if (line.length < 2) continue;
      ctx.beginPath();
      ctx.moveTo(line[0].x, line[0].y);
      for (let i = 1; i < line.length; i++) {
        ctx.lineTo(line[i].x, line[i].y);
      }
      ctx.stroke();
    }
  }

  function finishPractice() {
    isCanvasOpen = false;
    isPracticeDone = true;
    handlePronounce();
  }

  function handlePronounce() {
    if (!currCard) return;
    isSpeaking = true;
    playTTS(currCard.native, langCode || langConfig?.code || 'zh-CN');
    setTimeout(() => (isSpeaking = false), 1200);
  }

  async function handleSM2Grade(grade) {
    if (!currCard?.key || isSubmitting) return;
    isSubmitting = true;

    try {
      await srsStore.rateCard(langCode, currCard.key, grade);
      userStrokes = [];
      isPracticeDone = false;
    } catch (err) {
      console.error(`[SRS] Failed to rate card "${currCard.key}":`, err);
    } finally {
      isSubmitting = false;
    }
  }

  function startCram() {
    mode = 'cram';
    cramQueue = [...allCards].sort(() => Math.random() - 0.5);
    cramIndex = 0;
    userStrokes = [];
    isPracticeDone = false;
  }

  function startReview() {
    mode = 'review';
    userStrokes = [];
    isPracticeDone = false;
  }

  function handleCramFail() {
    if (!currCard) return;
    cramQueue.push(currCard);
    cramIndex++;
    userStrokes = [];
    isPracticeDone = false;
  }

  function handleCramPass() {
    cramIndex++;
    userStrokes = [];
    isPracticeDone = false;
  }

  onDestroy(() => {
    if (animTimer) clearTimeout(animTimer);
  });
</script>

<div 
  class="relative flex flex-col gap-5 p-4 sm:p-6 rounded-3xl border border-black/10 dark:border-white/15 bg-white/70 dark:bg-[#12131a]/75 shadow-[0_20px_50px_-12px_rgba(0,0,0,0.25),inset_0_1px_1px_rgba(255,255,255,0.45)] dark:shadow-[0_24px_50px_-12px_rgba(0,0,0,0.7),inset_0_1px_1px_rgba(255,255,255,0.15)] select-none backdrop-blur-2xl backdrop-saturate-[180%] overflow-hidden box-border"
  style="--studio-theme: {writeColor};"
>
  <!-- Top Specular Neon Highlight Lip -->
  <div 
    class="pointer-events-none absolute top-0 left-0 right-0 h-[2px] opacity-90 z-20"
    style="background: linear-gradient(90deg, transparent 5%, {writeColor} 30%, {writeColorSub} 70%, transparent 95%); box-shadow: 0 1px 12px {writeColor};"
  ></div>

  <!-- Header & Mode Rail -->
  <div class="flex items-center justify-between flex-wrap gap-2.5 pt-0.5 relative z-10">
    <div class="flex items-center gap-2.5">
      <div 
        class="w-9 h-9 rounded-2xl flex items-center justify-center border shadow-inner"
        style="
          background-color: color-mix(in srgb, {writeColor} 18%, transparent);
          border-color: color-mix(in srgb, {writeColor} 38%, transparent);
          color: {writeColor};
        "
      >
        <PenTool size={17} strokeWidth={2.5} class="animate-pulse" />
      </div>

      <div>
        <h2 class="text-xs sm:text-sm font-black tracking-tight uppercase text-neutral-900 dark:text-white flex items-center gap-1.5">
          <span>Calligraphy & Writing Studio</span>
          <span class="w-1.5 h-1.5 rounded-full" style="background-color: {writeColor}; box-shadow: 0 0 6px {writeColor};"></span>
        </h2>
        <span class="text-[10px] font-mono text-neutral-500 dark:text-white/40 block">
          Continuous Word Recall & Stroke Order Flow
        </span>
      </div>
    </div>

    <!-- Mode Switcher Trench -->
    <div class="flex items-center gap-1.5 p-1 rounded-2xl bg-black/[0.04] dark:bg-white/[0.05] border border-black/[0.06] dark:border-white/[0.08] shadow-inner ml-auto">
      <button
        type="button"
        onclick={startReview}
        class="flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-xs font-bold transition-all duration-150 cursor-pointer {mode === 'review' 
          ? 'text-white shadow-xs' 
          : 'text-neutral-500 dark:text-white/50 hover:text-neutral-900 dark:hover:text-white'}"
        style={mode === 'review' ? `background: linear-gradient(135deg, ${writeColor}, ${writeColorSub}); box-shadow: 0 2px 10px -2px ${writeColor};` : ''}
      >
        <Target size={12} strokeWidth={2.8} />
        <span>Due ({dueCards.length})</span>
      </button>

      <button
        type="button"
        onclick={startCram}
        class="flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-xs font-bold transition-all duration-150 cursor-pointer {mode === 'cram' 
          ? 'text-white shadow-xs' 
          : 'text-neutral-500 dark:text-white/50 hover:text-neutral-900 dark:hover:text-white'}"
        style={mode === 'cram' ? `background: linear-gradient(135deg, ${writeColor}, ${writeColorSub}); box-shadow: 0 2px 10px -2px ${writeColor};` : ''}
      >
        <Zap size={12} strokeWidth={2.8} />
        <span>Cram ({allCards.length})</span>
      </button>
    </div>
  </div>

  {#if !currCard}
    <!-- Session Cleared Empty State -->
    <div class="py-14 px-6 text-center space-y-3 rounded-2xl border border-dashed border-black/10 dark:border-white/10 bg-white/30 dark:bg-white/[0.02] backdrop-blur-md">
      <div 
        class="w-12 h-12 rounded-2xl flex items-center justify-center mx-auto border shadow-sm"
        style="
          background-color: color-mix(in srgb, {writeColor} 18%, transparent);
          border-color: color-mix(in srgb, {writeColor} 38%, transparent);
          color: {writeColor};
        "
      >
        <CheckCircle2 size={24} strokeWidth={2.5} />
      </div>

      <div class="space-y-1">
        <h3 class="text-sm font-black text-neutral-900 dark:text-white tracking-tight">
          {mode === 'review' ? 'Calligraphy Queue Cleared' : 'Writing Session Completed'}
        </h3>
        <p class="text-xs text-neutral-500 dark:text-white/40 max-w-xs mx-auto leading-relaxed">
          {mode === 'review' 
            ? `All scheduled character writing prompts are completed (${todayStr}).` 
            : 'You reviewed all characters in the cram deck.'}
        </p>
      </div>

      {#if mode === 'cram' && allCards.length > 0}
        <button
          type="button"
          onclick={startCram}
          class="inline-flex items-center gap-1.5 px-4 py-2 rounded-xl text-xs font-black text-white cursor-pointer active:scale-95 transition-all shadow-md mt-2"
          style="background: linear-gradient(135deg, {writeColor}, {writeColorSub});"
        >
          <RotateCcw size={12} strokeWidth={2.8} />
          <span>Restart Writing Session</span>
        </button>
      {/if}
    </div>
  {:else}
    <!-- 🌟 3D GYROSCOPIC RECALL HERO STAGE 🌟 -->
    <div class="relative w-full [perspective:1000px] box-border">
      <div 
        bind:this={cardStageEl}
        role="presentation"
        onmousemove={handleStageMouseMove}
        onmouseenter={() => (isStageHovered = true)}
        onmouseleave={handleStageMouseLeave}
        class="relative w-full rounded-3xl border border-black/10 dark:border-white/15 bg-white/75 dark:bg-[#0c0d14]/85 shadow-2xl p-4 sm:p-6 flex flex-col gap-6 text-center overflow-hidden will-change-transform"
        style="
          transform: {isStageHovered 
            ? `rotateX(${tiltX}deg) rotateY(${tiltY}deg) translateY(-2px) scale(1.005)` 
            : 'rotateX(0deg) rotateY(0deg) translateY(0) scale(1)'};
          transform-style: preserve-3d;
          transition: transform 0.12s cubic-bezier(0.16, 1, 0.3, 1), box-shadow 0.2s ease;
          box-shadow: {isStageHovered 
            ? `0 24px 50px -12px rgba(0,0,0,0.65), 0 0 28px color-mix(in srgb, ${writeColor} 20%, transparent)` 
            : '0 10px 30px -8px rgba(0,0,0,0.35)'};
        "
      >
        <!-- Full-Bleed Artwork Aura or Radial Glow -->
        {#if currCard.link}
          <div class="pointer-events-none absolute inset-0 rounded-3xl overflow-hidden -z-10">
            <img 
              src={currCard.link} 
              alt="" 
              aria-hidden="true" 
              class="w-full h-full object-cover blur-2xl scale-135 saturate-[240%] opacity-35 dark:opacity-45 transform-gpu"
            />
            <div class="absolute inset-0 bg-gradient-to-b from-white/40 via-white/15 to-white/85 dark:from-black/40 dark:via-black/20 dark:to-black/90"></div>
          </div>
        {:else}
          <div 
            class="pointer-events-none absolute inset-0 rounded-3xl opacity-20 -z-10"
            style="background: radial-gradient(circle 380px at 50% 30%, {writeColor}, transparent 75%);"
          ></div>
        {/if}

        <!-- Cursor Light Sheen -->
        <div 
          class="pointer-events-none absolute inset-0 opacity-0 transition-opacity duration-150 z-20 {isStageHovered ? 'opacity-100' : ''}"
          style="background: radial-gradient(circle 300px at {glareX}% {glareY}%, rgba(255,255,255,0.15), transparent 75%);"
        ></div>

        <!-- Top Neon Lip -->
        <div 
          class="pointer-events-none absolute top-0 left-0 right-0 h-[2px] opacity-80 z-20"
          style="background: linear-gradient(90deg, transparent, {writeColor}, {writeColorSub}, transparent);"
        ></div>

        <!-- Metadata Strip: Date, English Meaning, Due -->
        <div class="w-full flex items-center justify-between text-[10px] font-mono font-bold text-neutral-500 dark:text-white/50 relative z-10">
          <span class="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-xl bg-black/[0.04] dark:bg-white/[0.06] border border-black/[0.06] dark:border-white/10 shadow-2xs backdrop-blur-md">
            <Calendar size={10} />
            <span>{currCard.source_date ? currCard.source_date.slice(5) : 'Prompt'}</span>
          </span>

          <!-- Full Compound Word Pinyin & English Title -->
          <div class="flex items-center gap-2">
            <span class="text-sm sm:text-base font-black text-neutral-900 dark:text-white">
              {currCard.meaning || currCard.definition || 'Recall Writing'}
            </span>
            {#if currCard.pronunciation}
              <span class="text-xs sm:text-sm font-mono font-bold" style="color: {writeColor};">
                [{currCard.pronunciation}]
              </span>
            {/if}
          </div>

          <span class="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-xl bg-black/[0.04] dark:bg-white/[0.06] border border-black/[0.06] dark:border-white/10 shadow-2xs backdrop-blur-md">
            <Clock size={10} />
            <span>Due: {currCard.due_date ? (currCard.due_date === todayStr ? 'Today' : currCard.due_date.slice(5)) : 'Immediate'}</span>
          </span>
        </div>

        <!-- 🌟 THE 3-COLUMN WORKSHOP ARENA 🌟 -->
        <div class="grid grid-cols-1 lg:grid-cols-12 gap-5 items-center relative z-10">

          <!-- LEFT COLUMN: Radical & Structural Breakdown of inspected character -->
          <div class="lg:col-span-3 space-y-3 order-2 lg:order-1 text-left">
            <div class="p-3.5 rounded-2xl bg-white/60 dark:bg-black/50 border border-black/10 dark:border-white/10 shadow-xs space-y-2 backdrop-blur-md">
              <span class="text-[10px] font-mono font-bold uppercase tracking-wider text-neutral-400 dark:text-white/40 flex items-center justify-between">
                <span class="flex items-center gap-1"><Layers size={11} style="color: {writeColor};" /> Radical</span>
                <span class="text-white/40">Char {activeCharIdx + 1}/{charList.length}</span>
              </span>
              <div class="flex items-baseline gap-2">
                <span class="text-2xl font-black text-white font-serif">{activeGlyph?.component1 || '—'}</span>
                <span class="text-xs font-mono font-bold text-white/50">{activeGlyph?.phonetic || ''}</span>
              </div>
            </div>

            <div class="p-3.5 rounded-2xl bg-white/60 dark:bg-black/50 border border-black/10 dark:border-white/10 shadow-xs space-y-1.5 backdrop-blur-md">
              <span class="text-[10px] font-mono font-bold uppercase tracking-wider text-neutral-400 dark:text-white/40 flex items-center gap-1">
                <BookOpen size={11} style="color: {writeColor};" /> Decomposition
              </span>
              <span class="text-xs font-mono font-bold text-neutral-800 dark:text-white/90 block">
                {activeGlyph?.component2 || '—'}
              </span>
            </div>
          </div>

          <!-- CENTER COLUMN: Unified Side-By-Side Stage for All Characters -->
          <div class="lg:col-span-6 flex flex-col items-center gap-3 order-1 lg:order-2">
            
            <!-- 🌟 Unified Multi-Character Calligraphy Arena (Inside One Box) 🌟 -->
            <div class="p-3 rounded-3xl bg-black/85 border border-white/20 shadow-2xl flex items-center justify-center gap-2 sm:gap-3 flex-wrap">
              {#each charList as ch, idx}
                {@const isSelected = idx === activeCharIdx}
                {@const gData = glyphDataMap[ch]}
                {@const sLengths = strokeLengthsMap[ch] || []}
                {@const isThisCharAnimating = isPlayingAnimation && animCharIdx === idx}
                {@const isPastChar = isPlayingAnimation && animCharIdx > idx}

                <div 
                  role="button"
                  tabindex="0"
                  onclick={() => (activeCharIdx = idx)}
                  onkeydown={(e) => { if (e.key === 'Enter') activeCharIdx = idx; }}
                  class="relative w-28 h-28 sm:w-36 sm:h-36 rounded-2xl bg-black/60 border transition-all duration-200 cursor-pointer overflow-hidden p-2 flex items-center justify-center shadow-inner {isSelected 
                    ? 'border-white/80 ring-2' 
                    : 'border-white/15 hover:border-white/30'}"
                  style={isSelected ? `ring-color: ${writeColor};` : ''}
                >
                  <!-- Rice Grid -->
                  <svg class="absolute inset-0 w-full h-full pointer-events-none opacity-15" viewBox="0 0 100 100">
                    <line x1="50" y1="0" x2="50" y2="100" stroke="white" stroke-width="0.8" stroke-dasharray="2,2" />
                    <line x1="0" y1="50" x2="100" y2="50" stroke="white" stroke-width="0.8" stroke-dasharray="2,2" />
                    <line x1="0" y1="0" x2="100" y2="100" stroke="white" stroke-width="0.8" stroke-dasharray="2,2" />
                    <line x1="100" y1="0" x2="0" y2="100" stroke="white" stroke-width="0.8" stroke-dasharray="2,2" />
                  </svg>

                  {#if gData?.strokes && gData.strokes.length > 0}
                    <svg viewBox="0 0 1024 1024" class="w-full h-full drop-shadow-md">
                      <defs>
                        {#each gData.strokes as strokeD, sIdx}
                          <clipPath id="stage-clip-{ch}-{sIdx}">
                            <path d={strokeD} transform="scale(1, -1) translate(0, -900)" />
                          </clipPath>
                        {/each}
                      </defs>

                      <!-- Static Completed Vector View -->
                      {#if !isPlayingAnimation}
                        <g transform="scale(1, -1) translate(0, -900)">
                          {#each gData.strokes as strokeD}
                            <path d={strokeD} fill={writeColor} />
                          {/each}
                        </g>
                      {:else}
                        <!-- Ghost Wireframe Background -->
                        <g transform="scale(1, -1) translate(0, -900)" opacity="0.12">
                          {#each gData.strokes as strokeD}
                            <path d={strokeD} fill="white" />
                          {/each}
                        </g>

                        <!-- Sequential Stroke Animation -->
                        {#if gData.medians}
                          {#each gData.medians as medianPts, sIdx}
                            {@const isVisible = isPastChar || (isThisCharAnimating && sIdx < animStrokeIdx)}
                            {@const len = sLengths[sIdx] || 260}
                            <g clip-path="url(#stage-clip-{ch}-{sIdx})">
                              <path
                                d={pointsToSvgPath(medianPts)}
                                transform="scale(1, -1) translate(0, -900)"
                                fill="none"
                                stroke={writeColor}
                                stroke-width="140"
                                stroke-linecap="round"
                                stroke-linejoin="round"
                                style="
                                  stroke-dasharray: {len};
                                  stroke-dashoffset: {isVisible ? 0 : len};
                                  transition: stroke-dashoffset 340ms cubic-bezier(0.25, 1, 0.5, 1);
                                "
                              />
                            </g>
                          {/each}
                        {/if}
                      {/if}
                    </svg>
                  {:else}
                    <span class="text-3xl font-black text-white font-serif">{ch}</span>
                  {/if}

                  <div class="absolute top-1.5 left-1.5 px-1.5 py-0.2 rounded bg-black/60 border border-white/10 text-[9px] font-mono font-bold text-white/60">
                    {ch}
                  </div>
                </div>
              {/each}
            </div>

            <!-- Animation Trigger -->
            <button
              type="button"
              onclick={playSequentialAnimation}
              disabled={isPlayingAnimation}
              class="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-white/10 hover:bg-white/20 border border-white/15 text-xs font-mono font-bold text-white transition-all active:scale-95 cursor-pointer shadow-xs disabled:opacity-50"
            >
              <Play size={12} class={isPlayingAnimation ? 'animate-spin text-emerald-400' : ''} />
              <span>{isPlayingAnimation ? 'Playing Word Sequence...' : 'Play Word Stroke Order'}</span>
            </button>
          </div>

          <!-- RIGHT COLUMN: Definition & Etymology Mnemonic -->
          <div class="lg:col-span-3 space-y-3 order-3 text-left">
            <div class="p-3.5 rounded-2xl bg-white/60 dark:bg-black/50 border border-black/10 dark:border-white/10 shadow-xs space-y-1 backdrop-blur-md">
              <span class="text-[10px] font-mono font-bold uppercase tracking-wider text-neutral-400 dark:text-white/40 block">
                {selectedChar} Definition
              </span>
              <p class="text-xs font-medium text-neutral-800 dark:text-white/90 leading-snug line-clamp-3">
                {activeGlyph?.definition || currCard.meaning || '—'}
              </p>
            </div>

            {#if activeGlyph?.mnemonic}
              <div class="p-3.5 rounded-2xl bg-white/60 dark:bg-black/50 border border-black/10 dark:border-white/10 shadow-xs space-y-1 backdrop-blur-md">
                <span class="text-[10px] font-mono font-bold uppercase tracking-wider text-amber-400 block flex items-center gap-1">
                  <Sparkles size={11} /> Mnemonic
                </span>
                <p class="text-[11px] font-medium text-white/80 leading-snug italic">
                  "{activeGlyph.mnemonic}"
                </p>
              </div>
            {/if}
          </div>

        </div>

        <!-- 🌟 BOTTOM ACTION BAR: Open Canvas OR SM-2 Rating Deck 🌟 -->
        <div class="w-full flex flex-col items-center gap-3 pt-2 relative z-10 border-t border-black/[0.08] dark:border-white/10">
          
          {#if !isPracticeDone}
            <!-- THE BIG "OPEN CANVAS" BUTTON -->
            <button
              type="button"
              onclick={openCanvasModal}
              class="inline-flex items-center gap-2.5 px-8 py-3 rounded-2xl font-black text-sm text-white transition-all duration-150 active:scale-95 cursor-pointer shadow-xl hover:brightness-105"
              style="
                background: linear-gradient(135deg, {writeColor}, {writeColorSub});
                box-shadow: 0 4px 20px -2px color-mix(in srgb, {writeColor} 45%, transparent);
              "
            >
              <PenTool size={16} strokeWidth={2.8} />
              <span>Open Writing Canvas</span>
            </button>
          {:else}
            <!-- REVEALED SM-2 RATING DECK -->
            <div class="flex flex-col items-center gap-3 w-full animate-in fade-in duration-200">
              <div class="flex items-center gap-2">
                <button
                  type="button"
                  onclick={openCanvasModal}
                  class="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-xl border border-white/15 bg-white/5 hover:bg-white/10 text-xs font-mono font-bold text-white transition-all cursor-pointer"
                >
                  <PenTool size={12} />
                  <span>Practice Again</span>
                </button>

                <button
                  type="button"
                  onclick={handlePronounce}
                  class="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-xl border transition-all cursor-pointer text-xs font-mono font-bold"
                  style="
                    background-color: color-mix(in srgb, {writeColor} 18%, transparent);
                    border-color: color-mix(in srgb, {writeColor} 38%, transparent);
                    color: {writeColor};
                  "
                >
                  <Volume2 size={12} class={isSpeaking ? 'animate-pulse' : ''} />
                  <span>Listen</span>
                </button>
              </div>

              <!-- 4 SRS Rating Buttons -->
              <div class="flex gap-2 justify-center flex-wrap pt-1 w-full max-w-lg">
                {#if mode === 'review'}
                  <button
                    type="button"
                    onclick={() => handleSM2Grade('again')}
                    disabled={isSubmitting}
                    class="px-3.5 py-2 rounded-xl text-xs font-black bg-rose-500/15 text-rose-500 border border-rose-500/35 hover:bg-rose-500/25 active:scale-95 transition-all cursor-pointer disabled:opacity-50 shadow-xs"
                  >
                    ❌ Again ({getIntervalPreview({ interval: curInt, ease: curEase, grade: 'again' })})
                  </button>

                  <button
                    type="button"
                    onclick={() => handleSM2Grade('hard')}
                    disabled={isSubmitting}
                    class="px-3.5 py-2 rounded-xl text-xs font-black bg-amber-500/15 text-amber-500 border border-amber-500/35 hover:bg-amber-500/25 active:scale-95 transition-all cursor-pointer disabled:opacity-50 shadow-xs"
                  >
                    ⚡ Hard ({getIntervalPreview({ interval: curInt, ease: curEase, grade: 'hard' })})
                  </button>

                  <button
                    type="button"
                    onclick={() => handleSM2Grade('good')}
                    disabled={isSubmitting}
                    class="px-3.5 py-2 rounded-xl text-xs font-black bg-emerald-500/15 text-emerald-500 border border-emerald-500/35 hover:bg-emerald-500/25 active:scale-95 transition-all cursor-pointer disabled:opacity-50 shadow-xs"
                  >
                    👍 Good ({getIntervalPreview({ interval: curInt, ease: curEase, grade: 'good' })})
                  </button>

                  <button
                    type="button"
                    onclick={() => handleSM2Grade('easy')}
                    disabled={isSubmitting}
                    class="px-3.5 py-2 rounded-xl text-xs font-black bg-indigo-500/15 text-indigo-500 border border-indigo-500/35 hover:bg-indigo-500/25 active:scale-95 transition-all cursor-pointer disabled:opacity-50 shadow-xs"
                  >
                    🌟 Easy ({getIntervalPreview({ interval: curInt, ease: curEase, grade: 'easy' })})
                  </button>
                {:else}
                  <button
                    type="button"
                    onclick={handleCramFail}
                    class="px-5 py-2 rounded-xl text-xs font-black bg-rose-500/15 text-rose-500 border border-rose-500/35 hover:bg-rose-500/25 active:scale-95 transition-all cursor-pointer shadow-xs"
                  >
                    ❌ Fail / Repeat
                  </button>

                  <button
                    type="button"
                    onclick={handleCramPass}
                    class="px-5 py-2 rounded-xl text-xs font-black bg-emerald-500/15 text-emerald-500 border border-emerald-500/35 hover:bg-emerald-500/25 active:scale-95 transition-all cursor-pointer shadow-xs"
                  >
                    ✅ Pass / Next
                  </button>
                {/if}
              </div>

              <div class="text-[10px] font-mono text-neutral-400 dark:text-white/40">
                Interval: {curInt}d • Factor: {curEase.toFixed(2)}
              </div>
            </div>
          {/if}

        </div>

      </div>
    </div>
  {/if}
</div>

<!-- 🌟 CONTINUOUS FULL-WORD PRACTICE CANVAS MODAL (BOTH CHARACTERS ON ONE DESK) 🌟 -->
{#if isCanvasOpen}
  <div 
    use:portal
    class="fixed inset-0 z-[9999] flex items-center justify-center p-4 sm:p-8 bg-black/80 backdrop-blur-2xl animate-fade-in select-none"
    role="presentation"
  >
    <div 
      class="relative w-full max-w-4xl rounded-3xl border border-white/20 bg-neutral-950/95 shadow-[0_0_80px_rgba(0,0,0,0.9)] overflow-hidden flex flex-col p-5 sm:p-7 space-y-4"
      style="--studio-theme: {writeColor};"
    >
      <!-- Top Neon Lip -->
      <div 
        class="absolute top-0 left-0 right-0 h-[2px] opacity-90"
        style="background: linear-gradient(90deg, transparent 5%, {writeColor} 50%, transparent 95%); box-shadow: 0 0 16px {writeColor};"
      ></div>

      <!-- Modal Header: Displays Full Word Prompt -->
      <div class="flex items-center justify-between border-b border-white/10 pb-3">
        <div class="flex items-center gap-3">
          <span class="text-xl sm:text-2xl font-black text-white font-serif tracking-tight">
            {currCard.native}
          </span>
          {#if currCard.pronunciation}
            <span class="text-xs sm:text-sm font-mono font-bold" style="color: {writeColor};">
              [{currCard.pronunciation}]
            </span>
          {/if}
          <span class="text-xs sm:text-sm font-medium text-white/60">
            • {currCard.meaning || currCard.definition}
          </span>
        </div>

        <button
          type="button"
          onclick={() => (isCanvasOpen = false)}
          class="w-8 h-8 rounded-full border border-white/10 bg-white/5 hover:bg-white/15 text-white/60 hover:text-white flex items-center justify-center cursor-pointer transition-all active:scale-90"
        >
          <X size={16} />
        </button>
      </div>

      <!-- 🌟 CONTINUOUS FULL-WORD CANVAS DESK (N Adjacent Cells Under ONE Drawing Canvas) 🌟 -->
      <div class="relative w-full h-[320px] sm:h-[400px] rounded-3xl bg-black/90 border border-white/20 shadow-2xl overflow-hidden touch-none flex items-center justify-center p-2">
        
        <!-- Multi-Cell Rice Grid (Each Character Gets Its Standard Square Cell) -->
        <div class="absolute inset-0 flex items-center justify-center pointer-events-none p-2 gap-3">
          {#each charList as ch}
            {@const gData = glyphDataMap[ch]}
            <div class="relative aspect-square h-full max-h-[360px] rounded-2xl border border-white/10 bg-black/40 overflow-hidden flex items-center justify-center">
              
              <!-- Rice Grid -->
              <svg class="absolute inset-0 w-full h-full opacity-20" viewBox="0 0 100 100">
                <line x1="50" y1="0" x2="50" y2="100" stroke="white" stroke-width="0.8" stroke-dasharray="2,2" />
                <line x1="0" y1="50" x2="100" y2="50" stroke="white" stroke-width="0.8" stroke-dasharray="2,2" />
                <line x1="0" y1="0" x2="100" y2="100" stroke="white" stroke-width="0.8" stroke-dasharray="2,2" />
                <line x1="100" y1="0" x2="0" y2="100" stroke="white" stroke-width="0.8" stroke-dasharray="2,2" />
              </svg>

              <!-- Full-Word Ghost Guidelines (All Characters Visible Simultaneously) -->
              {#if showGuidelines && gData?.strokes}
                <svg viewBox="0 0 1024 1024" class="absolute inset-4 w-[calc(100%-32px)] h-[calc(100%-32px)] drop-shadow-md">
                  <g transform="scale(1, -1) translate(0, -900)" opacity="0.18">
                    {#each gData.strokes as strokeD}
                      <path d={strokeD} fill="white" />
                    {/each}
                  </g>
                </svg>
              {/if}

              <!-- Cell Character Identifier Tag -->
              <span class="absolute top-2 left-2 text-[10px] font-mono font-bold text-white/30">
                {ch}
              </span>
            </div>
          {/each}
        </div>

        <!-- 🌟 THE SINGLE CONTINUOUS HTML5 CANVAS FOR THE ENTIRE WORD 🌟 -->
        <canvas
          bind:this={canvasEl}
          onmousedown={startDraw}
          onmousemove={moveDraw}
          onmouseup={endDraw}
          onmouseleave={endDraw}
          ontouchstart={startDraw}
          ontouchmove={moveDraw}
          ontouchend={endDraw}
          class="absolute inset-0 w-full h-full cursor-crosshair z-10"
        ></canvas>

        <!-- Floating In-Canvas Controls Toolbar -->
        <div class="absolute bottom-3 left-3 right-3 flex items-center justify-between z-20 pointer-events-auto">
          <button
            type="button"
            onclick={() => (showGuidelines = !showGuidelines)}
            class="flex items-center gap-1.5 px-3 py-1.5 rounded-xl border border-white/15 bg-black/75 hover:bg-black text-xs font-mono font-bold text-white transition-all active:scale-90"
          >
            {#if showGuidelines}
              <EyeOff size={13} />
              <span>Hide Ghost</span>
            {:else}
              <Eye size={13} />
              <span>Show Ghost</span>
            {/if}
          </button>

          <div class="flex items-center gap-1.5">
            <button
              type="button"
              onclick={undoLastStroke}
              class="p-2 rounded-xl border border-white/15 bg-black/75 hover:bg-black text-white transition-all active:scale-90"
              title="Undo stroke"
            >
              <RotateCcw size={14} />
            </button>
            <button
              type="button"
              onclick={clearCanvas}
              class="p-2 rounded-xl border border-white/15 bg-black/75 hover:bg-black text-white transition-all active:scale-90"
              title="Clear canvas"
            >
              <Eraser size={14} />
            </button>
          </div>
        </div>
      </div>

      <!-- Modal Footer -->
      <div class="flex items-center justify-between pt-2 border-t border-white/10">
        <span class="text-xs font-mono text-white/50">
          Write full compound: {currCard.native}
        </span>

        <button
          type="button"
          onclick={finishPractice}
          class="inline-flex items-center gap-2 px-6 py-2.5 rounded-2xl font-black text-xs text-white transition-all active:scale-95 cursor-pointer shadow-lg hover:brightness-105"
          style="
            background: linear-gradient(135deg, {writeColor}, {writeColorSub});
            box-shadow: 0 4px 18px -2px color-mix(in srgb, {writeColor} 45%, transparent);
          "
        >
          <Check size={14} strokeWidth={2.8} />
          <span>Done Practicing</span>
        </button>
      </div>
    </div>
  </div>
{/if}

<style>
  @keyframes fadeIn {
    from { opacity: 0; transform: scale(0.97); }
    to { opacity: 1; transform: scale(1); }
  }
  .animate-fade-in {
    animation: fadeIn 0.15s cubic-bezier(0.16, 1, 0.3, 1) forwards;
  }
</style>