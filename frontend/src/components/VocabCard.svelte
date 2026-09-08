<script>
  import { activeLanguage } from '../lib/stores/activeLanguage.svelte.js';
  import { tokenizePhonetics } from '../lib/formatters/phonetics.js';
  import { playTTS } from '../lib/tts.js';
  import ColoredText from './ColoredText.svelte';
  import MediaStage from './MediaStage.svelte';
  import AudioBar from './AudioBar.svelte';

  let {
    lang = 'zh-CN',
    date = '',
    word = {},
    index = 1,
    isOpen = true
  } = $props();

  let langConfig = $derived(activeLanguage.current);
  let colors = $derived(activeLanguage.colors);
  let accentColor = $derived(colors.vocab?.dark_primary || '#2e7d32');

  // Reactively compute tone-colored tokens for native script and pronunciation
  let tokens = $derived(
    tokenizePhonetics(word.native_script, word.pronunciation, langConfig)
  );

  function handlePronounce(e) {
    e.preventDefault();
    e.stopPropagation();
    playTTS(word.native_script, langConfig?.code || 'zh-CN');
  }
</script>

<details
  open={isOpen}
  class="group flex flex-col rounded-2xl bg-[var(--bg-surface)] border border-[var(--border-card)] shadow-xs overflow-hidden transition-colors duration-200 select-none"
>
  <summary class="flex items-center justify-between px-4 py-3.5 bg-[var(--bg-surface)] hover:bg-[var(--bg-surface-active)] border-b border-[var(--border-card)] cursor-pointer list-none transition-colors">
    <div class="flex items-center gap-2.5 min-w-0">
      <span
        class="text-[11px] font-mono font-black px-2 py-0.5 rounded-lg border border-[var(--border-card)] bg-[var(--bg-base)]"
        style="color: {accentColor};"
      >
        #{index}
      </span>

      <div class="flex items-baseline gap-2 truncate">
        <span class="text-sm font-black truncate">
          <ColoredText tokens={tokens.primaryTokens} fallbackClass="text-[var(--text-primary)]" />
        </span>
        {#if word.pronunciation}
          <span class="text-xs font-semibold text-[var(--text-muted)] truncate">
            (<ColoredText tokens={tokens.secondaryTokens} fallbackClass="text-[var(--text-muted)]" />)
          </span>
        {/if}
      </div>
    </div>

    <button
      onclick={handlePronounce}
      title="Play Pronunciation"
      class="p-1.5 rounded-xl border border-[var(--border-card)] bg-[var(--bg-base)] hover:border-[var(--border-hover)] text-xs transition-transform active:scale-90 cursor-pointer"
    >
      🔊
    </button>
  </summary>

  <div class="flex flex-col gap-4 p-4 bg-[var(--bg-base)]">
    {#if word.link}
      <div class="w-full max-w-[280px] mx-auto">
        <MediaStage
          src={word.link}
          alt={word.native_script}
          fallbackChar={word.native_script}
        />
      </div>
    {/if}

    <div class="flex items-center justify-between gap-4 p-2 bg-[var(--bg-surface)] rounded-2xl border border-[var(--border-card)]">
      <div class="flex flex-col gap-1 min-w-0">
        <div class="text-3xl sm:text-4xl font-black tracking-tight leading-none">
          <ColoredText tokens={tokens.primaryTokens} fallbackClass="text-[var(--text-primary)]" />
        </div>

        {#if word.pronunciation}
          <div class="text-sm sm:text-base font-bold tracking-tight mt-1">
            <ColoredText tokens={tokens.secondaryTokens} fallbackClass="text-[var(--text-muted)]" />
          </div>
        {/if}
      </div>

      <button
        onclick={handlePronounce}
        class="flex items-center gap-1.5 px-3.5 py-2 rounded-xl text-xs font-bold border transition-all active:scale-95 cursor-pointer shrink-0"
        style="background: {accentColor}18; color: {accentColor}; border-color: {accentColor}35;"
      >
        <span>🔊</span>
        <span>Listen</span>
      </button>
    </div>

    <AudioBar
      {lang}
      {date}
      category="vocab"
      index={word.word_index ?? word.id ?? index}
      audioDuration={word.audio_duration || 0}
      {accentColor}
      buttonLabel="Record Reading"
    />
  </div>
</details>