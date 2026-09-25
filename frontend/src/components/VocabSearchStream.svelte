<!-- frontend/src/components/VocabSearchStream.svelte -->
<script>
  import { onMount } from 'svelte';
  import { vocabIndexStore } from '../lib/stores/vocabIndex.svelte.js';
  import { activeLanguage } from '../lib/stores/activeLanguage.svelte.js';
  import { tokenizePhonetics } from '../lib/formatters/phonetics.js';
  import ColoredText from './ColoredText.svelte';
  import MediaStage from './MediaStage.svelte';

  import { 
    Search, 
    X, 
    ChevronLeft, 
    ChevronRight, 
    Sparkles, 
    Calendar,
    Command
  } from '@lucide/svelte';

  let { onSelectDate } = $props();

  let query = $state('');
  let searchInput = $state(null);
  let scrollTrack = $state(null);
  let scrollLeft = $state(0);
  let containerWidth = $state(380);

  // 🌟 CRISP 3D GYRO TILT WITH GLOSS SHEEN (rAF-Throttled) 🌟
  let activeCardKey = $state(null);
  let tiltX = $state(0);
  let tiltY = $state(0);
  let glareX = $state(50);
  let glareY = $state(50);
  let tiltTicking = false;

  function handleCardMouseMove(e, key) {
    if (activeCardKey !== key) activeCardKey = key;
    if (tiltTicking) return;
    tiltTicking = true;

    const rect = e.currentTarget.getBoundingClientRect();
    const clientX = e.clientX;
    const clientY = e.clientY;

    requestAnimationFrame(() => {
      const normX = ((clientX - rect.left) / rect.width) * 2 - 1;
      const normY = ((clientY - rect.top) / rect.height) * 2 - 1;

      // 14° tilt range makes the 3D depth immediately noticeable
      tiltX = -normY * 14;
      tiltY = normX * 14;
      glareX = ((clientX - rect.left) / rect.width) * 100;
      glareY = ((clientY - rect.top) / rect.height) * 100;

      tiltTicking = false;
    });
  }

  function handleCardMouseLeave() {
    activeCardKey = null;
    tiltX = 0;
    tiltY = 0;
    glareX = 50;
    glareY = 50;
  }

  let filteredEntries = $derived(vocabIndexStore.search(query));
  let langConfig = $derived(activeLanguage.current);
  let themeColor = $derived(activeLanguage.themeColor || '#a855f7');

  const CARD_WIDTH = 136;
  const CARD_GAP = 12;
  const ITEM_STRIDE = CARD_WIDTH + CARD_GAP; // 148px stride
  const BUFFER_COUNT = 3;

  let totalWidth = $derived(
    filteredEntries.length > 0 ? filteredEntries.length * ITEM_STRIDE - CARD_GAP : 0
  );

  let startIndex = $derived(
    Math.max(0, Math.floor(scrollLeft / ITEM_STRIDE) - BUFFER_COUNT)
  );

  let endIndex = $derived(
    Math.min(
      filteredEntries.length,
      Math.ceil((scrollLeft + containerWidth) / ITEM_STRIDE) + BUFFER_COUNT
    )
  );

  let visibleEntries = $derived.by(() => {
    return filteredEntries.slice(startIndex, endIndex).map((item, idx) => ({
      ...item,
      virtualIndex: startIndex + idx,
      offsetLeft: (startIndex + idx) * ITEM_STRIDE
    }));
  });

  let canScrollLeft = $derived(scrollLeft > 10);
  let canScrollRight = $derived(scrollLeft + containerWidth < totalWidth - 10);

  function getSynchronizedTokens(native, pron, config) {
    const tokens = tokenizePhonetics(native, pron, config);
    if (tokens.primaryTokens?.length > 0 && tokens.secondaryTokens?.length > 0) {
      tokens.primaryTokens = tokens.primaryTokens.map((tok, i) => {
        const sec = tokens.secondaryTokens[i] || tokens.secondaryTokens[0];
        return {
          ...tok,
          color: tok.color || sec?.color || undefined
        };
      });
    }
    return tokens;
  }

  function handleScroll(e) {
    scrollLeft = e.currentTarget.scrollLeft;
  }

  function clearSearch() {
    query = '';
    if (scrollTrack) scrollTrack.scrollLeft = 0;
    if (searchInput) searchInput.focus();
  }

  function scrollByAmount(amount) {
    if (!scrollTrack) return;
    scrollTrack.scrollBy({ left: amount, behavior: 'smooth' });
  }

  function handleGlobalKeyDown(e) {
    if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k') {
      e.preventDefault();
      searchInput?.focus();
      searchInput?.select();
    } else if (e.key === '/' && document.activeElement.tagName !== 'INPUT' && document.activeElement.tagName !== 'TEXTAREA') {
      e.preventDefault();
      searchInput?.focus();
      searchInput?.select();
    }
  }
