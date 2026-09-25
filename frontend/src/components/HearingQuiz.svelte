<!-- frontend/src/components/HearingQuiz.svelte -->
<script>
  import { srsStore } from '../lib/stores/srs.svelte.js';
  import { activeLanguage } from '../lib/stores/activeLanguage.svelte.js';
  import { getIntervalPreview } from '../lib/srsEngine.js';
  import { tokenizePhonetics } from '../lib/formatters/phonetics.js';
  import { playTTS } from '../lib/tts.js';
  import MediaStage from './MediaStage.svelte';
  import ColoredText from './ColoredText.svelte';

  // Razor-sharp vector icons
  import { 
    Headphones, 
    Volume2, 
    Eye, 
    RotateCcw, 
    Calendar, 
    Zap, 
    Target,
    CheckCircle2,
    Clock,
    Sparkles,
    Gauge
  } from '@lucide/svelte';

  let { langCode } = $props();

  let todayStr = new Date().toISOString().substring(0, 10);
  let mode = $state('review'); // 'review' | 'cram'
  let ttsRate = $state(0.85);
  let isRevealed = $state(false);
  let isSubmitting = $state(false);
  let isPlayingAudio = $state(false);

  let cramQueue = $state([]);
  let cramIndex = $state(0);

  // 🌟 GYRO / TILT STATE (rAF-Throttled) 🌟
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

      tiltX = -normY * 4.5;
      tiltY = normX * 4.5;
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
  let themeColor = $derived(activeLanguage.themeColor || colors.theme || '#a855f7');
  let listeningColor = $derived(colors.listening?.primary || colors.listening?.dark_primary || '#f97316');
  let listeningColorSub = $derived(colors.listening?.light_primary || '#fb923c');

  // Read all listening cards from srsStore.cards
  let allCards = $derived.by(() => {
    const raw = srsStore.cards || {};
    const cards = [];

    for (const [key, item] of Object.entries(raw)) {
      if (item && item.card_type === 'listening') {
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

  let curWord = $derived.by(() => {
    if (mode === 'review') {
      return dueCards[0] || null;
    } else {
      return cramQueue[cramIndex] || null;
    }
  });

  let curInt = $derived(Number(curWord?.interval ?? 0));
  let curEase = $derived(Number(curWord?.ease ?? 2.50));

  // 🌟 SYNCHRONIZED TONE CHROMA ENGINE (Dual line tone matching) 🌟
  const tokenCache = new Map();
  function getSynchronizedTokens(script, pron, cfg) {
    const key = `${cfg?.code || 'zh-CN'}:${script || ''}:${pron || ''}`;
    if (tokenCache.has(key)) return tokenCache.get(key);

    const parsed = tokenizePhonetics(script, pron, cfg);
    const primary = parsed.primaryTokens || [];
    const secondary = parsed.secondaryTokens || [];
    const coloredSecondary = secondary.filter(t => t.color);

    const syncedPrimary = primary.map((tok, i) => {
      if (tok.color) return tok;
      const matchColor = secondary[i]?.color || coloredSecondary[i]?.color || coloredSecondary[0]?.color;
      return matchColor ? { ...tok, color: matchColor } : tok;
    });

    const result = {
      primaryTokens: syncedPrimary,
      secondaryTokens: secondary
    };

    if (tokenCache.size > 800) tokenCache.clear();
    tokenCache.set(key, result);
    return result;
  }

  let tokens = $derived(
    curWord
      ? getSynchronizedTokens(curWord.native, curWord.pronunciation, langConfig)
      : { primaryTokens: [], secondaryTokens: [] }
  );

  function startReview() {
    mode = 'review';
    isRevealed = false;
  }

  function startCram() {
    mode = 'cram';
    cramQueue = [...allCards].sort(() => Math.random() - 0.5);
    cramIndex = 0;
    isRevealed = false;
  }

  function handlePlayAudio() {
    if (!curWord) return;
    isPlayingAudio = true;
    playTTS(curWord.native, langCode || langConfig?.code || 'zh-CN', ttsRate);
    setTimeout(() => (isPlayingAudio = false), 1200);
  }

  function handleReveal() {
    isRevealed = true;
    handlePlayAudio();
  }

  async function handleSM2Grade(grade) {
    if (!curWord?.key || isSubmitting) return;
    isSubmitting = true;

    try {
      await srsStore.rateCard(langCode, curWord.key, grade);
      isRevealed = false;
    } catch (err) {
      console.error(`[SRS] Failed to grade card "${curWord.key}":`, err);
    } finally {
      isSubmitting = false;
    }
  }

  function handleCramFail() {
    if (!curWord) return;
    cramQueue.push(curWord);
    cramIndex++;
    isRevealed = false;
  }

  function handleCramPass() {
    cramIndex++;
    isRevealed = false;
  }
</script>

<!-- 🌟 PHYSICAL GLASS POD CONTAINER 🌟 -->
<div 
  class="relative flex flex-col gap-4 sm:gap-5 p-4 sm:p-6 rounded-3xl border border-black/10 dark:border-white/15 bg-white/70 dark:bg-[#12131a]/75 shadow-[0_20px_50px_-12px_rgba(0,0,0,0.25),inset_0_1px_1px_rgba(255,255,255,0.45)] dark:shadow-[0_24px_50px_-12px_rgba(0,0,0,0.7),inset_0_1px_1px_rgba(255,255,255,0.15)] select-none backdrop-blur-2xl backdrop-saturate-[180%] overflow-hidden box-border"
  style="--studio-theme: {listeningColor};"
>
  <!-- Top Specular Neon Lip -->
  <div 
    class="pointer-events-none absolute top-0 left-0 right-0 h-[2px] opacity-90 z-20"
    style="background: linear-gradient(90deg, transparent 5%, {listeningColor} 30%, {listeningColorSub} 70%, transparent 95%); box-shadow: 0 1px 12px {listeningColor};"
  ></div>

  <!-- Header & Controls Rail -->
  <div class="flex items-center justify-between flex-wrap gap-2.5 pt-0.5 relative z-10">
    <div class="flex items-center gap-2.5">
      <div 
        class="w-9 h-9 rounded-2xl flex items-center justify-center border shadow-inner"
        style="
          background-color: color-mix(in srgb, {listeningColor} 18%, transparent);
          border-color: color-mix(in srgb, {listeningColor} 38%, transparent);
          color: {listeningColor};
        "
      >
        <Headphones size={17} strokeWidth={2.5} class="animate-pulse" />
      </div>

      <div>
        <h2 class="text-xs sm:text-sm font-black tracking-tight uppercase text-neutral-900 dark:text-white flex items-center gap-1.5">
          <span>Tone Ear Trainer</span>
          <span class="w-1.5 h-1.5 rounded-full" style="background-color: {listeningColor}; box-shadow: 0 0 6px {listeningColor};"></span>
        </h2>
        <span class="text-[10px] font-mono text-neutral-500 dark:text-white/40 block">
          Auditory Tone Perception & Recognition
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
        style={mode === 'review' ? `background: linear-gradient(135deg, ${listeningColor}, ${listeningColorSub}); box-shadow: 0 2px 10px -2px ${listeningColor};` : ''}
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
        style={mode === 'cram' ? `background: linear-gradient(135deg, ${listeningColor}, ${listeningColorSub}); box-shadow: 0 2px 10px -2px ${listeningColor};` : ''}
      >
        <Zap size={12} strokeWidth={2.8} />
        <span>Cram ({allCards.length})</span>
      </button>
    </div>
  </div>

  {#if !curWord}
    <!-- Empty / Session Cleared State -->
    <div class="py-14 px-6 text-center space-y-3 rounded-2xl border border-dashed border-black/10 dark:border-white/10 bg-white/30 dark:bg-white/[0.02] backdrop-blur-md">
      <div 
        class="w-12 h-12 rounded-2xl flex items-center justify-center mx-auto border shadow-sm"
        style="
          background-color: color-mix(in srgb, {listeningColor} 18%, transparent);
          border-color: color-mix(in srgb, {listeningColor} 38%, transparent);
          color: {listeningColor};
        "
      >
        <CheckCircle2 size={24} strokeWidth={2.5} />
      </div>

      <div class="space-y-1">
        <h3 class="text-sm font-black text-neutral-900 dark:text-white tracking-tight">
          {mode === 'review' ? 'Queue Cleared for Today' : 'Hearing Cram Session Completed'}
        </h3>
        <p class="text-xs text-neutral-500 dark:text-white/40 max-w-xs mx-auto leading-relaxed">
          {mode === 'review' 
            ? `All scheduled auditory training cards are completed (${todayStr}).` 
            : 'You completed reviewing all listening recognition cards in the vault.'}
        </p>
      </div>

      {#if mode === 'cram' && allCards.length > 0}
        <button
          type="button"
          onclick={startCram}
          class="inline-flex items-center gap-1.5 px-4 py-2 rounded-xl text-xs font-black text-white cursor-pointer active:scale-95 transition-all shadow-md mt-2"
          style="background: linear-gradient(135deg, ${listeningColor},${listeningColorSub});"
        >
          <RotateCcw size={12} strokeWidth={2.8} />
          <span>Restart Cram Session</span>
        </button>
      {/if}
    </div>
  {:else}
    <!-- 🌟 3D GYROSCOPIC AUDITORY RECALL HERO STAGE 🌟 -->
    <div class="relative w-full [perspective:1000px] box-border">
      <div 
        bind:this={cardStageEl}
        role="presentation"
        onmousemove={handleStageMouseMove}
        onmouseenter={() => (isStageHovered = true)}
        onmouseleave={handleStageMouseLeave}
        class="relative w-full rounded-3xl border border-black/10 dark:border-white/15 bg-white/75 dark:bg-[#0c0d14]/85 shadow-2xl p-4 sm:p-6 flex flex-col items-center gap-5 text-center overflow-hidden will-change-transform transition-shadow duration-200"
        style="
          transform: {isStageHovered 
            ? `rotateX(${tiltX}deg) rotateY(${tiltY}deg) translateY(-3px) scale(1.008)` 
            : 'rotateX(0deg) rotateY(0deg) translateY(0) scale(1)'};
          transform-style: preserve-3d;
          transition: transform 0.12s cubic-bezier(0.16, 1, 0.3, 1), box-shadow 0.2s ease, border-color 0.2s ease;
          box-shadow: {isStageHovered 
            ? `0 24px 50px -12px rgba(0,0,0,0.65), 0 0 28px color-mix(in srgb, ${listeningColor} 25%, transparent)` 
            : '0 10px 30px -8px rgba(0,0,0,0.35)'};
        "
      >
        <!-- Full-Bleed Artwork / Listening Theme Backlight Aura -->
        {#if curWord.link && isRevealed}
          <div class="pointer-events-none absolute inset-0 rounded-3xl overflow-hidden -z-10">
            <img 
              src={curWord.link} 
              alt="" 
              aria-hidden="true" 
              class="w-full h-full object-cover blur-2xl scale-135 saturate-[240%] opacity-40 dark:opacity-50 transition-transform duration-500 transform-gpu"
            />
            <div class="absolute inset-0 bg-gradient-to-b from-white/40 via-white/15 to-white/85 dark:from-black/40 dark:via-black/20 dark:to-black/90"></div>
          </div>
        {:else}
          <div 
            class="pointer-events-none absolute inset-0 rounded-3xl opacity-25 -z-10"
            style="background: radial-gradient(circle 380px at 50% 25%, {listeningColor}, transparent 75%);"
          ></div>
        {/if}

        <!-- Specular Cursor Sheen -->
        <div 
          class="pointer-events-none absolute inset-0 opacity-0 transition-opacity duration-150 z-20 {isStageHovered ? 'opacity-100' : ''}"
          style="background: radial-gradient(circle 300px at {glareX}% {glareY}%, rgba(255,255,255,0.16), transparent 75%);"
        ></div>

        <!-- Top Specular Neon Lip -->
        <div 
          class="pointer-events-none absolute top-0 left-0 right-0 h-[2px] opacity-80 z-20"
          style="background: linear-gradient(90deg, transparent, {listeningColor}, {listeningColorSub}, transparent);"
        ></div>

        <!-- Top Pill Header (Metadata, Due Indicator & Playback Speed Stepper) -->
        <div class="w-full flex items-center justify-between text-[10px] font-mono font-bold text-neutral-500 dark:text-white/50 relative z-10 flex-wrap gap-2">
          <span class="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-xl bg-black/[0.04] dark:bg-white/[0.06] border border-black/[0.06] dark:border-white/10 shadow-2xs backdrop-blur-md">
            <Calendar size={10} />
            <span>{curWord.source_date ? curWord.source_date.slice(5) : 'Vault'}</span>
          </span>

          <!-- Audio Speed Tuner Capsule -->
          <div class="inline-flex items-center gap-1 px-2.5 py-1 rounded-xl bg-black/[0.04] dark:bg-white/[0.06] border border-black/[0.06] dark:border-white/10 shadow-2xs backdrop-blur-md">
            <Gauge size={11} style="color: {listeningColor};" />
            <span class="text-neutral-400 dark:text-white/40">Speed:</span>
            <input
              type="number"
              min="0.4"
              max="1.5"
              step="0.05"
              bind:value={ttsRate}
              class="w-10 bg-transparent border-none outline-none text-center font-bold text-neutral-900 dark:text-white p-0 cursor-pointer"
            />
            <span class="text-[9px]">x</span>
          </div>

          <span class="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-xl bg-black/[0.04] dark:bg-white/[0.06] border border-black/[0.06] dark:border-white/10 shadow-2xs backdrop-blur-md">
            <Clock size={10} />
            <span>Due: {curWord.due_date ? (curWord.due_date === todayStr ? 'Today' : curWord.due_date.slice(5)) : 'Immediate'}</span>
          </span>
        </div>

        <!-- Media Stage Arena: Acoustic Pulse Wave Before Reveal, Art Upon Reveal -->
        <div class="w-full max-w-[320px] mx-auto min-h-[190px] flex flex-col items-center justify-center p-4 rounded-2xl bg-black/[0.04] dark:bg-black/45 border border-white/20 shadow-inner overflow-hidden relative z-10">
          {#if isRevealed}
            <MediaStage
              src={curWord.link || ''}
              alt="Word Illustration"
              fallbackChar={curWord.native}
            />
          {:else}
            <!-- Acoustic Target Icon & Ripple -->
            <div class="relative flex items-center justify-center">
              <div 
                class="absolute w-28 h-28 rounded-full blur-xl opacity-30 animate-pulse pointer-events-none"
                style="background-color: {listeningColor};"
              ></div>
              <div 
                class="w-20 h-20 rounded-3xl flex items-center justify-center border shadow-xl transition-transform duration-200 {isPlayingAudio ? 'scale-110' : ''}"
                style="
                  background-color: color-mix(in srgb, {listeningColor} 16%, transparent);
                  border-color: color-mix(in srgb, {listeningColor} 38%, transparent);
                  color: {listeningColor};
                "
              >
                <Headphones size={36} strokeWidth={2.2} class={isPlayingAudio ? 'animate-bounce' : ''} />
              </div>
            </div>
            <span class="text-[11px] font-mono font-bold text-neutral-400 dark:text-white/40 mt-3 tracking-wide">
              Listen closely for tone inflection
            </span>
          {/if}
        </div>

        <!-- Audio Trigger & Reveal Action Controls -->
        <div class="flex items-center gap-2.5 flex-wrap justify-center relative z-10">
          <button
            type="button"
            onclick={handlePlayAudio}
            class="inline-flex items-center gap-2 px-6 py-2.5 rounded-2xl font-black text-xs text-white transition-all duration-150 active:scale-95 cursor-pointer border-none shadow-lg hover:brightness-105"
            style="
              background: linear-gradient(135deg, {listeningColor}, {listeningColorSub});
              box-shadow: 0 4px 18px -2px color-mix(in srgb, {listeningColor} 45%, transparent);
            "
          >
            <Volume2 size={15} strokeWidth={2.8} class={isPlayingAudio ? 'animate-pulse' : ''} />
            <span>Play Tone Audio</span>
          </button>

          {#if !isRevealed}
            <button
              type="button"
              onclick={handleReveal}
              class="inline-flex items-center gap-2 px-6 py-2.5 rounded-2xl font-bold text-xs bg-white/70 dark:bg-white/10 hover:bg-white dark:hover:bg-white/15 text-neutral-800 dark:text-white border border-black/10 dark:border-white/15 transition-all duration-150 active:scale-95 cursor-pointer shadow-xs backdrop-blur-md"
            >
              <Eye size={14} strokeWidth={2.5} />
              <span>Reveal Word</span>
            </button>
          {/if}
        </div>

        <!-- Revealed Details & Grading Action Deck -->
        {#if isRevealed}
          <div class="flex flex-col items-center gap-4 w-full border-t border-black/[0.08] dark:border-white/10 pt-4 relative z-10 animate-in fade-in slide-in-from-bottom-2 duration-200">
            
            <!-- Synchronized Tone-Colored Character Banner -->
            <div class="flex items-center justify-between gap-4 p-3.5 sm:p-4 rounded-2xl bg-white/60 dark:bg-black/50 border border-black/[0.08] dark:border-white/15 w-full max-w-md shadow-inner backdrop-blur-md">
              <div class="flex flex-col items-start gap-1 text-left min-w-0">
                <div class="text-3xl sm:text-4xl font-black tracking-tight leading-none drop-shadow-[0_2px_8px_rgba(0,0,0,0.6)]">
                  <ColoredText tokens={tokens.primaryTokens} fallbackClass="text-neutral-900 dark:text-white" />
                </div>

                {#if curWord.pronunciation}
                  <div class="text-sm sm:text-base font-mono font-bold tracking-tight mt-0.5 drop-shadow-[0_1px_4px_rgba(0,0,0,0.5)]">
                    <ColoredText tokens={tokens.secondaryTokens} fallbackClass="text-neutral-600 dark:text-white/70" />
                  </div>
                {/if}
              </div>

              <!-- Replay Pronounce Trigger -->
              <button
                type="button"
                onclick={handlePlayAudio}
                class="flex items-center gap-1.5 px-3 py-2 rounded-xl text-xs font-bold border transition-all active:scale-90 cursor-pointer shrink-0 shadow-2xs backdrop-blur-md"
                style="
                  background-color: color-mix(in srgb, {listeningColor} 18%, transparent);
                  border-color: color-mix(in srgb, {listeningColor} 38%, transparent);
                  color: {listeningColor};
                "
                title="Replay pronunciation"
              >
                <Volume2 size={13} class={isPlayingAudio ? 'animate-pulse' : ''} />
                <span>Replay</span>
              </button>
            </div>

            <!-- SM-2 Rating Deck -->
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
  {/if}
</div>