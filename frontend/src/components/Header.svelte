<!-- frontend/src/components/Header.svelte -->
<script>
  import { onMount } from 'svelte';
  import { metadataStore } from '../lib/stores/metadata.svelte.js';
  import { activeLanguage } from '../lib/stores/activeLanguage.svelte.js';
  import { srsStore } from '../lib/stores/srs.svelte.js';
  import { uploadProgressStore } from '../lib/stores/uploadProgress.svelte.js';
  import { refreshPendingAudioCount, syncPendingAudios } from '../lib/audioSync.js';

  import Mascot from './Mascot.svelte';

  import { 
    ArrowLeft, 
    Flame, 
    CloudUpload,
    RotateCw
  } from '@lucide/svelte';

  let { handleBack, activeRoute = 'dashboard' } = $props();

  let status = $derived(metadataStore.connectionStatus);
  let activeLangCode = $derived(metadataStore.activeLanguage);
  let activeLangConfig = $derived(activeLanguage.current);
  let themeColor = $derived(activeLanguage.themeColor || '#a855f7');

  let totalDue = $derived.by(() => {
    if (!srsStore.getDueCounts) return 0;
    const counts = srsStore.getDueCounts();
    return (counts.audio || 0) + (counts.visual || 0);
  });

  let streak = $derived(activeLangConfig?.current_streak || 0);

  let pendingAudios = $derived(uploadProgressStore.pendingCount);
  let isUploading = $derived(uploadProgressStore.isUploading);
  let uploadProgress = $derived(uploadProgressStore.progress);

  onMount(() => {
    refreshPendingAudioCount();
  });
</script>

<header 
  class="safe-top w-full sticky top-0 z-50 px-3 sm:px-6 py-2.5 border-b border-[var(--border-subtle)] transition-colors duration-500 backdrop-blur-2xl"
  style="
    background-color: color-mix(in srgb, var(--bg-base) 80%, transparent);
    background-image: 
      radial-gradient(circle 500px at 10% -20%, {themeColor}22, transparent 100%),
      radial-gradient(circle 350px at 90% -20%, {themeColor}15, transparent 100%);
  "
>
  <div class="max-w-[1720px] mx-auto flex items-center justify-between gap-3 relative z-10">
    
    <!-- LEFT: Back Button + Clean Kaomoji Mascot -->
    <div class="flex items-center gap-2.5 sm:gap-4">
      {#if activeRoute !== 'dashboard' && activeRoute !== 'select-language'}
        <button
          type="button"
          onclick={handleBack}
          aria-label="Go Back"
          class="flex items-center justify-center w-8 h-8 rounded-xl bg-[var(--bg-surface)] border border-[var(--border-card)] hover:border-[var(--border-hover)] hover:bg-[var(--bg-surface-elevated)] text-[var(--text-secondary)] hover:text-[var(--text-primary)] transition-all duration-150 active:scale-90 cursor-pointer shadow-xs shrink-0"
        >
          <ArrowLeft size={14} strokeWidth={2.5} />
        </button>
      {/if}

      <!-- Clean Dynamic Mascot Component -->
      <Mascot {activeRoute} />
    </div>

    <!-- RIGHT: Audio Queue, Streak, SRS Due, and Yjs Telemetry -->
    <div class="flex items-center gap-2 sm:gap-2.5">

      <!-- Audio Outbox Sync Capsule -->
      {#if pendingAudios > 0 || isUploading}
        <button
          type="button"
          onclick={() => syncPendingAudios()}
          title="{pendingAudios} recording(s) pending. Click to force sync."
          class="relative flex flex-col justify-center px-2.5 sm:px-3 py-1.5 rounded-xl bg-rose-500/10 hover:bg-rose-500/15 border border-rose-500/30 text-rose-400 font-mono transition-all active:scale-95 shadow-xs overflow-hidden cursor-pointer"
        >
          <div class="flex items-center gap-1.5 z-10 text-[11px] font-bold leading-none">
            {#if isUploading}
              <RotateCw size={12} class="animate-spin text-rose-400 shrink-0" />
              <span>{uploadProgress}%</span>
              {#if pendingAudios > 0}
                <span class="text-[9px] font-normal opacity-70">({pendingAudios})</span>
              {/if}
            {:else}
              <CloudUpload size={12} class="text-rose-400 shrink-0" />
              <span>{pendingAudios}</span>
              <span class="hidden sm:inline text-[9px] uppercase font-bold tracking-wider opacity-80">Queued</span>
            {/if}
          </div>

          {#if isUploading && uploadProgress > 0}
            <div class="absolute bottom-0 left-0 right-0 h-[2.5px] bg-rose-500/20">
              <div 
                class="h-full bg-rose-400 shadow-[0_0_6px_#fb7185] transition-all duration-150 rounded-r-full"
                style="width: {uploadProgress}%;"
              ></div>
            </div>
          {/if}
        </button>
      {/if}

      <!-- Streak Badge -->
      {#if activeLangCode}
        <div 
          title="{streak} Day Streak"
          class="flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-[var(--bg-surface)]/90 border border-[var(--border-card)] shadow-xs transition-transform hover:scale-105"
          style="box-shadow: {streak >= 3 ? '0 0 12px rgba(245,158,11,0.2)' : '0 0 4px rgba(0,0,0,0.05)'};"
        >
          <Flame size={13} class={streak >= 3 ? 'text-amber-500 fill-amber-500/20 animate-pulse' : 'text-neutral-400'} />
          <span class="text-xs font-mono font-black {streak >= 3 ? 'text-amber-500' : 'text-neutral-500'}">
            {streak}<span class="text-[10px] font-bold text-[var(--text-muted)] ml-0.5">d</span>
          </span>
        </div>
      {/if}

      <!-- Due Cards Pulse Indicator -->
      {#if totalDue > 0}
        <div 
          title="{totalDue} flashcards awaiting review"
          class="flex items-center gap-2 px-3 py-1.5 rounded-xl bg-rose-500/10 border border-rose-500/30 shadow-xs transition-transform hover:scale-105"
          style="box-shadow: 0 0 14px rgba(244,63,94,0.2);"
        >
          <span class="relative flex h-2 w-2">
            <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-rose-400 opacity-75"></span>
            <span class="relative inline-flex rounded-full h-2 w-2 bg-rose-500 shadow-[0_0_6px_#f43f5e]"></span>
          </span>
          <span class="text-xs font-mono font-black text-rose-500">
            {totalDue}
          </span>
          <span class="hidden md:inline text-[10px] font-bold uppercase tracking-wider text-rose-400">
            Due
          </span>
        </div>
      {/if}

      <!-- Yjs Synchronizer Telemetry Capsule -->
      <div 
        title="Sync Pipeline: {status}"
        class="flex items-center gap-2 px-3 py-1.5 rounded-xl bg-[var(--bg-surface)]/90 border border-[var(--border-card)] shadow-xs"
      >
        <div class="relative flex items-center justify-center">
          {#if status === 'connected'}
            <span class="w-2 h-2 rounded-full bg-emerald-400 shadow-[0_0_8px_rgba(52,211,153,0.9)]"></span>
          {:else if status === 'connecting'}
            <span class="w-2 h-2 rounded-full bg-amber-400 animate-pulse"></span>
          {:else}
            <span class="w-2 h-2 rounded-full bg-rose-500 shadow-[0_0_8px_rgba(244,63,94,0.9)]"></span>
          {/if}
        </div>
        
        <span class="hidden lg:inline text-[10px] font-mono font-bold uppercase tracking-wider text-[var(--text-muted)]">
          {status}
        </span>
      </div>

    </div>

  </div>
</header>