</script>

<svelte:window onkeydown={handleGlobalKeyDown} />

<div class="relative w-full space-y-3.5 pt-2 select-none group/stream">
  
  <!-- SECTION DIVIDER -->
  <div class="flex items-center gap-3">
    <div class="flex-1 h-px bg-gradient-to-r from-transparent via-[var(--border-subtle)] to-transparent"></div>
    <div class="flex items-center gap-2 px-3 py-1 rounded-full bg-[var(--bg-surface)] border border-[var(--border-subtle)] shadow-xs">
      <Search size={11} style="color: {themeColor};" />
      <span class="text-[10px] font-mono font-bold uppercase tracking-widest text-[var(--text-muted)]">
        Search
      </span>
    </div>
    <div class="flex-1 h-px bg-gradient-to-r from-transparent via-[var(--border-subtle)] to-transparent"></div>
  </div>

  <!-- SEARCH INPUT COMMAND CAPSULE -->
  <div 
    class="relative flex items-center gap-3 px-4 py-3 rounded-2xl border border-[var(--border-card)] bg-[var(--bg-surface)] shadow-xs transition-all duration-200 backdrop-blur-xl"
    style="
      --focus-ring: color-mix(in srgb, {themeColor} 25%, transparent);
      --focus-shadow: 0 0 20px color-mix(in srgb, {themeColor} 30%, transparent);
    "
    style:border-color={query ? themeColor : undefined}
  >
    <div class="relative flex items-center justify-center shrink-0">
      <Search 
        size={16} 
        class="text-[var(--text-muted)] transition-colors duration-200" 
        style={query ? `color: ${themeColor};` : ''} 
      />
      <div 
        class="absolute inset-0 blur-sm rounded-full opacity-0 group-focus-within/stream:opacity-100 transition-opacity"
        style="background-color: color-mix(in srgb, {themeColor} 25%, transparent);"
      ></div>
    </div>

    <!-- Input with no native outline or black focus ring -->
    <input
      bind:this={searchInput}
      bind:value={query}
      type="text"
      placeholder="Instant vocab lookup by glyph, pinyin or meaning..."
      class="w-full bg-transparent border-0 outline-none ring-0 focus:outline-none focus:ring-0 text-xs sm:text-sm font-semibold text-[var(--text-primary)] placeholder-[var(--text-muted)]/70 tracking-tight shadow-none"
    />

    <div class="flex items-center gap-2 shrink-0">
      {#if query}
        <button
          type="button"
          onclick={clearSearch}
          aria-label="Clear search"
          class="flex items-center justify-center w-5 h-5 rounded-lg bg-[var(--bg-surface-elevated)] hover:bg-rose-500/15 text-[var(--text-muted)] hover:text-rose-400 transition-colors cursor-pointer active:scale-90"
        >
          <X size={12} strokeWidth={2.5} />
        </button>
      {:else}
        <div class="hidden sm:flex items-center gap-0.5 px-1.5 py-0.5 rounded-md bg-[var(--badge-bg)] border border-[var(--border-subtle)] text-[10px] font-mono font-bold text-[var(--text-muted)]">
          <Command size={10} />
          <span>K</span>
        </div>
      {/if}

      <span class="text-[10px] font-mono font-bold px-2 py-0.5 rounded-lg bg-[var(--bg-surface-elevated)] text-[var(--text-secondary)] border border-[var(--border-subtle)] shadow-inner">
        {filteredEntries.length} {filteredEntries.length === 1 ? 'word' : 'words'}
      </span>
    </div>

  </div>

  <!-- VIRTUALIZED HORIZONTAL CAROUSEL -->
  {#if filteredEntries.length === 0}
    <div class="py-12 px-6 rounded-3xl border border-dashed border-[var(--border-card)] bg-[var(--bg-surface)]/40 backdrop-blur-xs text-center space-y-2">
      <div class="w-10 h-10 rounded-2xl bg-[var(--bg-surface-elevated)] border border-[var(--border-subtle)] flex items-center justify-center mx-auto text-[var(--text-muted)]">
        <Sparkles size={18} />
      </div>
      <p class="text-xs font-semibold text-[var(--text-primary)]">
        {query ? `No cards match "${query}"` : 'No vocabulary logged yet.'}
      </p>
      <p class="text-[10px] text-[var(--text-muted)] max-w-xs mx-auto">
        {query ? 'Check your spelling or search by tone number / pinyin syllable.' : 'Add your first vocabulary word in today\'s log to see the stream grow.'}
      </p>
    </div>
  {:else}
    <div class="relative w-full">
      
      <!-- Left Edge Navigation Paddle -->
      {#if canScrollLeft}
        <button
          type="button"
          aria-label="Scroll Left"
          onclick={() => scrollByAmount(-350)}
          class="absolute -left-3 top-1/2 -translate-y-1/2 z-30 w-8 h-8 rounded-full bg-[var(--bg-surface)]/90 hover:bg-[var(--bg-surface-elevated)] border border-[var(--border-card)] shadow-lg flex items-center justify-center text-[var(--text-primary)] transition-all duration-150 hover:scale-110 active:scale-95 cursor-pointer backdrop-blur-md"
        >
          <ChevronLeft size={16} strokeWidth={2.5} />
        </button>
      {/if}

      <!-- Right Edge Navigation Paddle -->
      {#if canScrollRight}
        <button
          type="button"
          aria-label="Scroll Right"
          onclick={() => scrollByAmount(350)}
          class="absolute -right-3 top-1/2 -translate-y-1/2 z-30 w-8 h-8 rounded-full bg-[var(--bg-surface)]/90 hover:bg-[var(--bg-surface-elevated)] border border-[var(--border-card)] shadow-lg flex items-center justify-center text-[var(--text-primary)] transition-all duration-150 hover:scale-110 active:scale-95 cursor-pointer backdrop-blur-md"
        >
          <ChevronRight size={16} strokeWidth={2.5} />
        </button>
      {/if}

      <!-- Ambient Edge Fading Masks -->
      {#if canScrollLeft}
        <div class="pointer-events-none absolute left-0 top-0 bottom-2 w-10 bg-gradient-to-r from-[var(--bg-base)] via-[var(--bg-base)]/50 to-transparent z-20"></div>
      {/if}
      {#if canScrollRight}
        <div class="pointer-events-none absolute right-0 top-0 bottom-2 w-10 bg-gradient-to-l from-[var(--bg-base)] via-[var(--bg-base)]/50 to-transparent z-20"></div>
      {/if}

      <!-- Track with unclipped perspective container -->
      <div 
        bind:this={scrollTrack}
        bind:clientWidth={containerWidth}
        onscroll={handleScroll}
        class="relative w-full overflow-x-auto overscroll-x-contain pb-6 pt-4 select-none h-[225px] touch-pan-x scroll-smooth"
      >
        <div class="relative h-full" style="width: {totalWidth}px; min-width: 100%;">
          {#each visibleEntries as item (item.word_id || item.native_script + item.date)}
            {@const key = item.word_id || item.native_script + item.date}
            {@const isHovered = activeCardKey === key}
            {@const tokens = getSynchronizedTokens(item.native_script, item.pronunciation, langConfig)}
            
            <div
              style="left: {item.offsetLeft}px;"
              class="absolute top-0 w-[136px] h-[198px] [perspective:800px]"
            >
              <!-- 🌟 3D GYROSCOPIC TILT CARD 🌟 -->
              <button
                type="button"
                onclick={() => onSelectDate(item.date)}
                onmousemove={(e) => handleCardMouseMove(e, key)}
                onmouseleave={handleCardMouseLeave}
                class="group/card w-full h-full flex flex-col items-center justify-between p-3 rounded-3xl border border-[var(--border-card)] bg-[var(--bg-surface)]/90 hover:bg-[var(--bg-surface-elevated)] active:scale-[0.96] text-center cursor-pointer outline-none relative backdrop-blur-md will-change-transform"
                style="
                  --card-hover-border: color-mix(in srgb, {themeColor} 60%, transparent);
                  transform-style: preserve-3d;
                  transform: {isHovered ? `rotateX(${tiltX}deg) rotateY(${tiltY}deg) translateZ(12px) scale(1.04)` : 'rotateX(0deg) rotateY(0deg) translateZ(0px) scale(1)'};
                  transition: {isHovered ? 'transform 0.05s linear, box-shadow 0.15s ease' : 'transform 0.3s cubic-bezier(0.16, 1, 0.3, 1), box-shadow 0.2s ease'};
                  box-shadow: {isHovered ? `0 20px 35px -8px rgba(0,0,0,0.5), 0 0 22px color-mix(in srgb, ${themeColor} 30%, transparent)` : '0 4px 12px -2px rgba(0,0,0,0.1)'};
                "
              >
                <!-- Specular Glare Layer Tracking Pointer -->
                <div 
                  class="pointer-events-none absolute inset-0 rounded-3xl opacity-0 transition-opacity duration-150 z-20 {isHovered ? 'opacity-100' : ''}"
                  style="background: radial-gradient(circle 160px at {glareX}% {glareY}%, rgba(255,255,255,0.22), transparent 75%);"
                ></div>

                <!-- THEME AMBIENT BLEED -->
                <div 
                  class="pointer-events-none absolute -inset-1 rounded-3xl overflow-hidden opacity-30 group-hover/card:opacity-60 transition-opacity duration-300 -z-10"
                >
                  {#if item.link}
                    <img 
                      src={item.link} 
                      alt="" 
                      aria-hidden="true" 
                      class="w-full h-full object-cover blur-xl scale-125 saturate-200 transform-gpu"
                    />
                  {:else}
                    <div 
                      class="w-full h-full blur-xl transform-gpu"
                      style="background: radial-gradient(circle at center, {themeColor} 0%, transparent 70%);"
                    ></div>
                  {/if}
                </div>

                <!-- Top Header: Date Pill -->
                <div class="w-full flex items-center justify-between gap-1 pb-1 relative z-10">
                  <span class="inline-flex items-center gap-1 font-mono text-[9px] font-bold text-[var(--text-muted)] group-hover/card:text-[var(--text-secondary)] transition-colors">
                    <Calendar size={10} />
                    <span>{item.date.slice(5)}</span>
                  </span>

                  <span 
                    class="w-1.5 h-1.5 rounded-full transition-colors"
                    style="background-color: {themeColor};"
                  ></span>
                </div>

                <!-- Media Preview Container (Crisp Glass Stage) -->
                <div class="relative w-full h-24 my-auto flex items-center justify-center rounded-2xl bg-[var(--bg-base)]/80 border border-[var(--border-subtle)] overflow-hidden pointer-events-none group-hover/card:border-[var(--border-hover)] transition-colors shadow-inner z-10">
                  <MediaStage 
                    src={item.link} 
                    alt={item.native_script} 
                    fallbackChar={item.native_script}
                    observerRoot={scrollTrack}
                  />
                </div>

                <!-- Footer Text Stack: Both lines share matching tone colors -->
                <div class="w-full pt-1.5 space-y-0.5 relative z-10">
                  <div class="w-full text-base font-black truncate leading-tight tracking-tight drop-shadow-xs">
                    <ColoredText tokens={tokens.primaryTokens} fallbackClass="text-[var(--text-primary)]" />
                  </div>

                  <div class="w-full text-[11px] font-mono font-bold truncate leading-tight">
                    <ColoredText tokens={tokens.secondaryTokens} fallbackClass="text-[var(--text-muted)]" />
                  </div>
                </div>

              </button>
            </div>
          {/each}
        </div>
      </div>

    </div>
  {/if}

</div>