<!-- frontend/src/components/GrammarCard.svelte -->
<script>
  import { activeLanguage } from '../lib/stores/activeLanguage.svelte.js';
  import { tokenizePhonetics } from '../lib/formatters/phonetics.js';
  import ColoredText from './ColoredText.svelte';
  import MediaStage from './MediaStage.svelte';
  import AudioBar from './AudioBar.svelte';

  let {
    lang = 'zh-CN',
    date = '',
    activity = {},
    index = 1,
    isOpen = true
  } = $props();

  let langConfig = $derived(activeLanguage.current);
  let colors = $derived(activeLanguage.colors);
  let accentColor = $derived(colors.grammar?.dark_primary || '#01579b');

  // Metadata extracted from daily activities blob
  let meta = $derived(activity.metadata || {});
  let title = $derived(meta.title || `Grammar Point #${index}`);
  let pronunciation = $derived(meta.pronunciation || '');
  let structure = $derived(meta.structure || '');
  let meaning = $derived(meta.meaning || '');
  let mediaLink = $derived(activity.link || '');

  // Tone-colored tokens for the pronunciation reading
  let tokens = $derived(
    tokenizePhonetics('', pronunciation, langConfig)
  );
</script>

<details
  open={isOpen}
  class="group flex flex-col rounded-2xl bg-[var(--bg-surface)] border border-[var(--border-card)] shadow-xs overflow-hidden transition-colors duration-200 select-none"
>
  <!-- Summary Header -->
  <summary class="flex items-center justify-between px-4 py-3.5 bg-[var(--bg-surface)] hover:bg-[var(--bg-surface-active)] border-b border-[var(--border-card)] cursor-pointer list-none transition-colors">
    <div class="flex items-center gap-2.5 min-w-0">
      <!-- Index Badge -->
      <span
        class="text-[11px] font-mono font-black px-2 py-0.5 rounded-lg border border-[var(--border-card)] bg-[var(--bg-base)] shrink-0"
        style="color: {accentColor};"
      >
        #{index}
      </span>

      <!-- Title & Reading -->
      <div class="flex items-baseline gap-2 truncate">
        <span class="text-sm font-bold text-[var(--text-primary)] truncate">
          {title}
        </span>
        {#if pronunciation}
          <span class="text-xs font-semibold text-[var(--text-muted)] truncate">
            (<ColoredText tokens={tokens.secondaryTokens} fallbackClass="text-[var(--text-muted)]" />)
          </span>
        {/if}
      </div>
    </div>

    <!-- Header Right Tag -->
    <span
      class="text-[11px] font-mono font-bold px-2 py-0.5 rounded-md border shrink-0 ml-2"
      style="color: {accentColor}; background-color: {accentColor}18; border-color: {accentColor}35;"
    >
      📚 Grammar
    </span>
  </summary>

  <!-- Expanded Body -->
  <div class="flex flex-col gap-3.5 p-4 bg-[var(--bg-base)]">
    <!-- Optional Diagram, Infographic, or Media -->
    {#if mediaLink}
      <div class="w-full max-w-[320px] mx-auto">
        <MediaStage
          src={mediaLink}
          alt={title}
          fallbackChar="📚"
        />
      </div>
    {/if}

    <!-- Structure Formula & Usage Explanations -->
    {#if structure || meaning}
      <div class="flex flex-col gap-2.5 p-3 rounded-xl bg-[var(--bg-surface)] border border-[var(--border-card)]">
        {#if structure}
          <div class="flex items-baseline gap-2 flex-wrap">
            <span
              class="text-[10px] font-extrabold uppercase tracking-wider"
              style="color: {accentColor};"
            >
              Structure:
            </span>
            <span class="text-xs font-mono font-bold text-[var(--text-primary)] tracking-tight">
              {structure}
            </span>
          </div>
        {/if}

        {#if meaning}
          <div class="flex items-baseline gap-2 flex-wrap">
            <span class="text-[10px] font-extrabold uppercase tracking-wider text-[var(--text-muted)]">
              Usage:
            </span>
            <span class="text-xs font-medium text-[var(--text-primary)] leading-relaxed">
              {meaning}
            </span>
          </div>
        {/if}
      </div>
    {/if}

    <!-- Grammar Voice Practice Recorder -->
    <AudioBar
      {lang}
      {date}
      category="grammar"
      index={activity.item_index ?? index}
      audioDuration={activity.audio_duration || 0}
      {accentColor}
      buttonLabel="Voice Practice"
    />
  </div>
</details>