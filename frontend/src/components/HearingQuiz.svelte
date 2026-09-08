<!-- frontend/src/components/HearingQuiz.svelte -->
<script>
  import { srsStore } from '../lib/stores/srs.svelte.js';
  import { activeLanguage } from '../lib/stores/activeLanguage.svelte.js';
  import { getIntervalPreview } from '../lib/srsEngine.js';
  import { tokenizePhonetics } from '../lib/formatters/phonetics.js';
  import { playTTS } from '../lib/tts.js';
  import MediaStage from './MediaStage.svelte';
  import ColoredText from './ColoredText.svelte';

  let { langCode } = $props();

  let todayStr = new Date().toISOString().substring(0, 10);
  let mode = $state('review'); // 'review' | 'cram'
  let ttsRate = $state(0.85);
  let isRevealed = $state(false);
  let isSubmitting = $state(false);

  let cramQueue = $state([]);
  let cramIndex = $state(0);

  let langConfig = $derived(activeLanguage.current);

  // Read from srsStore.cards (matching the migration schema)
  let allCards = $derived.by(() => {
    const raw = srsStore.cards || {};
    const cards = [];

    for (const [key, item] of Object.entries(raw)) {
      if (item && item.card_type === 'listening') {
        const isDue = !item.due_date || item.due_date <= todayStr;
        cards.push({
          key,
          ...item,
          isDue
        });
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

  // Compute tone color tokens for the revealed native script and pronunciation
  let tokens = $derived(
    curWord
      ? tokenizePhonetics(curWord.native, curWord.pronunciation, langConfig)
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
    playTTS(curWord.native, langCode, ttsRate);
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

<div class="audio-trainer-main-card relative flex flex-col gap-3.5 p-4 sm:p-5 rounded-2xl bg-[var(--bg-surface)] border border-[var(--border-card)] shadow-xs select-none overflow-hidden">
  <div class="absolute top-0 left-0 right-0 h-[3px] bg-gradient-to-r from-purple-500 to-blue-500 opacity-90"></div>

  <!-- Top Header with Mode Switchers -->
  <div class="flex items-center justify-between flex-wrap gap-2 pt-0.5">
    <div class="flex items-center gap-2">
      <span class="text-base">🎧</span>
      <span class="text-xs font-extrabold tracking-wide text-[var(--text-primary)]">
        Tone Ear Trainer
      </span>
    </div>

    <div class="flex items-center gap-1.5">
      <button
        onclick={startReview}
        class="px-3 py-1 text-xs font-extrabold rounded-lg border transition-all cursor-pointer {mode === 'review' 
          ? 'bg-[var(--interactive-accent,var(--text-primary))] text-[var(--bg-base)] border-transparent' 
          : 'bg-[var(--bg-base)] text-[var(--text-primary)] border-[var(--border-card)]'}"
      >
        🎯 Due ({dueCards.length})
      </button>

      <button
        onclick={startCram}
        class="px-3 py-1 text-xs font-extrabold rounded-lg border transition-all cursor-pointer {mode === 'cram' 
          ? 'bg-[var(--interactive-accent,var(--text-primary))] text-[var(--bg-base)] border-transparent' 
          : 'bg-[var(--bg-base)] text-[var(--text-primary)] border-[var(--border-card)]'}"
      >
        ⚡ Cram All ({allCards.length})
      </button>
    </div>
  </div>

  {#if !curWord}
    <div class="text-center py-9 px-4 space-y-2">
      <div class="text-base font-extrabold text-[var(--text-primary)]">
        {mode === 'review' ? '🎉 All scheduled listening reviews are complete!' : '🎉 You have completed the hearing cram session!'}
      </div>
      <div class="text-xs text-[var(--text-muted)]">
        {mode === 'review' ? `No audio cards are due today (${todayStr}).` : 'Click below to shuffle and start another cram session.'}
      </div>

      {#if mode === 'cram' && allCards.length > 0}
        <button
          onclick={startCram}
          class="mt-3 px-4 py-2 rounded-xl text-xs font-extrabold bg-[var(--interactive-accent,var(--text-primary))] text-[var(--bg-base)] cursor-pointer"
        >
          🔄 Restart Cram Mode
        </button>
      {/if}
    </div>
  {:else}
    <!-- Audio Trigger Arena -->
    <div class="relative flex flex-col items-center justify-center p-6 sm:p-7 rounded-xl bg-[var(--bg-base)] border border-[var(--border-card)] gap-3.5 text-center">
      <div class="flex items-center gap-2.5 flex-wrap justify-center">
        <button
          onclick={handlePlayAudio}
          class="px-5 py-2 rounded-xl text-xs font-extrabold text-white bg-gradient-to-r from-purple-500 to-blue-500 hover:opacity-95 active:scale-95 transition-transform cursor-pointer border-none shadow-xs"
        >
          🔊 Play Audio
        </button>

        {#if !isRevealed}
          <button
            onclick={() => (isRevealed = true)}
            class="px-5 py-2 rounded-xl text-xs font-extrabold bg-[var(--bg-surface)] text-[var(--text-primary)] border border-[var(--border-card)] hover:bg-[var(--bg-surface-active)] active:scale-95 transition-all cursor-pointer"
          >
            👁️ Reveal Word
          </button>
        {/if}
      </div>

      <div class="absolute bottom-2 right-2 flex items-center gap-1 px-1.5 py-0.5 rounded-lg bg-[var(--bg-surface)] border border-[var(--border-card)] opacity-85 text-[10px] font-mono font-bold text-[var(--text-muted)]">
        <span>⚡</span>
        <input
          type="number"
          min="0.4"
          max="1.5"
          step="0.05"
          bind:value={ttsRate}
          class="w-8 bg-transparent border-none outline-none text-center font-bold text-[var(--text-primary)]"
        />
      </div>
    </div>

    <!-- Revealed Details Box -->
    {#if isRevealed}
      <div class="flex flex-col gap-4 p-4 rounded-xl bg-[var(--bg-base)] border border-[var(--border-card)]">
        <!-- 1. Picture / MediaStage on top -->
        <div class="w-full max-w-[280px] mx-auto min-h-[140px] flex items-center justify-center">
          <MediaStage
            src={curWord.link || ''}
            alt="Word Illustration"
            fallbackChar={curWord.native}
          />
        </div>

        <!-- 2. Tone-Colored Native Script & Pronunciation below picture -->
        <div class="text-center space-y-1">
          <div class="text-3xl font-black tracking-wide font-serif">
            <ColoredText tokens={tokens.primaryTokens} fallbackClass="text-[var(--text-primary)]" />
          </div>
          {#if curWord.pronunciation}
            <div class="text-sm font-mono font-bold">
              <ColoredText tokens={tokens.secondaryTokens} fallbackClass="text-[var(--text-muted)]" />
            </div>
          {/if}
        </div>

        <!-- 3. Rating Action Row -->
        <div class="pt-3 border-t border-[var(--border-card)] flex gap-2 justify-center flex-wrap">
          {#if mode === 'review'}
            <button
              onclick={() => handleSM2Grade('again')}
              disabled={isSubmitting}
              class="px-3 py-1.5 rounded-lg text-xs font-extrabold bg-rose-500/15 text-rose-500 border border-rose-500/30 hover:bg-rose-500/25 active:scale-95 transition-all cursor-pointer disabled:opacity-50"
            >
              ❌ Again ({getIntervalPreview({ interval: curInt, ease: curEase, grade: 'again' })})
            </button>

            <button
              onclick={() => handleSM2Grade('hard')}
              disabled={isSubmitting}
              class="px-3 py-1.5 rounded-lg text-xs font-extrabold bg-amber-500/15 text-amber-500 border border-amber-500/30 hover:bg-amber-500/25 active:scale-95 transition-all cursor-pointer disabled:opacity-50"
            >
              ⚡ Hard ({getIntervalPreview({ interval: curInt, ease: curEase, grade: 'hard' })})
            </button>

            <button
              onclick={() => handleSM2Grade('good')}
              disabled={isSubmitting}
              class="px-3 py-1.5 rounded-lg text-xs font-extrabold bg-emerald-500/15 text-emerald-500 border border-emerald-500/30 hover:bg-emerald-500/25 active:scale-95 transition-all cursor-pointer disabled:opacity-50"
            >
              👍 Good ({getIntervalPreview({ interval: curInt, ease: curEase, grade: 'good' })})
            </button>

            <button
              onclick={() => handleSM2Grade('easy')}
              disabled={isSubmitting}
              class="px-3 py-1.5 rounded-lg text-xs font-extrabold bg-indigo-500/15 text-indigo-500 border border-indigo-500/30 hover:bg-indigo-500/25 active:scale-95 transition-all cursor-pointer disabled:opacity-50"
            >
              🌟 Easy ({getIntervalPreview({ interval: curInt, ease: curEase, grade: 'easy' })})
            </button>
          {:else}
            <button
              onclick={handleCramFail}
              class="px-4 py-2 rounded-lg text-xs font-extrabold bg-rose-500/15 text-rose-500 border border-rose-500/35 hover:bg-rose-500/25 active:scale-95 transition-all cursor-pointer"
            >
              ❌ Fail / Repeat
            </button>

            <button
              onclick={handleCramPass}
              class="px-4 py-2 rounded-lg text-xs font-extrabold bg-emerald-500/15 text-emerald-500 border border-emerald-500/35 hover:bg-emerald-500/25 active:scale-95 transition-all cursor-pointer"
            >
              ✅ Pass / Next
            </button>
          {/if}
        </div>

        <div class="text-[11px] font-mono text-[var(--text-muted)] opacity-60 text-center">
          Due: {curWord.due_date || 'Today'}
        </div>
      </div>
    {/if}
  {/if}
</div>