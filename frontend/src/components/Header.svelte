<!-- frontend/src/components/Header.svelte -->
<script>
  import { metadataStore } from '../lib/stores/metadata.svelte.js';
  import { activeLanguage } from '../lib/stores/activeLanguage.svelte.js';
  import { srsStore } from '../lib/stores/srs.svelte.js';

  // Razor-sharp vector icons
  import { 
    ChevronDown, 
    ArrowLeft, 
    Flame, 
    Check, 
    Sparkles, 
    Globe,
    Layers
  } from '@lucide/svelte';

  let { handleBack, activeRoute = 'dashboard' } = $props();

  // Telemetry & active states
  let status = $derived(metadataStore.connectionStatus);
  let activeLangCode = $derived(metadataStore.activeLanguage);
  let activeLangConfig = $derived(activeLanguage.current);
  let langList = $derived(Object.values(metadataStore.languages || {}));

  // Clean Theme Accent Color: Reads from activeLanguage.themeColor, falls back to vibrant purple
  let themeColor = $derived(activeLanguage.themeColor || '#a855f7');

  // SRS Due counter
  let totalDue = $derived.by(() => {
    if (!srsStore.getDueCounts) return 0;
    const counts = srsStore.getDueCounts();
    return (counts.audio || 0) + (counts.visual || 0);
  });

  // Streak
  let streak = $derived(activeLangConfig?.current_streak || 0);

  // Instant Native Popover State (Zero lag, zero portals)
  let isLangMenuOpen = $state(false);

  function toggleMenu(e) {
    e.stopPropagation();
    isLangMenuOpen = !isLangMenuOpen;
  }

  function selectLanguage(code) {
    metadataStore.activeLanguage = code;
    isLangMenuOpen = false;
  }

  function handleWindowClick(e) {
    if (!e.target.closest('#lang-dropdown-wrapper')) {
      isLangMenuOpen = false;
    }
  }

  function handleWindowKeydown(e) {
    if (e.key === 'Escape') {
      isLangMenuOpen = false;
    }
  }
</script>

