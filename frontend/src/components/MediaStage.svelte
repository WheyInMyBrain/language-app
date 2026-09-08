<!-- frontend/src/components/MediaStage.svelte -->
<script module>
  let activeVideoCount = 0;
  const MAX_HARDWARE_DECODERS = 2; // Strict safety threshold for mobile GPUs
</script>

<script>
  import { onMount } from 'svelte';
  import { getMediaInfo } from '../lib/media.js';
  import { ensureImageDecoded, isImageDecoded } from '../lib/mediaCache.js';

  let { 
    src = '', 
    alt = 'Media', 
    fallbackChar = '字',
    observerRoot = null,
    class: extraClass = ''
  } = $props();

  let mediaInfo = $derived(getMediaInfo(src));
  let videoEl = $state(null);
  let containerEl = $state(null);

  let isVisible = $state(false);
  let isDecoded = $state(false);
  let canMountVideo = $state(false);

  // Reset decoded state whenever the URL changes so previous image never lingers
  $effect(() => {
    const currentUrl = mediaInfo.url;
    if (mediaInfo.type === 'image' && currentUrl) {
      if (isImageDecoded(currentUrl)) {
        isDecoded = true;
      } else {
        isDecoded = false; // Immediately show loading state
        ensureImageDecoded(currentUrl).then((ok) => {
          // Guard against race conditions if card switched again while loading
          if (mediaInfo.url === currentUrl && ok) {
            isDecoded = true;
          }
        });
      }
    } else {
      isDecoded = false;
    }
  });

  onMount(() => {
    if (!containerEl) return;

    const observer = new IntersectionObserver(
      (entries) => {
        const entry = entries[0];
        isVisible = entry.isIntersecting;

        if (mediaInfo.type === 'direct_video') {
          if (isVisible && activeVideoCount < MAX_HARDWARE_DECODERS) {
            canMountVideo = true;
            activeVideoCount++;
          } else if (!isVisible && canMountVideo) {
            canMountVideo = false;
            activeVideoCount = Math.max(0, activeVideoCount - 1);
          }
        }
      },
      {
        root: observerRoot,
        rootMargin: '100px',
        threshold: 0.15
      }
    );

    observer.observe(containerEl);

    return () => {
      observer.disconnect();
      if (canMountVideo) {
        activeVideoCount = Math.max(0, activeVideoCount - 1);
      }
    };
  });

  $effect(() => {
    if (videoEl) {
      videoEl.muted = true;
      videoEl.defaultMuted = true;
      videoEl.volume = 0;
      if (isVisible) {
        videoEl.play().catch(() => {});
      } else {
        videoEl.pause();
      }
    }
  });
</script>

<div 
  bind:this={containerEl}
  class="relative w-full aspect-square rounded-xl border border-[var(--border-card)] bg-[var(--bg-base)] overflow-hidden flex items-center justify-center select-none [contain:strict] [transform:translateZ(0)] {extraClass}"
>
  {#if mediaInfo.type === 'empty'}
    <span class="text-3xl font-black text-[var(--text-primary)] opacity-15">
      {fallbackChar ? fallbackChar.charAt(0) : '字'}
    </span>

  {:else if mediaInfo.type === 'direct_video'}
    {#if canMountVideo}
      <video
        bind:this={videoEl}
        src={mediaInfo.url}
        loop
        muted
        playsinline
        preload="none"
        class="w-full h-full max-w-full max-h-full object-contain pointer-events-none"
      ></video>
    {:else}
      <div class="flex flex-col items-center justify-center opacity-30 gap-1">
        <span class="text-lg">▶</span>
        <span class="text-[9px] font-mono uppercase tracking-widest text-[var(--text-muted)]">Video</span>
      </div>
    {/if}

  {:else}
    <!-- Image rendered with cross-fade once decoded -->
    {#key mediaInfo.url}
      <img
        src={mediaInfo.url}
        {alt}
        loading="eager"
        decoding="async"
        class="w-full h-full max-w-full max-h-full object-contain transition-opacity duration-200 {isDecoded ? 'opacity-100' : 'opacity-0'}"
      />
    {/key}

    <!-- Clean, centered loader shown while fetching/decoding -->
    {#if !isDecoded}
      <div class="absolute inset-0 flex flex-col items-center justify-center gap-2 bg-[var(--bg-surface)] pointer-events-none">
        <div class="w-6 h-6 rounded-full border-2 border-[var(--border-card)] border-t-[var(--interactive-accent,var(--text-primary))] animate-spin"></div>
        <span class="text-[10px] font-mono font-bold text-[var(--text-muted)] tracking-wider uppercase opacity-70">
          Loading
        </span>
      </div>
    {/if}
  {/if}
</div>