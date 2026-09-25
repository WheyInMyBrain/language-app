<!-- frontend/src/components/OmniCard.svelte -->
<script>
  import { activeLanguage } from '../lib/stores/activeLanguage.svelte.js';
  import { tokenizePhonetics } from '../lib/formatters/phonetics.js';
  import { formatSecondsToTimer } from '../lib/mediaResolver.js';
  import { playTTS } from '../lib/tts.js';

  // Subcomponents
  import ColoredText from './ColoredText.svelte';
  import VideoPlayer from './VideoPlayer.svelte';
  import AudioBar from './AudioBar.svelte';

  // Razor-sharp vector icons
  import { 
    Volume2, 
    Play, 
    Headphones, 
    BookOpen, 
    MessageSquare, 
    ChevronDown, 
    Mic, 
    Sparkles,
    ImageOff
  } from '@lucide/svelte';

  // 🌟 EXACT SYNCHRONIZED TONE CHROMA ENGINE FROM VOCABSEARCHSTREAM 🌟
  const tokenCache = new Map();
  function getSynchronizedTokens(script, pron, cfg) {
    const key = `${cfg?.code || 'zh-CN'}:${script || ''}:${pron || ''}`;
    if (tokenCache.has(key)) return tokenCache.get(key);

    const parsed = tokenizePhonetics(script, pron, cfg);
    const primary = parsed.primaryTokens || [];
    const secondary = parsed.secondaryTokens || [];

    const coloredSecondary = secondary.filter(t => t.color);

    const syncedPrimary = primary.map((tok, i) => {
      if (tok.color) return tok;
      const matchColor = secondary[i]?.color || coloredSecondary[i]?.color || coloredSecondary[0]?.color;
      return matchColor ? { ...tok, color: matchColor } : tok;
    });

    const result = {
      primaryTokens: syncedPrimary,
      secondaryTokens: secondary
    };

    if (tokenCache.size > 800) tokenCache.clear();
    tokenCache.set(key, result);
    return result;
  }

  let {
    type = 'vocab',
    lang = 'zh-CN',
    date = '',
    item = {},
    index = 1,
    isOpen = false
  } = $props();

  let isExpanded = $state(false);$effect(() => {
    isExpanded = isOpen;
  });

  let isCopied = $state(false);
  let isSpeaking = $state(false);
  let audioDuration = $state(item.audio_duration || 0);

  // 🌟 ROBUST MEDIA LOADING STATE 🌟
  // Only track changes to the link string itself, avoiding re-triggers on audio duration changes
  let lastLink = $state(null);
  let isMediaLoading = $state(false);
  let hasMediaError = $state(false);

  $effect(() => {
    const currentLink = item.link || null;
    if (currentLink !== lastLink) {
      lastLink = currentLink;
      if (currentLink) {
        isMediaLoading = true;
        hasMediaError = false;
      } else {
        isMediaLoading = false;
        hasMediaError = false;
      }
    }
  });

  // Action to instantly resolve cached images
  function initImage(node) {
    if (node.complete && node.naturalWidth > 0) {
      isMediaLoading = false;
    }
  }

  // 3D Gyroscopic Tilt States
  let cardEl = $state(null);
  let rotateX = $state(0);
  let rotateY = $state(0);
  let glareX = $state(50);
  let glareY = $state(50);
  let isHovered = $state(false);
  let tiltTicking = false;

  let langConfig = $derived(activeLanguage.current);
  let colors = $derived(activeLanguage.colors || {});
  let themeColor = $derived(activeLanguage.themeColor || '#a855f7');

  const typeMeta = $derived.by(() => {
    switch (type) {
      case 'vocab':
        return {
          label: 'Vocab',
          icon: MessageSquare,
          color: colors.vocab?.dark_primary || colors.vocab?.primary || themeColor || '#10b981',
          colorSub: colors.vocab?.light_primary || '#34d399',
          audioCategory: 'vocab',
          prompt: 'Practice pronunciation'
        };
      case 'ci':
        return {
          label: 'CI Video',
          icon: Play,
          color: colors.ci?.dark_primary || colors.ci?.primary || themeColor || '#a855f7',
          colorSub: colors.ci?.light_primary || '#c084fc',
          audioCategory: 'ci',
          prompt: 'Practice shadowing'
        };
      case 'listening':
        return {
          label: 'Listening',
          icon: Headphones,
          color: colors.listening?.dark_primary || colors.listening?.primary || themeColor || '#f97316',
          colorSub: colors.listening?.light_primary || '#fb923c',
          audioCategory: 'listening',
          prompt: 'Summarise video'
        };
      case 'grammar':
      default:
        return {
          label: 'Grammar',
          icon: BookOpen,
          color: colors.grammar?.dark_primary || colors.grammar?.primary || themeColor || '#0ea5e9',
          colorSub: colors.grammar?.light_primary || '#38bdf8',
          audioCategory: 'grammar',
          prompt: 'Record audio'
        };
    }
  });

  let youtubeThumbnail = $derived.by(() => {
    if (!item.link) return null;
    const url = item.link;
    const match = url.match(/(?:youtu\.be\/|youtube\.com\/(?:embed\/|v\/|watch\?v=|watch\?.+&v=))([\w-]{11})/);
    return match ? `https://img.youtube.com/vi/${match[1]}/hqdefault.jpg` : null;
  });

  let mediaSrc = $derived(
    type === 'vocab' ? item.link : (youtubeThumbnail || null)
  );

  let vocabTokens = $derived(
    type === 'vocab'
      ? getSynchronizedTokens(item.native_script, item.pronunciation, langConfig)
      : { primaryTokens: [], secondaryTokens: [] }
  );

  let grammarMeta = $derived(type === 'grammar' ? (item.metadata || {}) : {});
  let grammarTitle = $derived(grammarMeta.title || `Grammar Point #${index}`);
  let grammarPronTokens = $derived(
    type === 'grammar'
      ? getSynchronizedTokens('', grammarMeta.pronunciation || '', langConfig)
      : { secondaryTokens: [] }
  );

  let duration = $derived(item.link_duration || item.durationSec || 0);
  let displayTimer = $derived(duration > 0 ? formatSecondsToTimer(duration) : null);

  // RAF-Throttled Gyroscopic Mouse Move
  function handleMouseMove(e) {
    if (!cardEl || tiltTicking) return;
    tiltTicking = true;

    const rect = cardEl.getBoundingClientRect();
    const clientX = e.clientX;
    const clientY = e.clientY;

    requestAnimationFrame(() => {
      const normX = ((clientX - rect.left) / rect.width) * 2 - 1;
      const normY = ((clientY - rect.top) / rect.height) * 2 - 1;

      rotateX = -normY * 4.5;
      rotateY = normX * 4.5;
      glareX = ((clientX - rect.left) / rect.width) * 100;
      glareY = ((clientY - rect.top) / rect.height) * 100;

      tiltTicking = false;
    });
  }

  function handleMouseEnter() {
    isHovered = true;
  }

  function handleMouseLeave() {
    isHovered = false;
    rotateX = 0;
    rotateY = 0;
  }

  function handlePronounce(e) {
    e.stopPropagation();
    const textToSpeak = item.native_script || grammarTitle;
    if (!textToSpeak) return;
    isSpeaking = true;
    playTTS(textToSpeak, langConfig?.code || 'zh-CN');
    setTimeout(() => (isSpeaking = false), 1200);
  }

  async function handleCopyLink(e) {
    e.stopPropagation();
    const link = item.link;
    if (!link) return;

    try {
      await navigator.clipboard.writeText(link);
      isCopied = true;
      setTimeout(() => (isCopied = false), 1800);
    } catch {}
  }