<svelte:window onclick={handleWindowClick} onkeydown={handleWindowKeydown} />

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
    
    <!-- LEFT: Identity, Navigation & Instant Language Switcher -->
    <div class="flex items-center gap-2.5 sm:gap-4">
      
      <!-- Smart Back Button: Only illuminates when drilled into sub-views -->
      {#if activeRoute !== 'dashboard' && activeRoute !== 'select-language'}
        <button
          type="button"
          onclick={handleBack}
          aria-label="Go Back"
          class="flex items-center justify-center w-8 h-8 rounded-xl bg-[var(--bg-surface)] border border-[var(--border-card)] hover:border-[var(--border-hover)] hover:bg-[var(--bg-surface-elevated)] text-[var(--text-secondary)] hover:text-[var(--text-primary)] transition-all duration-150 active:scale-90 cursor-pointer shadow-xs"
        >
          <ArrowLeft size={14} strokeWidth={2.5} />
        </button>
      {/if}

      <!-- Brand Mark: LOGLANG with Soft Backlit Glow -->
      <div class="flex items-center gap-2.5 group cursor-default">
        <div 
          class="relative flex items-center justify-center w-8 h-8 rounded-xl border shadow-xs transition-all duration-300 group-hover:scale-105"
          style="
            background: radial-gradient(circle at 35% 35%, {themeColor}30, transparent 100%), var(--bg-surface);
            border-color: {themeColor}50;
            box-shadow: 0 0 16px {themeColor}25;
          "
        >
          <Sparkles size={15} style="color: {themeColor};" class="transition-transform group-hover:rotate-12 duration-300" />
        </div>

        <div class="hidden sm:flex flex-col leading-none">
          <div class="flex items-center gap-1.5">
            <span class="text-sm font-black tracking-tight text-[var(--text-primary)]">
              LOG<span style="color: {themeColor};" class="font-mono font-bold transition-colors duration-500">LANG</span>
            </span>
            <span 
              class="text-[8px] font-mono font-bold uppercase tracking-wider px-1.5 py-0.5 rounded border"
              style="background-color: {themeColor}12; color: {themeColor}; border-color: {themeColor}30;"
            >
              STUDIO
            </span>
          </div>
          <span class="text-[9px] font-mono tracking-widest text-[var(--text-muted)] uppercase mt-0.5">
            Language Cockpit
          </span>
        </div>
      </div>

      <!-- Divider -->
      <div class="hidden sm:block w-px h-5 bg-[var(--border-subtle)]"></div>

      <!-- Instant Native Language Selector (100% Reliable, 0ms latency) -->
      {#if activeLangCode}
        <div id="lang-dropdown-wrapper" class="relative">
          <button
            type="button"
            onclick={toggleMenu}
            class="flex items-center gap-2 px-3 py-1.5 rounded-xl bg-[var(--bg-surface)]/90 hover:bg-[var(--bg-surface-elevated)] border transition-all duration-150 cursor-pointer shadow-xs active:scale-[0.98] outline-none"
            style="border-color: {isLangMenuOpen ? themeColor : 'var(--border-card)'}; box-shadow: {isLangMenuOpen ? `0 0 14px ${themeColor}30` : `0 0 8px ${themeColor}10`};"
          >
            <!-- Breathing Theme Dot -->
            <span 
              class="w-2 h-2 rounded-full transition-colors duration-500 shrink-0"
              style="background-color: {themeColor}; box-shadow: 0 0 8px {themeColor};"
            ></span>

            <span class="text-xs font-bold text-[var(--text-primary)] tracking-tight">
              {activeLangConfig?.name || activeLangCode}
            </span>

            <span class="text-[9px] font-mono font-bold uppercase px-1.5 py-0.5 rounded bg-[var(--badge-bg)] text-[var(--text-muted)] border border-[var(--border-subtle)]">
              {activeLangCode}
            </span>

            <ChevronDown 
              size={12} 
              class="text-[var(--text-muted)] transition-transform duration-200 {isLangMenuOpen ? 'rotate-180' : ''}" 
            />
          </button>

          <!-- Native Floating Popover Menu -->
          {#if isLangMenuOpen}
            <div 
              class="absolute left-0 mt-2 w-60 rounded-2xl border shadow-2xl p-1.5 z-50 backdrop-blur-2xl animate-in fade-in zoom-in-95 duration-100"
              style="
                background-color: color-mix(in srgb, var(--bg-surface) 92%, {themeColor} 8%);
                border-color: color-mix(in srgb, {themeColor} 40%, var(--border-card));
                box-shadow: 0 16px 36px -8px rgba(0,0,0,0.5), 0 0 24px {themeColor}20;
              "
            >
              <div class="px-2.5 py-1.5 text-[10px] font-bold font-mono uppercase tracking-wider text-[var(--text-muted)] border-b border-[var(--border-subtle)] mb-1 flex items-center justify-between">
                <span>Active Targets</span>
                <span class="text-[9px] font-normal" style="color: {themeColor};">{langList.length} languages</span>
              </div>
              
              <div class="space-y-0.5 max-h-64 overflow-y-auto">
                {#each langList as lang (lang.code)}
                  {@const isSelected = lang.code === activeLangCode}
                  <button
                    type="button"
                    onclick={() => selectLanguage(lang.code)}
                    class="w-full flex items-center justify-between px-2.5 py-2 rounded-xl text-xs font-semibold transition-all cursor-pointer outline-none {isSelected 
                      ? 'text-[var(--text-primary)] font-bold' 
                      : 'text-[var(--text-secondary)] hover:text-[var(--text-primary)] hover:bg-[var(--bg-surface-elevated)]'}"
                    style={isSelected ? `background-color: ${themeColor}20; border: 1px solid ${themeColor}40;` : ''}
                  >
                    <div class="flex items-center gap-2">
                      {#if isSelected}
                        <Check size={13} style="color: {themeColor};" strokeWidth={3} />
                      {:else}
                        <span class="w-3.5"></span>
                      {/if}
                      <span>{lang.name}</span>
                    </div>

                    <span class="font-mono text-[10px] uppercase text-[var(--text-muted)]">
                      {lang.code}
                    </span>
                  </button>
                {/each}
              </div>
            </div>
          {/if}
        </div>
      {/if}

    </div>

    <!-- RIGHT: Telemetry Indicators, Pulse Streaks & Sync Status -->
    <div class="flex items-center gap-2 sm:gap-2.5">

      <!-- Streak Metric Badge -->
      {#if activeLangCode}
        <div 
          title="{streak} Day Streak"
          class="flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-[var(--bg-surface)]/90 border border-[var(--border-card)] shadow-xs transition-transform hover:scale-105"
          style="box-shadow: 0 0 10px rgba(245,158,11,0.12);"
        >
          <Flame size={13} class="text-amber-500 fill-amber-500/20" />
          <span class="text-xs font-mono font-black text-amber-500">
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