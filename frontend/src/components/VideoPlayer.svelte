<!-- frontend/src/components/VideoPlayer.svelte -->
<script>
  import { getMediaInfo } from '../lib/media.js';

  let { 
    src = '', 
    accentColor = '#6a1b9a',
    fallbackText = 'No video link provided.' 
  } = $props();

  let mediaInfo = $derived(getMediaInfo(src));
  let hasEmbedError = $state(false);
  
  // Controls click-to-load YouTube facade
  let isPlayerActivated = $state(false);

  $effect(() => {
    src;
    hasEmbedError = false;
    isPlayerActivated = false;
  });
</script>

<div class="relative w-full aspect-video rounded-xl overflow-hidden bg-[var(--bg-base)] border border-[var(--border-card)] flex items-center justify-center select-none group">
  {#if mediaInfo.type === 'empty'}
    <span class="text-xs text-[var(--text-muted)] italic px-4 text-center">
      {fallbackText}
    </span>

  {:else if hasEmbedError}
    <div class="flex flex-col items-center justify-center gap-2 p-4 text-center">
      <span class="text-xs text-[var(--text-muted)]">
        Video embed restricted by provider.
      </span>
      <a
        href={mediaInfo.url || src}
        target="_blank"
        rel="noopener noreferrer"
        class="flex items-center gap-1.5 px-3.5 py-1.5 rounded-xl text-xs font-bold border border-[var(--border-card)] bg-[var(--bg-surface)] hover:border-[var(--border-hover)] transition-transform active:scale-95 cursor-pointer"
        style="color: {accentColor};"
      >
        <span>↗️</span>
        <span>Open in YouTube</span>
      </a>
    </div>

  {:else if mediaInfo.type === 'youtube'}
    {#if !isPlayerActivated}
      <!-- Lazy Facade: Shows lightweight static thumbnail until tapped -->
      <button
        type="button"
        onclick={() => (isPlayerActivated = true)}
        class="relative w-full h-full p-0 border-none bg-black cursor-pointer overflow-hidden flex items-center justify-center group/btn"
        aria-label="Play video"
      >
        <!-- High-res lightweight YouTube cover thumbnail (~15kb) -->
        <img
          src="https://i.ytimg.com/vi/{mediaInfo.id}/hqdefault.jpg"
          alt="Video preview thumbnail"
          loading="lazy"
          class="w-full h-full object-cover opacity-85 group-hover/btn:opacity-100 group-hover/btn:scale-105 transition-all duration-300"
        />

        <!-- Centered Play Button Badge -->
        <div class="absolute inset-0 bg-black/20 flex items-center justify-center">
          <div
            class="w-12 h-12 rounded-full flex items-center justify-center text-white text-lg shadow-lg transform transition-transform group-hover/btn:scale-110 active:scale-95"
            style="background-color: {accentColor};"
          >
            ▶
          </div>
        </div>
      </button>
    {:else}
      <!-- Real iframe mounts only on user intention with autoplay enabled -->
      <iframe
        src="https://www.youtube.com/embed/{mediaInfo.id}?autoplay=1&rel=0"
        title="YouTube player"
        class="w-full h-full border-none"
        allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
        allowfullscreen
        loading="lazy"
        referrerpolicy="origin-when-cross-origin"
        onerror={() => (hasEmbedError = true)}
      ></iframe>
    {/if}

  {:else if mediaInfo.type === 'direct_video'}
    <!-- Pure lazy loading: no video bytes buffered until user presses play -->
    <video
      src={mediaInfo.url}
      controls
      preload="none"
      playsinline
      class="w-full h-full object-contain"
    >
      <track kind="captions" />
    </video>

  {:else if mediaInfo.type === 'image'}
    <img
      src={mediaInfo.url}
      alt="Immersion visual"
      loading="lazy"
      class="w-full h-full object-contain"
    />

  {:else}
    <a
      href={mediaInfo.url || src}
      target="_blank"
      rel="noopener noreferrer"
      class="flex items-center gap-1.5 px-4 py-2 rounded-xl text-xs font-bold border border-[var(--border-card)] bg-[var(--bg-surface)] hover:border-[var(--border-hover)] transition-transform active:scale-95 cursor-pointer"
      style="color: {accentColor};"
    >
      <span>↗️</span>
      <span>Open Link</span>
    </a>
  {/if}
</div>