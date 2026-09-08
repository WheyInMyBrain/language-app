<!-- frontend/src/components/ListeningCard.svelte -->
<script>
  import { activeLanguage } from '../lib/stores/activeLanguage.svelte.js';
  import { formatSecondsToTimer } from '../lib/mediaResolver.js';
  import VideoPlayer from './VideoPlayer.svelte';
  import AudioBar from './AudioBar.svelte';

  let {
    lang = 'zh-CN',
    date = '',
    activity = {},
    index = 1,
    isOpen = true
  } = $props();

  let colors = $derived(activeLanguage.colors);
  let accentColor = $derived(colors.listening?.dark_primary || '#bf360c');

  let duration = $derived(activity.link_duration || 0);
  let displayTimer = $derived(
    duration > 0 ? formatSecondsToTimer(duration) : 'Untimed'
  );

  let isCopied = $state(false);

  async function handleCopyLink(e) {
    e.preventDefault();
    e.stopPropagation();

    if (!activity.link) return;

    try {
      await navigator.clipboard.writeText(activity.link);
      isCopied = true;
      setTimeout(() => (isCopied = false), 1800);
    } catch {
      const el = document.createElement('textarea');
      el.value = activity.link;
      document.body.appendChild(el);
      el.select();
      document.execCommand('copy');
      document.body.removeChild(el);
      isCopied = true;
      setTimeout(() => (isCopied = false), 1800);
    }
  }
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

      <span class="text-sm font-bold text-[var(--text-primary)] truncate">
        Listening Practice Session
      </span>
    </div>

    <!-- Header Actions (Timer Badge + Copy Link Button) -->
    <div class="flex items-center gap-2 shrink-0 ml-2">
      {#if activity.link}
        <button
          onclick={handleCopyLink}
          title="Copy Audio/Video Link"
          class="flex items-center gap-1 px-2.5 py-1 rounded-lg border border-[var(--border-card)] bg-[var(--bg-base)] hover:border-[var(--border-hover)] text-[10px] font-bold transition-all active:scale-90 cursor-pointer"
          style={isCopied ? `color: ${accentColor}; border-color: ${accentColor};` : ''}
        >
          <span>{isCopied ? '✓' : '📋'}</span>
          <span>{isCopied ? 'Copied' : 'Copy'}</span>
        </button>
      {/if}

      <span
        class="text-[11px] font-mono font-bold px-2 py-0.5 rounded-md border"
        style="color: {accentColor}; background-color: {accentColor}18; border-color: {accentColor}35;"
      >
        ⏱️ {displayTimer}
      </span>
    </div>
  </summary>

  <!-- Expanded Body -->
  <div class="flex flex-col gap-4 p-4 bg-[var(--bg-base)]">
    <!-- 16:9 Video/Audio Player -->
    <div class="w-full max-w-[540px] mx-auto">
      <VideoPlayer 
        src={activity.link || ''} 
        {accentColor} 
        fallbackText="No audio/video link provided for this session."
      />
    </div>

    <!-- Voice Note Recording Bar -->
    <AudioBar
      {lang}
      {date}
      category="listening"
      index={activity.item_index ?? index}
      audioDuration={activity.audio_duration || 0}
      {accentColor}
      buttonLabel="My Voice Note"
    />
  </div>
</details>