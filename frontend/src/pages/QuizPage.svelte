<!-- frontend/src/pages/QuizPage.svelte -->
<script>
  import { srsStore } from '../lib/stores/srs.svelte.js';
  import { vocabIndexStore } from '../lib/stores/vocabIndex.svelte.js';
  import WordMixerQuiz from '../components/WordMixerQuiz.svelte';
  import VisualQuiz from '../components/VisualQuiz.svelte';
  import HearingQuiz from '../components/HearingQuiz.svelte';

  let { 
    langCode,
    onSelectDate = null 
  } = $props();

  let todayStr = new Date().toISOString().substring(0, 10);

  let visualDue = $derived(srsStore.getVisualDueCount(todayStr));
  let audioDue = $derived(srsStore.getAudioDueCount(todayStr));
  let totalDue = $derived(visualDue + audioDue);
  let totalWords = $derived((vocabIndexStore.entries || []).length);
</script>

<div class="max-w-2xl mx-auto py-4 px-3 space-y-7 pb-16">
  <!-- Page Header & Summary Strip -->
  <header class="flex items-center justify-between flex-wrap gap-3 pb-3 border-b border-[var(--border-card)]">
    <div>
      <h1 class="text-lg sm:text-xl font-black tracking-tight text-[var(--text-primary)] flex items-center gap-2">
        <span>⚡</span> Study & Recall Studio
      </h1>
      <p class="text-xs text-[var(--text-muted)] mt-0.5">
        Sentence synthesis sandbox and SM-2 spaced repetition decks
      </p>
    </div>

    <!-- Live Metric Chips -->
    <div class="flex items-center gap-2 text-xs font-mono font-bold">
      <div 
        class="flex items-center gap-1.5 px-3 py-1.5 rounded-xl border transition-colors {totalDue > 0 
          ? 'bg-amber-500/10 border-amber-500/30 text-amber-500' 
          : 'bg-emerald-500/10 border-emerald-500/30 text-emerald-500'}"
      >
        <span>{totalDue > 0 ? '🎯' : '✨'}</span>
        <span>{totalDue} Due</span>
      </div>

      <div class="flex items-center gap-1.5 px-3 py-1.5 rounded-xl border border-[var(--border-card)] bg-[var(--bg-surface)] text-[var(--text-muted)]">
        <span>📚</span>
        <span>{totalWords} Words</span>
      </div>
    </div>
  </header>

  <!-- Section 1: Sandbox / Generator (Mixer First) -->
  <section class="space-y-2">
    <div class="flex items-center justify-between px-1">
      <div class="flex items-center gap-2">
        <span class="text-xs font-black uppercase tracking-wider text-pink-500 font-mono">Stage 01</span>
        <span class="text-xs text-[var(--text-muted)]">• Creative Synthesis</span>
      </div>
    </div>
    <WordMixerQuiz {langCode} {onSelectDate} />
  </section>

  <!-- Styled Divider with Label -->
  <div class="relative flex items-center justify-center my-6">
    <div class="absolute inset-0 flex items-center">
      <div class="w-full border-t border-[var(--border-card)] border-dashed"></div>
    </div>
    <span class="relative px-3 py-0.5 bg-[var(--bg-base)] text-[10px] font-mono uppercase tracking-widest text-[var(--text-muted)] rounded-full border border-[var(--border-card)]">
      Active SRS Decks
    </span>
  </div>

  <!-- Section 2: Visual Recall Arena -->
  <section class="space-y-2">
    <div class="flex items-center justify-between px-1">
      <div class="flex items-center gap-2">
        <span class="text-xs font-black uppercase tracking-wider text-emerald-500 font-mono">Stage 02</span>
        <span class="text-xs text-[var(--text-muted)]">• Visual Recognition</span>
      </div>
      {#if visualDue > 0}
        <span class="text-[11px] font-mono font-bold text-emerald-500 px-2 py-0.5 rounded-md bg-emerald-500/10">
          {visualDue} cards ready
        </span>
      {/if}
    </div>
    <VisualQuiz {langCode} />
  </section>

  <!-- Divider Line -->
  <div class="relative flex items-center justify-center my-4">
    <div class="w-full border-t border-[var(--border-card)]"></div>
  </div>

  <!-- Section 3: Listening Tone Ear Trainer -->
  <section class="space-y-2">
    <div class="flex items-center justify-between px-1">
      <div class="flex items-center gap-2">
        <span class="text-xs font-black uppercase tracking-wider text-purple-500 font-mono">Stage 03</span>
        <span class="text-xs text-[var(--text-muted)]">• Auditory & Pitch Recall</span>
      </div>
      {#if audioDue > 0}
        <span class="text-[11px] font-mono font-bold text-purple-500 px-2 py-0.5 rounded-md bg-purple-500/10">
          {audioDue} cards ready
        </span>
      {/if}
    </div>
    <HearingQuiz {langCode} />
  </section>
</div>