<!-- frontend/src/pages/QuizPage.svelte -->
<script>
  import { srsStore } from '../lib/stores/srs.svelte.js';
  import { vocabIndexStore } from '../lib/stores/vocabIndex.svelte.js';
  import { activeLanguage } from '../lib/stores/activeLanguage.svelte.js';
  import WordMixerQuiz from '../components/WordMixerQuiz.svelte';
  import VisualQuiz from '../components/VisualQuiz.svelte';
  import HearingQuiz from '../components/HearingQuiz.svelte';

  // Razor-sharp vector icons
  import { 
    Zap, 
    Sparkles, 
    Target, 
    Layers, 
    Dice5, 
    Eye, 
    Headphones,
    BookOpen
  } from '@lucide/svelte';

  let { 
    langCode,
    onSelectDate = null 
  } = $props();

  let todayStr = new Date().toISOString().substring(0, 10);

  let colors = $derived(activeLanguage.colors || {});
  let themeColor = $derived(activeLanguage.themeColor || colors.theme || '#a855f7');
  let vocabColor = $derived(colors.vocab?.primary || colors.vocab?.dark_primary || '#10b981');
  let listeningColor = $derived(colors.listening?.primary || colors.listening?.dark_primary || '#f97316');

  let visualDue = $derived(srsStore.getVisualDueCount ? srsStore.getVisualDueCount(todayStr) : 0);
  let audioDue = $derived(srsStore.getAudioDueCount ? srsStore.getAudioDueCount(todayStr) : 0);
  let totalDue = $derived(visualDue + audioDue);
  let totalWords = $derived((vocabIndexStore.entries || []).length);
</script>

<div 
  class="relative w-full max-w-5xl xl:max-w-6xl mx-auto space-y-10 pt-1 sm:pt-2 pb-24 px-2 sm:px-4 md:px-6 select-none box-border"
  style="--quiz-theme: {themeColor};"