</script>

<div 
  class="relative w-full [perspective:1000px] select-none group"
  style="
    --card-accent: {typeMeta.color}; 
    --card-accent-sub: {typeMeta.colorSub};
    content-visibility: auto;
  "
>
  <div 
    bind:this={cardEl}
    role="presentation"
    onmousemove={handleMouseMove}
    onmouseenter={handleMouseEnter}
    onmouseleave={handleMouseLeave}
    class="group/card relative w-full rounded-3xl border border-[var(--border-card)] bg-[var(--bg-surface)]/90 hover:bg-[var(--bg-surface-elevated)] transition-all duration-200 active:scale-[0.98] flex flex-col justify-between overflow-hidden will-change-transform backdrop-blur-md"
    style="
      --card-hover-border: color-mix(in srgb, {themeColor} 60%, transparent);
      transform: {isHovered ? `rotateX(${rotateX}deg) rotateY(${rotateY}deg) translateY(-4px) scale(1.008)` : 'rotateX(0deg) rotateY(0deg) translateY(0) scale(1)'};
      transform-style: preserve-3d;
      transition: transform 0.12s cubic-bezier(0.16, 1, 0.3, 1), box-shadow 0.2s ease, border-color 0.2s ease;
    "
  >
    <!-- Backlight Diffusion Layer -->
    <div 
      class="pointer-events-none absolute -inset-1 rounded-3xl overflow-hidden opacity-30 group-hover:opacity-60 transition-opacity duration-300 -z-10"
    >
      {#if mediaSrc && !hasMediaError}
        <img 
          src={mediaSrc} 
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

    <!-- Cursor Glare Sheen -->
    <div 
      class="pointer-events-none absolute inset-0 opacity-0 transition-opacity duration-150 z-30 {isHovered ? 'opacity-100' : ''}"
      style="background: radial-gradient(circle 320px at {glareX}% {glareY}%, rgba(255,255,255,0.08), transparent 75%);"
    ></div>

    <!-- Top Specular Neon Lip -->
    <div 
      class="pointer-events-none absolute top-0 left-0 right-0 h-[2px] opacity-90 z-20"
      style="background: linear-gradient(90deg, transparent 5%, var(--card-accent) 30%, var(--card-accent-sub) 70%, transparent 95%);"
    ></div>

    <!-- ============================================== -->
    <!-- VOCABULARY CARD STAGE                          -->
    <!-- ============================================== -->
    {#if type === 'vocab'}
      
      {#if item.link}
        <div class="relative w-full min-h-[160px] max-h-80 overflow-hidden flex items-center justify-center p-3.5 z-10">
          
          {#if isMediaLoading}
            <div 
              class="absolute inset-3.5 rounded-2xl border border-white/10 bg-black/40 backdrop-blur-xl flex flex-col items-center justify-center space-y-3 overflow-hidden shadow-inner z-20 transition-opacity duration-300"
            >
              <div 
                class="absolute left-0 right-0 h-[2px] opacity-80 animate-radar"
                style="background: linear-gradient(90deg, transparent 5%, var(--card-accent) 50%, transparent 95%); box-shadow: 0 0 14px var(--card-accent);"
              ></div>

              <div class="relative flex items-center justify-center">
                <div 
                  class="w-12 h-12 rounded-full border border-white/20 animate-spin"
                  style="border-top-color: var(--card-accent); animation-duration: 1.2s;"
                ></div>
                <div 
                  class="absolute w-8 h-8 rounded-full blur-md opacity-50"
                  style="background-color: var(--card-accent);"
                ></div>
                <Sparkles size={16} class="absolute text-white animate-pulse" />
              </div>

              <div class="flex items-center gap-1.5 px-3 py-1 rounded-full bg-white/10 border border-white/10 shadow-xs backdrop-blur-md">
                <span class="w-1.5 h-1.5 rounded-full animate-ping" style="background-color: var(--card-accent);"></span>
                <span class="text-[10px] font-mono font-bold text-white/80 uppercase tracking-widest">
                  Resolving Asset...
                </span>
              </div>
            </div>
          {/if}

          {#if hasMediaError}
            <div class="w-full h-44 rounded-2xl border border-dashed border-white/15 bg-black/40 backdrop-blur-md flex flex-col items-center justify-center space-y-1.5 text-neutral-400">
              <ImageOff size={22} class="opacity-60" />
              <span class="text-[10px] font-mono font-bold tracking-tight text-white/50">Media Unavailable</span>
            </div>
          {:else}
            <img 
              use:initImage
              src={item.link} 
              alt={item.native_script} 
              loading="lazy"
              decoding="async"
              onload={() => (isMediaLoading = false)}
              onerror={() => {
                isMediaLoading = false;
                hasMediaError = true;
              }}
              class="w-full h-auto max-h-72 object-contain rounded-2xl shadow-xl ring-1 ring-white/10 transition-opacity duration-300 {isMediaLoading ? 'opacity-0 scale-95' : 'opacity-100 scale-100'}"
            />
          {/if}

          <div class="absolute top-4 left-4 z-10">
            <span 
              class="px-2.5 py-1 rounded-xl text-[10px] font-mono font-black border border-white/20 text-white bg-black/60 shadow-md backdrop-blur-md"
            >
              #{index}
            </span>
          </div>

          <button
            type="button"
            onclick={handlePronounce}
            class="absolute top-4 right-4 w-8 h-8 rounded-xl border border-white/20 bg-black/60 hover:bg-black/80 text-white flex items-center justify-center transition-transform duration-100 active:scale-90 hover:scale-105 cursor-pointer shadow-md z-10 backdrop-blur-md"
          >
            <Volume2 size={15} class={isSpeaking ? 'text-emerald-400 animate-pulse' : ''} />
          </button>
        </div>
      {/if}

      <div class="p-5 sm:p-6 flex flex-col justify-between flex-1 space-y-4 z-10 relative">
        <div class="space-y-1.5">
          {#if !item.link}
            <div class="flex items-center justify-between pb-1">
              <span 
                class="px-2.5 py-0.5 rounded-lg text-[10px] font-mono font-black border shadow-2xs"
                style="
                  color: var(--card-accent); 
                  background-color: color-mix(in srgb, var(--card-accent) 18%, transparent);
                  border-color: color-mix(in srgb, var(--card-accent) 35%, transparent);
                "
              >
                #{index}
              </span>

              <button
                type="button"
                onclick={handlePronounce}
                class="w-7 h-7 rounded-lg border border-white/15 bg-black/40 hover:bg-black/70 flex items-center justify-center text-white/80 hover:text-white transition-colors cursor-pointer shadow-xs backdrop-blur-md"
              >
                <Volume2 size={13} class={isSpeaking ? 'text-[var(--card-accent)] animate-pulse' : ''} />
              </button>
            </div>
          {/if}

          <!-- Synchronized Tone Chroma Text -->
          <div class="text-3xl sm:text-4xl font-black tracking-tight leading-none drop-shadow-xs">
            <ColoredText tokens={vocabTokens.primaryTokens} fallbackClass="text-[var(--text-primary)]" />
          </div>

          {#if item.pronunciation}
            <div class="text-xs sm:text-sm font-mono font-bold tracking-wide">
              <ColoredText tokens={vocabTokens.secondaryTokens} fallbackClass="text-[var(--text-muted)]" />
            </div>
          {/if}
        </div>

        <!-- ACCORDION WITH ISOLATED AUDIOBAR -->
        <div 
          class="grid transition-[grid-template-rows,opacity] duration-300 ease-[cubic-bezier(0.16,1,0.3,1)] {isExpanded ? 'grid-rows-[1fr] opacity-100' : 'grid-rows-[0fr] opacity-0 pointer-events-none'}"
        >
          <div class="overflow-hidden min-h-0">
            <div class="pt-3 border-t border-[var(--border-subtle)] space-y-3">
              <AudioBar 
                {lang}
                {date}
                category={typeMeta.audioCategory}
                {index}
                initialDuration={item.audio_duration || 0}
                accentColor={typeMeta.color}
                accentColorSub={typeMeta.colorSub}
                {type}
                {item}
                onDurationChange={(dur) => (audioDuration = dur)}
              />
            </div>
          </div>
        </div>

        <button
          type="button"
          onclick={() => (isExpanded = !isExpanded)}
          class="w-full pt-2 flex items-center justify-between text-[11px] font-mono font-bold text-[var(--text-muted)] hover:text-[var(--text-primary)] transition-colors cursor-pointer border-t border-[var(--border-subtle)]"
        >
          <span class="flex items-center gap-1.5">
            <Mic size={12} style="color: var(--card-accent);" />
            <span>{audioDuration > 0 ? `${Math.round(audioDuration)}s recorded` : typeMeta.prompt}</span>
          </span>
          <ChevronDown size={13} class="transition-transform duration-300 {isExpanded ? 'rotate-180' : ''}" />
        </button>

      </div>

    <!-- ============================================== -->
    <!-- CI VIDEO CARD                                  -->
    <!-- ============================================== -->
    {:else if type === 'ci'}

      <div class="p-5 sm:p-6 space-y-4 flex flex-col justify-between flex-1 z-10 relative">
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-2">
            <span 
              class="px-2.5 py-0.5 rounded-lg text-[10px] font-mono font-black border shadow-2xs"
              style="
                color: var(--card-accent); 
                background-color: color-mix(in srgb, var(--card-accent) 18%, transparent);
                border-color: color-mix(in srgb, var(--card-accent) 35%, transparent);
              "
            >
              #{index}
            </span>
            <span class="text-xs font-bold text-[var(--text-primary)] flex items-center gap-1.5 drop-shadow-sm">
              <Play size={13} style="color: var(--card-accent);" />
              <span>Comprehensible Input</span>
            </span>
          </div>

          <div class="flex items-center gap-1.5">
            {#if item.link}
              <button
                type="button"
                onclick={handleCopyLink}
                class="px-2.5 py-1 rounded-lg border border-[var(--border-subtle)] bg-[var(--bg-surface)] hover:bg-[var(--bg-surface-elevated)] text-[10px] font-mono text-[var(--text-muted)] hover:text-[var(--text-primary)] transition-all duration-150 active:scale-85 hover:scale-105 cursor-pointer shadow-xs"
              >
                {isCopied ? '✓ Copied' : 'Copy'}
              </button>
            {/if}

            {#if displayTimer}
              <span 
                class="px-2.5 py-1 rounded-lg text-[10px] font-mono font-bold border shadow-xs"
                style="color: var(--card-accent); background-color: color-mix(in srgb, var(--card-accent) 18%, transparent); border-color: color-mix(in srgb, var(--card-accent) 35%, transparent);"
              >
                ⏱️ {displayTimer}
              </span>
            {/if}
          </div>
        </div>

        <div class="relative w-full min-h-[190px] rounded-2xl overflow-hidden border border-[var(--border-card)] shadow-2xl bg-black/60">
          <VideoPlayer 
            src={item.link || ''} 
            accentColor={typeMeta.color} 
            fallbackText="No video link logged."
          />
        </div>

        <!-- CI ACCORDION DRAWER WITH AUDIOBAR -->
        <div 
          class="grid transition-[grid-template-rows,opacity] duration-300 ease-[cubic-bezier(0.16,1,0.3,1)] {isExpanded ? 'grid-rows-[1fr] opacity-100' : 'grid-rows-[0fr] opacity-0 pointer-events-none'}"
        >
          <div class="overflow-hidden min-h-0">
            <div class="pt-3 border-t border-[var(--border-subtle)] space-y-3">
              <AudioBar 
                {lang}
                {date}
                category={typeMeta.audioCategory}
                {index}
                initialDuration={item.audio_duration || 0}
                accentColor={typeMeta.color}
                accentColorSub={typeMeta.colorSub}
                {type}
                {item}
                onDurationChange={(dur) => (audioDuration = dur)}
              />
            </div>
          </div>
        </div>

        <button
          type="button"
          onclick={() => (isExpanded = !isExpanded)}
          class="w-full pt-2 flex items-center justify-between text-[11px] font-mono font-bold text-[var(--text-muted)] hover:text-[var(--text-primary)] transition-colors cursor-pointer border-t border-[var(--border-subtle)]"
        >
          <span class="flex items-center gap-1.5">
            <Mic size={12} style="color: var(--card-accent);" />
            <span>{audioDuration > 0 ? `${Math.round(audioDuration)}s recorded` : typeMeta.prompt}</span>
          </span>
          <ChevronDown size={13} class="transition-transform duration-300 {isExpanded ? 'rotate-180' : ''}" />
        </button>
      </div>

    <!-- ============================================== -->
    <!-- LISTENING IMMERSION CARD                       -->
    <!-- ============================================== -->
    {:else if type === 'listening'}

      <div class="p-5 sm:p-6 space-y-4 flex flex-col justify-between flex-1 z-10 relative">
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-2">
            <span 
              class="px-2.5 py-0.5 rounded-lg text-[10px] font-mono font-black border shadow-2xs"
              style="
                color: var(--card-accent); 
                background-color: color-mix(in srgb, var(--card-accent) 18%, transparent);
                border-color: color-mix(in srgb, var(--card-accent) 35%, transparent);
              "
            >
              #{index}
            </span>
            <span class="text-xs font-bold text-[var(--text-primary)] flex items-center gap-1.5 drop-shadow-sm">
              <Headphones size={13} style="color: var(--card-accent);" />
              <span>Listening Immersion</span>
            </span>
          </div>

          <div class="flex items-center gap-1.5">
            {#if item.link}
              <button
                type="button"
                onclick={handleCopyLink}
                class="px-2.5 py-1 rounded-lg border border-[var(--border-subtle)] bg-[var(--bg-surface)] hover:bg-[var(--bg-surface-elevated)] text-[10px] font-mono text-[var(--text-muted)] hover:text-[var(--text-primary)] transition-all duration-150 active:scale-85 hover:scale-105 cursor-pointer shadow-xs"
              >
                {isCopied ? '✓ Copied' : 'Copy'}
              </button>
            {/if}

            {#if displayTimer}
              <span 
                class="px-2.5 py-1 rounded-lg text-[10px] font-mono font-bold border shadow-xs"
                style="color: var(--card-accent); background-color: color-mix(in srgb, var(--card-accent) 18%, transparent); border-color: color-mix(in srgb, var(--card-accent) 35%, transparent);"
              >
                ⏱️ {displayTimer}
              </span>
            {/if}
          </div>
        </div>

        <div class="relative w-full min-h-[190px] rounded-2xl overflow-hidden border border-[var(--border-card)] shadow-2xl bg-black/60">
          <VideoPlayer 
            src={item.link || ''} 
            accentColor={typeMeta.color} 
            fallbackText="Audio session (no video embed)."
          />
        </div>

        <!-- LISTENING ACCORDION DRAWER WITH AUDIOBAR -->
        <div 
          class="grid transition-[grid-template-rows,opacity] duration-300 ease-[cubic-bezier(0.16,1,0.3,1)] {isExpanded ? 'grid-rows-[1fr] opacity-100' : 'grid-rows-[0fr] opacity-0 pointer-events-none'}"
        >
          <div class="overflow-hidden min-h-0">
            <div class="pt-3 border-t border-[var(--border-subtle)] space-y-3">
              <AudioBar 
                {lang}
                {date}
                category={typeMeta.audioCategory}
                {index}
                initialDuration={item.audio_duration || 0}
                accentColor={typeMeta.color}
                accentColorSub={typeMeta.colorSub}
                {type}
                {item}
                onDurationChange={(dur) => (audioDuration = dur)}
              />
            </div>
          </div>
        </div>

        <button
          type="button"
          onclick={() => (isExpanded = !isExpanded)}
          class="w-full pt-2 flex items-center justify-between text-[11px] font-mono font-bold text-[var(--text-muted)] hover:text-[var(--text-primary)] transition-colors cursor-pointer border-t border-[var(--border-subtle)]"
        >
          <span class="flex items-center gap-1.5">
            <Mic size={12} style="color: var(--card-accent);" />
            <span>{audioDuration > 0 ? `${Math.round(audioDuration)}s recorded` : typeMeta.prompt}</span>
          </span>
          <ChevronDown size={13} class="transition-transform duration-300 {isExpanded ? 'rotate-180' : ''}" />
        </button>
      </div>

    <!-- ============================================== -->
    <!-- GRAMMAR CARD                                   -->
    <!-- ============================================== -->
    {:else}

      <div class="p-5 sm:p-6 space-y-4 flex flex-col justify-between flex-1 z-10 relative">
        <div class="flex items-center justify-between">
          <span 
            class="px-2.5 py-0.5 rounded-lg text-[10px] font-mono font-black border shadow-2xs"
            style="
              color: var(--card-accent); 
              background-color: color-mix(in srgb, var(--card-accent) 18%, transparent);
              border-color: color-mix(in srgb, var(--card-accent) 35%, transparent);
            "
          >
            #{index}
          </span>

          <button
            type="button"
            onclick={handlePronounce}
            class="w-7 h-7 rounded-lg border border-[var(--border-subtle)] bg-[var(--bg-surface)] hover:bg-[var(--bg-surface-elevated)] flex items-center justify-center text-[var(--text-muted)] hover:text-[var(--text-primary)] transition-all cursor-pointer shadow-xs"
          >
            <Volume2 size={13} class={isSpeaking ? 'text-emerald-400 animate-pulse' : ''} />
          </button>
        </div>

        <div class="space-y-1.5">
          <h3 class="text-2xl font-black text-[var(--text-primary)] tracking-tight drop-shadow-xs">
            {grammarTitle}
          </h3>
          
          {#if grammarMeta.pronunciation}
            <div class="text-xs font-mono font-bold text-[var(--text-muted)]">
              <ColoredText tokens={grammarPronTokens.secondaryTokens} fallbackClass="text-[var(--text-muted)]" />
            </div>
          {/if}
        </div>

        {#if grammarMeta.structure}
          <div class="p-3.5 rounded-2xl bg-[var(--bg-base)]/80 border border-[var(--border-subtle)] space-y-1 shadow-inner">
            <span class="text-[9px] font-mono font-black uppercase tracking-wider block" style="color: var(--card-accent);">
              Formula
            </span>
            <span class="text-xs sm:text-sm font-mono font-bold text-[var(--text-primary)] block">
              {grammarMeta.structure}
            </span>
          </div>
        {/if}

        {#if grammarMeta.meaning}
          <p class="text-xs text-[var(--text-muted)] leading-relaxed font-medium">
            {grammarMeta.meaning}
          </p>
        {/if}

        <!-- GRAMMAR ACCORDION DRAWER WITH AUDIOBAR -->
        <div 
          class="grid transition-[grid-template-rows,opacity] duration-300 ease-[cubic-bezier(0.16,1,0.3,1)] {isExpanded ? 'grid-rows-[1fr] opacity-100' : 'grid-rows-[0fr] opacity-0 pointer-events-none'}"
        >
          <div class="overflow-hidden min-h-0">
            <div class="pt-3 border-t border-[var(--border-subtle)] space-y-3">
              <AudioBar 
                {lang}
                {date}
                category={typeMeta.audioCategory}
                {index}
                initialDuration={item.audio_duration || 0}
                accentColor={typeMeta.color}
                accentColorSub={typeMeta.colorSub}
                {type}
                {item}
                onDurationChange={(dur) => (audioDuration = dur)}
              />
            </div>
          </div>
        </div>

        <button
          type="button"
          onclick={() => (isExpanded = !isExpanded)}
          class="w-full pt-2 flex items-center justify-between text-[11px] font-mono font-bold text-[var(--text-muted)] hover:text-[var(--text-primary)] transition-colors cursor-pointer border-t border-[var(--border-subtle)]"
        >
          <span class="flex items-center gap-1.5">
            <Mic size={12} style="color: var(--card-accent);" />
            <span>{audioDuration > 0 ? `${Math.round(audioDuration)}s recorded` : typeMeta.prompt}</span>
          </span>
          <ChevronDown size={13} class="transition-transform duration-300 {isExpanded ? 'rotate-180' : ''}" />
        </button>
      </div>

    {/if}

  </div>
</div>

<style>
  @keyframes radar {
    0% {
      top: 0%;
      opacity: 0.2;
    }
    50% {
      top: 98%;
      opacity: 0.9;
    }
    100% {
      top: 0%;
      opacity: 0.2;
    }
  }

  .animate-radar {
    animation: radar 2.4s ease-in-out infinite;
  }
</style>