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
  let isRevealed = $state(false);
  let isSubmitting = $state(false);

  let cramQueue = $state([]);
  let cramIndex = $state(0);

  let langConfig = $derived(activeLanguage.current);
  let colors = $derived(activeLanguage.colors);
  let accentColor = $derived(colors?.vocab?.dark_primary || '#2e7d32');

  // Read all visual cards from srsStore.cards
  let allCards = $derived.by(() => {
    const raw = srsStore.cards || {};
    const cards = [];

    for (const [key, item] of Object.entries(raw)) {
      if (item && item.card_type === 'visual') {
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

  // Compute tone color tokens for the revealed answer
  let tokens = $derived(
    currCard
      ? tokenizePhonetics(currCard.native, currCard.pronunciation, langConfig)
      : { primaryTokens: [], secondaryTokens: [] }
  );

  function startCram() {
    mode = 'cram';
    cramQueue = [...allCards].sort(() => Math.random() - 0.5);
    cramIndex = 0;
    isRevealed = false;
  }

  function startReview() {
    mode = 'review';
    isRevealed = false;
  }

  function handleReveal() {
    isRevealed = true;
    if (currCard) {
      playTTS(currCard.native, langCode || langConfig?.code || 'zh-CN');
    }
  }

  function handlePronounce() {
    if (!currCard) return;
    playTTS(currCard.native, langCode || langConfig?.code || 'zh-CN');
  }

  async function handleSM2Grade(grade) {
    if (!currCard?.key || isSubmitting) return;
    isSubmitting = true;

    try {
      await srsStore.rateCard(langCode, currCard.key, grade);
      isRevealed = false;
    } catch (err) {
      console.error(`[SRS] Failed to grade card "${currCard.key}":`, err);
    } finally {
      isSubmitting = false;
    }
  }

  function handleCramFail() {
    if (!currCard) return;
    cramQueue.push(currCard);
    cramIndex++;
    isRevealed = false;
  }

  function handleCramPass() {
    cramIndex++;
    isRevealed = false;
  }
</script>

<div class="word-srs-main-studio relative flex flex-col gap-3.5 p-4 sm:p-5 rounded-2xl bg-[var(--bg-surface)] border border-[var(--border-card)] shadow-xs select-none overflow-hidden">
  <div class="absolute top-0 left-0 right-0 h-[3px] bg-gradient-to-r from-emerald-500 to-blue-500 opacity-90"></div>

  <div class="flex items-center justify-between flex-wrap gap-2 pt-0.5">
    <div class="flex items-center gap-2">
      <span class="text-base">🀄</span>
      <span class="text-xs font-extrabold tracking-wide text-[var(--text-primary)]">
        Vocabulary Studio
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

  {#if !currCard}
    <div class="text-center py-9 px-4 space-y-2">
      <div class="text-base font-extrabold text-[var(--text-primary)]">
        {mode === 'review' ? '🎉 All scheduled vocabulary reviews are complete!' : '🎉 You have completed the cram session!'}
      </div>
      <div class="text-xs text-[var(--text-muted)]">
        {mode === 'review' ? `No cards are due today (${todayStr}).` : 'Click below to shuffle and start another cram session.'}
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
    <div class="flex flex-col items-center gap-4 p-4 rounded-xl bg-[var(--bg-base)] border border-[var(--border-card)] text-center">
      <div class="w-full max-w-[280px] mx-auto min-h-[160px] flex items-center justify-center">
        <MediaStage
          src={currCard.link || ''}
          alt="Visual Recall Prompt"
          fallbackChar={isRevealed ? currCard.native : '❓'}
        />
      </div>

      {#if !isRevealed}
        <button
          onclick={handleReveal}
          class="px-8 py-2 rounded-xl font-extrabold text-xs bg-[var(--interactive-accent,var(--text-primary))] text-[var(--bg-base)] hover:opacity-90 active:scale-95 transition-transform cursor-pointer"
        >
          👁️ Reveal Answer
        </button>
      {/if}

      {#if isRevealed}
        <div class="flex flex-col items-center gap-3.5 w-full border-t border-[var(--border-card)] pt-4">
          <div class="flex items-center justify-between gap-4 p-3 bg-[var(--bg-surface)] rounded-2xl border border-[var(--border-card)] w-full max-w-sm">
            <div class="flex flex-col items-start gap-1 text-left min-w-0">
              <div class="text-3xl sm:text-4xl font-black tracking-tight leading-none font-serif">
                <ColoredText tokens={tokens.primaryTokens} fallbackClass="text-[var(--text-primary)]" />
              </div>

              {#if currCard.pronunciation}
                <div class="text-sm sm:text-base font-bold tracking-tight mt-1">
                  <ColoredText tokens={tokens.secondaryTokens} fallbackClass="text-[var(--text-muted)]" />
                </div>
              {/if}
            </div>

            <button
              onclick={handlePronounce}
              class="flex items-center gap-1.5 px-3 py-2 rounded-xl text-xs font-bold border transition-all active:scale-95 cursor-pointer shrink-0"
              style="background: {accentColor}18; color: {accentColor}; border-color: {accentColor}35;"
              title="Play Pronunciation"
            >
              <span>🔊</span>
              <span>Listen</span>
            </button>
          </div>

          <div class="flex gap-2 justify-center flex-wrap pt-1">
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

          <div class="text-[11px] font-mono text-[var(--text-muted)] opacity-60">
            Due: {currCard.due_date || 'Today'} • Date: {currCard.source_date || '—'}
          </div>
        </div>
      {/if}
    </div>
  {/if}
</div>