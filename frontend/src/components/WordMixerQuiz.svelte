<!-- frontend/src/components/WordMixerQuiz.svelte -->
<script>
  import { vocabIndexStore } from '../lib/stores/vocabIndex.svelte.js';
  import { activeLanguage } from '../lib/stores/activeLanguage.svelte.js';
  import { tokenizePhonetics } from '../lib/formatters/phonetics.js';
  import { playTTS } from '../lib/tts.js';
  import MediaStage from './MediaStage.svelte';
  import ColoredText from './ColoredText.svelte';

  // Razor-sharp vector icons
  import { 
    Dice5, 
    Sparkles, 
    Volume2, 
    Calendar, 
    Image, 
    Layers, 
    Plus,
    Minus
  } from '@lucide/svelte';

  let { 
    langCode,
    minCount = 2,
    maxCount = 10,
    defaultCount = 2,
    onSelectDate = null
  } = $props();

  let selectedCount = $state(2);
  let showText = $state(true);
  let mixedWords = $state([]);
  let scrollTrack = $state(null);
  let speakingWord = $state(null);

  // 🌟 GYRO / TILT STATE (rAF-Throttled) 🌟
  let activeCardIndex = $state(null);
  let tiltX = $state(0);
  let tiltY = $state(0);
  let glareX = $state(50);
  let glareY = $state(50);
  let tiltTicking = false;

  function handleCardMouseMove(e, idx) {
    if (activeCardIndex !== idx) activeCardIndex = idx;
    if (tiltTicking) return;
    tiltTicking = true;

    const rect = e.currentTarget.getBoundingClientRect();
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

  function handleCardMouseLeave() {
    activeCardIndex = null;
    tiltX = 0;
    tiltY = 0;
    glareX = 50;
    glareY = 50;
  }

  // 🌟 SYNCHRONIZED TONE CHROMA ENGINE 🌟
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

  $effect(() => {
    selectedCount = defaultCount;
  });

  let langConfig = $derived(activeLanguage.current);
  let pool = $derived(vocabIndexStore.entries || []);
  let colors = $derived(activeLanguage.colors || {});
  let themeColor = $derived(activeLanguage.themeColor || colors.theme || '#a855f7');

  function pickRandomWords(sourceList, count) {
    if (!sourceList || sourceList.length === 0) return [];
    const poolCopy = [...sourceList];
    const n = Math.min(count, poolCopy.length);
    const result = [];

    for (let i = 0; i < n; i++) {
      const randIdx = Math.floor(Math.random() * poolCopy.length);
      result.push(poolCopy[randIdx]);
      poolCopy.splice(randIdx, 1);
    }
    return result;
  }

  function forgeNewCombination() {
    mixedWords = pickRandomWords(pool, selectedCount);
    if (scrollTrack) {
      scrollTrack.scrollTo({ left: 0, behavior: 'smooth' });
    }
  }

  function adjustCount(delta) {
    const next = selectedCount + delta;
    if (next >= minCount && next <= maxCount) {
      selectedCount = next;
      forgeNewCombination();
    }
  }

  $effect(() => {
    if (pool.length > 0 && mixedWords.length === 0) {
      forgeNewCombination();
    }
  });

  function handlePronounce(e, native) {
    e.stopPropagation();
    if (!native) return;
    speakingWord = native;
    playTTS(native, langCode || langConfig?.code || 'zh-CN');
    setTimeout(() => {
      if (speakingWord === native) speakingWord = null;
    }, 1200);
  }
</script>

<!-- 🌟 PHYSICAL GLASS POD CONTAINER 🌟 -->
<div 
  class="relative flex flex-col gap-4 p-4 sm:p-6 rounded-3xl border border-black/10 dark:border-white/15 bg-white/70 dark:bg-[#12131a]/75 shadow-[0_20px_50px_-12px_rgba(0,0,0,0.25),inset_0_1px_1px_rgba(255,255,255,0.45)] dark:shadow-[0_24px_50px_-12px_rgba(0,0,0,0.7),inset_0_1px_1px_rgba(255,255,255,0.15)] select-none backdrop-blur-2xl backdrop-saturate-[180%] overflow-hidden box-border"
  style="--theme-accent: {themeColor};"
>
  <!-- Top Specular Neon Highlight Lip -->
  <div 
    class="pointer-events-none absolute top-0 left-0 right-0 h-[2px] opacity-90 z-20"
    style="background: linear-gradient(90deg, transparent 5%, {themeColor} 30%, color-mix(in srgb, {themeColor} 60%, white) 70%, transparent 95%); box-shadow: 0 1px 12px {themeColor};"
  ></div>

  <!-- Header & Controls Rail -->
  <div class="flex items-center justify-between flex-wrap gap-2.5 pt-0.5 relative z-10">
    <div class="flex items-center gap-2.5">
      <div 
        class="w-9 h-9 rounded-2xl flex items-center justify-center border shadow-inner"
        style="
          background-color: color-mix(in srgb, {themeColor} 18%, transparent);
          border-color: color-mix(in srgb, {themeColor} 40%, transparent);
          color: {themeColor};
        "
      >
        <Dice5 size={18} strokeWidth={2.5} class="animate-pulse" />
      </div>

      <div>
        <h2 class="text-xs sm:text-sm font-black tracking-tight uppercase text-neutral-900 dark:text-white flex items-center gap-1.5">
          <span>Sentence Forge</span>
          <span class="w-1.5 h-1.5 rounded-full" style="background-color: {themeColor}; box-shadow: 0 0 6px {themeColor};"></span>
        </h2>
        <span class="text-[10px] font-mono text-neutral-500 dark:text-white/40 block">
          Combinatorial Lexical Synthesizer
        </span>
      </div>
    </div>

    <!-- Controls Dock -->
    <div class="flex items-center gap-2 flex-wrap ml-auto">
      <!-- Full Card vs Image Only Toggle -->
      <button
        type="button"
        onclick={() => (showText = !showText)}
        class="flex items-center gap-1.5 px-3 py-1.5 text-xs font-bold rounded-xl border border-black/10 dark:border-white/10 bg-white/70 dark:bg-white/[0.06] text-neutral-800 dark:text-white/90 hover:bg-white dark:hover:bg-white/15 transition-all cursor-pointer shadow-xs active:scale-95"
      >
        {#if showText}
          <Layers size={12} style="color: {themeColor};" />
          <span>Full Card</span>
        {:else}
          <Image size={12} style="color: {themeColor};" />
          <span>Image Only</span>
        {/if}
      </button>

      <!-- 🌟 ELEVATED QUANTITY STEPPER (+ / Count / -) 🌟 -->
      <div class="flex items-center gap-1.5 px-2 py-1 rounded-2xl bg-black/[0.04] dark:bg-white/[0.05] border border-black/[0.08] dark:border-white/[0.1] shadow-inner">
        <button
          type="button"
          onclick={() => adjustCount(-1)}
          disabled={selectedCount <= minCount}
          aria-label="Decrease cards"
          class="w-6 h-6 rounded-xl bg-white/60 dark:bg-white/10 hover:bg-white dark:hover:bg-white/20 text-neutral-700 dark:text-white/80 flex items-center justify-center transition-all active:scale-85 cursor-pointer disabled:opacity-30 disabled:pointer-events-none shadow-2xs"
        >
          <Minus size={11} strokeWidth={2.8} />
        </button>

        <span class="font-mono text-xs font-black px-1.5 min-w-[20px] text-center" style="color: {themeColor};">
          {selectedCount}
        </span>

        <button
          type="button"
          onclick={() => adjustCount(1)}
          disabled={selectedCount >= maxCount}
          aria-label="Increase cards"
          class="w-6 h-6 rounded-xl bg-white/60 dark:bg-white/10 hover:bg-white dark:hover:bg-white/20 text-neutral-700 dark:text-white/80 flex items-center justify-center transition-all active:scale-85 cursor-pointer disabled:opacity-30 disabled:pointer-events-none shadow-2xs"
        >
          <Plus size={11} strokeWidth={2.8} />
        </button>
      </div>
    </div>
  </div>

  <!-- Instruction Subtitle -->
  <div class="text-[11px] text-neutral-500 dark:text-white/50 leading-relaxed -mt-1 font-medium relative z-10">
    Construct a cohesive sentence or dialogue integrating all <span class="font-mono font-black" style="color: {themeColor};">{selectedCount}</span> active cards below:
  </div>

  <!-- Cards Horizontal 3D Gyroscopic Stage Track -->
  {#if pool.length === 0}
    <div class="py-12 text-center text-xs text-neutral-500 dark:text-white/40 italic border border-dashed border-black/10 dark:border-white/10 rounded-2xl bg-white/20 dark:bg-black/20">
      ⚠️ No vocabulary items logged yet. Add vocabulary to your day logs to unlock combinations.
    </div>
  {:else}
    <div
      bind:this={scrollTrack}
      class="flex items-center gap-3 w-full overflow-x-auto overscroll-x-contain py-3 px-1 touch-pan-x [perspective:1000px] scroll-smooth no-scrollbar relative z-10"
    >
      {#each mixedWords as item, index (item.word_id || `${item.native_script}-${index}`)}
        {@const tokens = getSynchronizedTokens(item.native_script, item.pronunciation, langConfig)}
        {@const isCardActive = activeCardIndex === index}
        {@const isSpeaking = speakingWord === item.native_script}

        <!-- 🌟 3D TACTILE WORD CARD WITH HARMONIZED THEME BACKLIGHT 🌟 -->
        <div
          role="presentation"
          onmousemove={(e) => handleCardMouseMove(e, index)}
          onmouseleave={handleCardMouseLeave}
          class="group/card relative flex flex-col items-center justify-between p-3 rounded-3xl border border-black/10 dark:border-white/15 bg-white/75 dark:bg-[#12131a]/80 text-center shrink-0 select-none overflow-hidden will-change-transform cursor-pointer transition-shadow duration-200"
          style="
            width: {showText ? '160px' : '142px'};
            min-height: {showText ? '228px' : '182px'};
            transform: {isCardActive ? `rotateX(${tiltX}deg) rotateY(${tiltY}deg) translateY(-4px) scale(1.02)` : 'rotateX(0deg) rotateY(0deg) translateY(0) scale(1)'};
            transform-style: preserve-3d;
            transition: transform 0.12s cubic-bezier(0.16, 1, 0.3, 1), box-shadow 0.2s ease, border-color 0.2s ease;
            box-shadow: {isCardActive 
              ? `0 16px 36px -10px rgba(0,0,0,0.5), 0 0 22px color-mix(in srgb, ${themeColor} 30%, transparent)` 
              : '0 4px 18px -4px rgba(0,0,0,0.15)'};
          "
        >
          <!-- Full-Bleed Artwork Backlight Canvas (Theme Harmonized) -->
          {#if item.link}
            <div class="pointer-events-none absolute inset-0 rounded-3xl overflow-hidden -z-10">
              <img 
                src={item.link} 
                alt="" 
                aria-hidden="true" 
                class="w-full h-full object-cover blur-2xl scale-135 saturate-[220%] opacity-40 dark:opacity-50 transition-transform duration-500 group-hover/card:scale-150 transform-gpu"
              />
              <div class="absolute inset-0 bg-gradient-to-b from-white/35 via-white/15 to-white/80 dark:from-black/35 dark:via-black/20 dark:to-black/85"></div>
            </div>
          {:else}
            <div 
              class="pointer-events-none absolute inset-0 rounded-3xl opacity-30 -z-10"
              style="background: radial-gradient(circle at center, {themeColor} 0%, transparent 75%);"
            ></div>
          {/if}

          <!-- Specular Sheen Layer -->
          <div 
            class="pointer-events-none absolute inset-0 opacity-0 transition-opacity duration-150 z-20 {isCardActive ? 'opacity-100' : ''}"
            style="background: radial-gradient(circle 200px at {glareX}% {glareY}%, rgba(255,255,255,0.22), transparent 75%);"
          ></div>

          <!-- Top Specular Lip -->
          <div 
            class="pointer-events-none absolute top-0 left-0 right-0 h-[2px] opacity-80 z-20"
            style="background: linear-gradient(90deg, transparent, {themeColor}, color-mix(in srgb, {themeColor} 60%, white), transparent);"
          ></div>

          <!-- Top Header: Index / Date Navigation -->
          <div class="w-full flex items-center justify-between gap-1 pb-1 relative z-10">
            {#if item.date && onSelectDate}
              <button
                type="button"
                onclick={() => onSelectDate(item.date)}
                class="inline-flex items-center gap-1 font-mono text-[9px] font-bold text-neutral-600 dark:text-white/60 bg-black/[0.04] dark:bg-black/40 px-2 py-0.5 rounded-lg border border-white/20 backdrop-blur-md shadow-2xs transition-colors cursor-pointer"
                title="View original day log"
              >
                <Calendar size={9} />
                <span>{item.date.slice(5)}</span>
              </button>
            {:else}
              <span class="font-mono text-[9px] font-bold text-neutral-600 dark:text-white/60 bg-black/[0.04] dark:bg-black/40 px-2 py-0.5 rounded-lg border border-white/20 shadow-2xs">
                #{index + 1}
              </span>
            {/if}

            <button
              type="button"
              onclick={(e) => handlePronounce(e, item.native_script)}
              class="p-1 rounded-lg text-neutral-600 dark:text-white/60 hover:text-neutral-900 dark:hover:text-white bg-black/[0.04] dark:bg-black/40 border border-white/20 hover:border-white/40 transition-transform active:scale-80 cursor-pointer shadow-2xs"
              title="Play pronunciation"
            >
              <Volume2 size={11} class={isSpeaking ? 'text-emerald-400 animate-pulse' : ''} />
            </button>
          </div>

          <!-- Media Stage Box -->
          <div class="relative w-full h-24 my-auto flex items-center justify-center rounded-2xl bg-black/[0.04] dark:bg-black/35 border border-white/20 overflow-hidden pointer-events-none shadow-inner z-10">
            <MediaStage
              src={item.link || ''}
              alt={item.native_script}
              fallbackChar={item.native_script}
              observerRoot={scrollTrack}
            />
          </div>

          <!-- Synchronized Tone-Colored Text -->
          {#if showText}
            <div class="w-full pt-1.5 space-y-0.5 relative z-10">
              <div class="w-full text-base font-black truncate leading-tight tracking-tight drop-shadow-[0_2px_8px_rgba(0,0,0,0.6)]">
                <ColoredText tokens={tokens.primaryTokens} fallbackClass="text-neutral-900 dark:text-white" />
              </div>
              <div class="w-full text-[11px] font-mono font-bold truncate leading-tight drop-shadow-[0_1px_4px_rgba(0,0,0,0.5)]">
                <ColoredText tokens={tokens.secondaryTokens} fallbackClass="text-neutral-700 dark:text-white/80" />
              </div>
            </div>
          {/if}
        </div>

        <!-- Floating Glass Fusion Connector '+' Capsule -->
        {#if index < mixedWords.length - 1}
          <div 
            class="flex items-center justify-center w-7 h-7 rounded-full border shadow-sm shrink-0 select-none pointer-events-none backdrop-blur-md"
            style="
              background-color: color-mix(in srgb, {themeColor} 18%, transparent);
              border-color: color-mix(in srgb, {themeColor} 40%, transparent);
              color: {themeColor};
              box-shadow: 0 0 14px color-mix(in srgb, {themeColor} 30%, transparent);
            "
          >
            <Plus size={14} strokeWidth={3} />
          </div>
        {/if}
      {/each}
    </div>
  {/if}

  <!-- Bottom Bar: Pool Status & Roll Combination Button -->
  <div class="flex items-center justify-between flex-wrap gap-2.5 pt-2 border-t border-black/[0.06] dark:border-white/[0.08] relative z-10">
    <div class="flex items-center gap-2">
      <span class="w-1.5 h-1.5 rounded-full" style="background-color: {themeColor}; box-shadow: 0 0 6px {themeColor};"></span>
      <span class="text-[11px] font-mono font-bold text-neutral-600 dark:text-white/60">
        Vault Pool: <strong class="text-neutral-900 dark:text-white">{pool.length}</strong> active words
      </span>
    </div>

    <button
      type="button"
      onclick={forgeNewCombination}
      disabled={pool.length === 0}
      class="inline-flex items-center gap-2 px-4 py-2 rounded-2xl font-black text-xs text-white transition-all duration-150 active:scale-95 cursor-pointer border-none shadow-md hover:brightness-105 disabled:opacity-50"
      style="
        background: linear-gradient(135deg, {themeColor}, color-mix(in srgb, {themeColor} 70%, black));
        box-shadow: 0 4px 16px -2px color-mix(in srgb, {themeColor} 45%, transparent);
      "
    >
      <Dice5 size={14} strokeWidth={2.8} />
      <span>Forge New Combination</span>
    </button>
  </div>
</div>