>
  
  <!-- 🌟 1. UNIFIED VISIONOS HEADER GLASS POD 🌟 -->
  <header 
    class="relative flex items-center justify-between p-4 sm:p-5 rounded-3xl border border-black/10 dark:border-white/15 bg-white/70 dark:bg-[#12131a]/75 backdrop-blur-2xl backdrop-saturate-[180%] shadow-[0_20px_50px_-12px_rgba(0,0,0,0.18),inset_0_1px_1px_rgba(255,255,255,0.45)] dark:shadow-[0_24px_50px_-12px_rgba(0,0,0,0.7),inset_0_1px_1px_rgba(255,255,255,0.15)] overflow-hidden flex-wrap gap-3"
  >
    <!-- Top Specular Neon Highlight Lip -->
    <div 
      class="pointer-events-none absolute top-0 left-0 right-0 h-[2px] opacity-90 z-20"
      style="background: linear-gradient(90deg, transparent 5%, var(--quiz-theme) 30%, color-mix(in srgb, var(--quiz-theme) 60%, white) 70%, transparent 95%); box-shadow: 0 1px 12px var(--quiz-theme);"
    ></div>

    <div class="flex items-center gap-3 min-w-0 relative z-10">
      <div 
        class="w-10 h-10 rounded-2xl flex items-center justify-center border shadow-inner shrink-0"
        style="
          background-color: color-mix(in srgb, var(--quiz-theme) 18%, transparent);
          border-color: color-mix(in srgb, var(--quiz-theme) 38%, transparent);
          color: var(--quiz-theme);
        "
      >
        <Zap size={20} strokeWidth={2.5} class="animate-pulse" />
      </div>

      <div class="space-y-0.5">
        <h1 class="text-sm sm:text-base font-black tracking-tight text-neutral-900 dark:text-white flex items-center gap-1.5">
          <span>Study & Recall Studio</span>
          <span class="w-1.5 h-1.5 rounded-full" style="background-color: var(--quiz-theme); box-shadow: 0 0 6px var(--quiz-theme);"></span>
        </h1>
        <p class="text-[11px] text-neutral-500 dark:text-white/50 font-medium">
          Combinatorial sentence synthesis and active spaced repetition decks
        </p>
      </div>
    </div>

    <!-- Live Telemetry Badges -->
    <div class="flex items-center gap-2 font-mono text-xs font-bold relative z-10">
      <div 
        class="flex items-center gap-1.5 px-3 py-1.5 rounded-2xl border shadow-xs transition-colors"
        style="
          color: {totalDue > 0 ? '#f59e0b' : '#10b981'};
          background-color: color-mix(in srgb, {totalDue > 0 ? '#f59e0b' : '#10b981'} 15%, transparent);
          border-color: color-mix(in srgb, {totalDue > 0 ? '#f59e0b' : '#10b981'} 35%, transparent);
          box-shadow: 0 0 12px color-mix(in srgb, {totalDue > 0 ? '#f59e0b' : '#10b981'} 15%, transparent);
        "
      >
        {#if totalDue > 0}
          <Target size={13} strokeWidth={2.8} />
          <span>{totalDue} Due</span>
        {:else}
          <Sparkles size={13} strokeWidth={2.8} />
          <span>Queue Cleared</span>
        {/if}
      </div>

      <div class="flex items-center gap-1.5 px-3 py-1.5 rounded-2xl border border-black/10 dark:border-white/10 bg-white/60 dark:bg-white/[0.05] text-neutral-600 dark:text-white/70 shadow-2xs">
        <BookOpen size={13} style="color: var(--quiz-theme);" />
        <span>{totalWords} Words</span>
      </div>
    </div>
  </header>

  <!-- 🌟 STAGE 1: CREATIVE SENTENCE FORGE (Mixer) 🌟 -->
  <section class="space-y-4 relative">
    <!-- Lateral Flank Bleed (Left and Right) -->
    <div 
      class="pointer-events-none absolute -left-24 top-1/2 -translate-y-1/2 w-48 h-[120%] rounded-full blur-[90px] opacity-25 -z-10"
      style="background: radial-gradient(circle at 0% 50%, var(--quiz-theme), transparent 75%);"
    ></div>
    <div 
      class="pointer-events-none absolute -right-24 top-1/2 -translate-y-1/2 w-48 h-[120%] rounded-full blur-[90px] opacity-25 -z-10"
      style="background: radial-gradient(circle at 100% 50%, var(--quiz-theme), transparent 75%);"
    ></div>

    <!-- Section Bridge -->
    <div class="flex items-center gap-3">
      <div class="flex-1 h-px bg-gradient-to-r from-transparent via-[var(--border-subtle)] to-transparent"></div>
      <div 
        class="flex items-center gap-2 px-3.5 py-1 rounded-full bg-[var(--bg-surface)] border shadow-xs"
        style="border-color: color-mix(in srgb, var(--quiz-theme) 35%, var(--border-subtle));"
      >
        <Dice5 size={12} style="color: var(--quiz-theme);" />
        <span class="text-[10px] font-mono font-bold uppercase tracking-widest text-[var(--text-primary)]">
          Stage 01 • Creative Synthesis
        </span>
      </div>
      <div class="flex-1 h-px bg-gradient-to-r from-transparent via-[var(--border-subtle)] to-transparent"></div>
    </div>

    <WordMixerQuiz {langCode} {onSelectDate} />
  </section>

  <!-- 🌟 STAGE 2: VISUAL RECALL STUDIO 🌟 -->
  <section class="space-y-4 relative">
    <!-- Lateral Flank Bleed -->
    <div 
      class="pointer-events-none absolute -left-24 top-1/2 -translate-y-1/2 w-48 h-[120%] rounded-full blur-[90px] opacity-25 -z-10"
      style="background: radial-gradient(circle at 0% 50%, {vocabColor}, transparent 75%);"
    ></div>
    <div 
      class="pointer-events-none absolute -right-24 top-1/2 -translate-y-1/2 w-48 h-[120%] rounded-full blur-[90px] opacity-25 -z-10"
      style="background: radial-gradient(circle at 100% 50%, {vocabColor}, transparent 75%);"
    ></div>

    <!-- Section Bridge -->
    <div class="flex items-center gap-3">
      <div class="flex-1 h-px bg-gradient-to-r from-transparent via-[var(--border-subtle)] to-transparent"></div>
      <div 
        class="flex items-center gap-2 px-3.5 py-1 rounded-full bg-[var(--bg-surface)] border shadow-xs"
        style="border-color: color-mix(in srgb, {vocabColor} 35%, var(--border-subtle));"
      >
        <Eye size={12} style="color: {vocabColor};" />
        <span class="text-[10px] font-mono font-bold uppercase tracking-widest text-[var(--text-primary)]">
          Stage 02 • Visual Recognition
        </span>
        {#if visualDue > 0}
          <span 
            class="text-[10px] font-mono font-bold px-1.5 rounded-full" 
            style="background-color: color-mix(in srgb, {vocabColor} 18%, transparent); color: {vocabColor};"
          >
            {visualDue} due
          </span>
        {/if}
      </div>
      <div class="flex-1 h-px bg-gradient-to-r from-transparent via-[var(--border-subtle)] to-transparent"></div>
    </div>

    <VisualQuiz {langCode} />
  </section>

  <!-- 🌟 STAGE 3: TONE EAR TRAINER 🌟 -->
  <section class="space-y-4 relative">
    <!-- Lateral Flank Bleed -->
    <div 
      class="pointer-events-none absolute -left-24 top-1/2 -translate-y-1/2 w-48 h-[120%] rounded-full blur-[90px] opacity-25 -z-10"
      style="background: radial-gradient(circle at 0% 50%, {listeningColor}, transparent 75%);"
    ></div>
    <div 
      class="pointer-events-none absolute -right-24 top-1/2 -translate-y-1/2 w-48 h-[120%] rounded-full blur-[90px] opacity-25 -z-10"
      style="background: radial-gradient(circle at 100% 50%, {listeningColor}, transparent 75%);"
    ></div>

    <!-- Section Bridge -->
    <div class="flex items-center gap-3">
      <div class="flex-1 h-px bg-gradient-to-r from-transparent via-[var(--border-subtle)] to-transparent"></div>
      <div 
        class="flex items-center gap-2 px-3.5 py-1 rounded-full bg-[var(--bg-surface)] border shadow-xs"
        style="border-color: color-mix(in srgb, {listeningColor} 35%, var(--border-subtle));"
      >
        <Headphones size={12} style="color: {listeningColor};" />
        <span class="text-[10px] font-mono font-bold uppercase tracking-widest text-[var(--text-primary)]">
          Stage 03 • Auditory & Pitch Recall
        </span>
        {#if audioDue > 0}
          <span 
            class="text-[10px] font-mono font-bold px-1.5 rounded-full" 
            style="background-color: color-mix(in srgb, {listeningColor} 18%, transparent); color: {listeningColor};"
          >
            {audioDue} due
          </span>
        {/if}
      </div>
      <div class="flex-1 h-px bg-gradient-to-r from-transparent via-[var(--border-subtle)] to-transparent"></div>
    </div>

    <HearingQuiz {langCode} />
  </section>

</div>