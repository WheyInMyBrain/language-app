<!-- frontend/src/components/OmniCard.svelte -->
<script>
  import { onDestroy } from 'svelte';
  import { activeLanguage } from '../lib/stores/activeLanguage.svelte.js';
  import { tokenizePhonetics } from '../lib/formatters/phonetics.js';
  import { formatSecondsToTimer } from '../lib/mediaResolver.js';
  import { playTTS } from '../lib/tts.js';
  import { getDocHandle, createSyncedDoc } from '../lib/yjs.js';
  import { resolveAudioSource, saveAudioRecord } from '../lib/audioSync.js';
  import { metadataStore } from '../lib/stores/metadata.svelte.js';

  // Subcomponents
  import ColoredText from './ColoredText.svelte';
  import VideoPlayer from './VideoPlayer.svelte';

  // Razor-sharp vector icons
  import { 
    Volume2, 
    Play, 
    Pause, 
    Square, 
    Headphones, 
    BookOpen, 
    MessageSquare, 
    ChevronDown, 
    Mic, 
    CloudUpload, 
    Sparkles,
    ImageOff,
    Loader2
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

  // 🌟 MEDIA RESOLUTION & LOADING STATES 🌟
  let isMediaLoading = $state(true);
  let hasMediaError = $state(false);

  // Reset loading state when the link changes
  $effect(() => {
    if (item.link) {
      isMediaLoading = true;
      hasMediaError = false;
    } else {
      isMediaLoading = false;
    }
  });

  // 3D Gyroscopic Tilt States
  let cardEl = $state(null);
  let rotateX = $state(0);
  let rotateY = $state(0);
  let glareX = $state(50);
  let glareY = $state(50);
  let isHovered = $state(false);
  let tiltTicking = false;

  // Audio Recording & Playback State
  let isRecording = $state(false);
  let isPlaying = $state(false);
  let isPendingSync = $state(false);
  let isLoadingAudio = $state(false);
  let elapsedSec = $state(0);
  let playbackProgress = $state(0);
  let currentTimeDisplay = $state('0:00');
  
  let recordedDuration = $state(null);
  let currentAudioDuration = $derived(recordedDuration ?? (item.audio_duration || 0));

  let resolvedUrl = $state(null);
  let audioEl = $state(null);
  let timerInterval = null;
  let playbackInterval = null;
  let mediaRecorder = null;
  let recordedChunks = [];

  onDestroy(() => {
    if (timerInterval) clearInterval(timerInterval);
    if (playbackInterval) clearInterval(playbackInterval);
    if (audioEl) audioEl.pause();
    if (resolvedUrl && resolvedUrl.startsWith('blob:')) {
      URL.revokeObjectURL(resolvedUrl);
    }
  });

  let langConfig = $derived(activeLanguage.current);
  let colors = $derived(activeLanguage.colors || {});
  let themeColor = $derived(activeLanguage.themeColor || '#a855f7');

  const typeMeta = $derived.by(() => {
    switch (type) {
      case 'vocab':
        return {
          label: 'Vocab',
          icon: MessageSquare,
          color: colors.vocab?.primary || colors.vocab?.dark_primary || themeColor || '#10b981',
          colorSub: colors.vocab?.light_primary || '#34d399',
          audioCategory: 'vocab'
        };
      case 'ci':
        return {
          label: 'CI Video',
          icon: Play,
          color: colors.ci?.primary || colors.ci?.dark_primary || themeColor || '#a855f7',
          colorSub: colors.ci?.light_primary || '#c084fc',
          audioCategory: 'ci'
        };
      case 'listening':
        return {
          label: 'Listening',
          icon: Headphones,
          color: colors.listening?.primary || colors.listening?.dark_primary || themeColor || '#f97316',
          colorSub: colors.listening?.light_primary || '#fb923c',
          audioCategory: 'listening'
        };
      case 'grammar':
      default:
        return {
          label: 'Grammar',
          icon: BookOpen,
          color: colors.grammar?.primary || colors.grammar?.dark_primary || themeColor || '#0ea5e9',
          colorSub: colors.grammar?.light_primary || '#38bdf8',
          audioCategory: 'grammar'
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

  // Synchronized primary & secondary tokens
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

  function formatTime(s) {
    const mins = Math.floor(s / 60);
    const secs = Math.floor(s % 60);
    return `${mins}:${secs < 10 ? '0' : ''}${secs}`;
  }

  function persistDurationLocally(seconds) {
    const roomName = `${lang}:${date}`;
    const handle = getDocHandle(roomName) || createSyncedDoc(roomName);
    if (!handle?.doc) return;

    if (type === 'vocab') {
      const wordsArr = handle.doc.getArray('words');
      const list = wordsArr.toArray().flat();
      const targetIdx = list.findIndex((w) => Number(w.word_index ?? w.id) === Number(index));

      if (targetIdx !== -1) {
        handle.doc.transact(() => {
          const updated = { ...list[targetIdx], audio_duration: seconds };
          wordsArr.delete(targetIdx, 1);
          wordsArr.insert(targetIdx, [updated]);
        });
      }
    } else {
      const actsArr = handle.doc.getArray('activities');
      const list = actsArr.toArray().flat();
      const targetIdx = list.findIndex(
        (a) => a.activity_type === type && Number(a.item_index) === Number(index)
      );

      if (targetIdx !== -1) {
        handle.doc.transact(() => {
          const updated = { ...list[targetIdx], audio_duration: seconds };
          actsArr.delete(targetIdx, 1);
          actsArr.insert(targetIdx, [updated]);
        });
      }
    }

    metadataStore.refreshDayTotals(lang, date);
  }

  async function toggleRecord() {
    if (isRecording) {
      if (timerInterval) clearInterval(timerInterval);
      mediaRecorder?.stop();
      isRecording = false;
      return;
    }

    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      recordedChunks = [];
      mediaRecorder = new MediaRecorder(stream, { mimeType: 'audio/webm' });

      mediaRecorder.ondataavailable = (e) => {
        if (e.data.size > 0) recordedChunks.push(e.data);
      };

      mediaRecorder.onstop = async () => {
        stream.getTracks().forEach((t) => t.stop());
        const blob = new Blob(recordedChunks, { type: 'audio/webm' });
        const finalDuration = elapsedSec || 1;

        if (resolvedUrl && resolvedUrl.startsWith('blob:')) {
          URL.revokeObjectURL(resolvedUrl);
        }

        resolvedUrl = URL.createObjectURL(blob);
        recordedDuration = finalDuration;
        isPendingSync = true;

        persistDurationLocally(finalDuration);

        const wasUploaded = await saveAudioRecord({
          lang,
          date,
          category: typeMeta.audioCategory,
          index: item.word_index ?? item.item_index ?? item.id ?? index,
          blob,
          duration: finalDuration
        });

        if (wasUploaded) {
          isPendingSync = false;
        }
      };

      mediaRecorder.start();
      isRecording = true;
      elapsedSec = 0;
      timerInterval = setInterval(() => {
        elapsedSec += 1;
      }, 1000);
    } catch (err) {
      console.error('Mic access error:', err);
      alert('Microphone permission required for audio recordings.');
    }
  }

  async function togglePlayback() {
    if (isPlaying && audioEl) {
      audioEl.pause();
      isPlaying = false;
      if (playbackInterval) clearInterval(playbackInterval);
      return;
    }

    if (!resolvedUrl) {
      isLoadingAudio = true;
      try {
        const itemIdx = item.word_index ?? item.item_index ?? item.id ?? index;
        const res = await resolveAudioSource(lang, date, typeMeta.audioCategory, itemIdx, currentAudioDuration);
        resolvedUrl = res.url;
        isPendingSync = res.isPendingSync;
      } finally {
        isLoadingAudio = false;
      }
    }

    setTimeout(() => {
      if (!audioEl) return;
      audioEl.play().then(() => {
        isPlaying = true;
        playbackInterval = setInterval(() => {
          if (audioEl) {
            currentTimeDisplay = formatTime(audioEl.currentTime);
            playbackProgress = (audioEl.currentTime / (audioEl.duration || currentAudioDuration)) * 100;
          }
        }, 100);
      }).catch((err) => {
        console.error('Audio playback error:', err);
        isPlaying = false;
      });
    }, 0);
  }

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
    } catch {
      // Fallback
    }
  }
</script>

{#if resolvedUrl}
  <audio
    bind:this={audioEl}
    src={resolvedUrl}
    onended={() => { isPlaying = false; playbackProgress = 0; }}
    preload="none"
  ></audio>
{/if}

<div 
  class="relative w-full [perspective:1000px] select-none group"
  style="--card-accent: {typeMeta.color}; --card-accent-sub: {typeMeta.colorSub};"
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
    
    <!-- 🌟 EXACT BACKLIGHT DIFFUSION LAYER MATCHING VOCABSEARCHSTREAM 🌟 -->
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
          
          <!-- 🌟 HOLOGRAPHIC QUANTUM LOADING STAGE 🌟 -->
          {#if isMediaLoading}
            <div 
              class="absolute inset-3.5 rounded-2xl border border-white/10 bg-black/40 backdrop-blur-xl flex flex-col items-center justify-center space-y-3 overflow-hidden shadow-inner z-20 transition-opacity duration-300"
            >
              <!-- Ambient Scanning Radar Beam -->
              <div 
                class="absolute left-0 right-0 h-[2px] opacity-80 animate-radar"
                style="background: linear-gradient(90deg, transparent 5%, var(--card-accent) 50%, transparent 95%); box-shadow: 0 0 14px var(--card-accent);"
              ></div>

              <!-- Orbiting Particle Ring -->
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

              <!-- Status Badge -->
              <div class="flex items-center gap-1.5 px-3 py-1 rounded-full bg-white/10 border border-white/10 shadow-xs backdrop-blur-md">
                <span class="w-1.5 h-1.5 rounded-full animate-ping" style="background-color: var(--card-accent);"></span>
                <span class="text-[10px] font-mono font-bold text-white/80 uppercase tracking-widest">
                  Resolving Asset...
                </span>
              </div>
            </div>
          {/if}

          <!-- Broken Link Fallback Chamber -->
          {#if hasMediaError}
            <div class="w-full h-44 rounded-2xl border border-dashed border-white/15 bg-black/40 backdrop-blur-md flex flex-col items-center justify-center space-y-1.5 text-neutral-400">
              <ImageOff size={22} class="opacity-60" />
              <span class="text-[10px] font-mono font-bold tracking-tight text-white/50">Media Unavailable</span>
            </div>
          {:else}
            <img 
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

          <!-- BOTH TEXT LINES DISPLAY SYNCHRONIZED TONE CHROMA -->
          <div class="text-3xl sm:text-4xl font-black tracking-tight leading-none drop-shadow-xs">
            <ColoredText tokens={vocabTokens.primaryTokens} fallbackClass="text-[var(--text-primary)]" />
          </div>

          {#if item.pronunciation}
            <div class="text-xs sm:text-sm font-mono font-bold tracking-wide">
              <ColoredText tokens={vocabTokens.secondaryTokens} fallbackClass="text-[var(--text-muted)]" />
            </div>
          {/if}
        </div>

        <!-- ACCORDION DRAWER -->
        <div 
          class="grid transition-[grid-template-rows,opacity] duration-300 ease-[cubic-bezier(0.16,1,0.3,1)] {isExpanded ? 'grid-rows-[1fr] opacity-100' : 'grid-rows-[0fr] opacity-0 pointer-events-none'}"
        >
          <div class="overflow-hidden min-h-0">
            <div class="pt-3 border-t border-[var(--border-subtle)] space-y-3">
              <div class="p-3.5 rounded-2xl bg-[var(--bg-base)]/80 border border-[var(--border-subtle)] space-y-3 shadow-inner">
                <div class="flex items-center justify-between gap-3">
                  <div class="flex items-center gap-2">
                    {#if isRecording}
                      <span class="w-2 h-2 rounded-full bg-rose-500 animate-ping"></span>
                      <span class="text-xs font-mono font-black text-rose-400">
                        REC {formatTime(elapsedSec)}
                      </span>
                    {:else if currentAudioDuration > 0}
                      <button
                        type="button"
                        onclick={togglePlayback}
                        disabled={isLoadingAudio}
                        class="flex items-center justify-center w-8 h-8 rounded-xl bg-[var(--bg-surface)] hover:bg-[var(--bg-surface-elevated)] border border-[var(--border-subtle)] text-[var(--text-primary)] transition-transform active:scale-90 disabled:opacity-50 cursor-pointer shadow-xs"
                      >
                        {#if isLoadingAudio}
                          <Sparkles size={14} class="animate-spin text-amber-400" />
                        {:else if isPlaying}
                          <Pause size={14} strokeWidth={2.8} />
                        {:else}
                          <Play size={14} strokeWidth={2.8} class="ml-0.5" />
                        {/if}
                      </button>

                      <div class="space-y-0.5">
                        <span class="text-xs font-mono font-bold text-[var(--text-primary)] block">
                          {isPlaying ? currentTimeDisplay : formatTime(currentAudioDuration)}
                        </span>
                        {#if isPendingSync}
                          <span class="text-[9px] font-mono text-amber-400 flex items-center gap-1">
                            <CloudUpload size={10} /> Syncing
                          </span>
                        {/if}
                      </div>
                    {:else}
                      <span class="text-xs font-mono text-[var(--text-muted)] italic">
                        Ready to record
                      </span>
                    {/if}
                  </div>

                  <button
                    type="button"
                    onclick={toggleRecord}
                    class="flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-xs font-bold text-white transition-all active:scale-90 cursor-pointer shadow-md {isRecording 
                      ? 'bg-rose-500 hover:bg-rose-600 ring-2 ring-rose-400/30' 
                      : 'bg-[var(--bg-surface)] hover:bg-[var(--bg-surface-elevated)] text-[var(--text-primary)] border border-[var(--border-subtle)]'}"
                  >
                    {#if isRecording}
                      <Square size={12} fill="currentColor" />
                      <span>Stop</span>
                    {:else}
                      <Mic size={13} style="color: var(--card-accent);" />
                      <span>{currentAudioDuration > 0 ? 'Re-record' : 'Record'}</span>
                    {/if}
                  </button>
                </div>

                {#if currentAudioDuration > 0 && !isRecording}
                  <div class="w-full h-1.5 rounded-full bg-[var(--bg-surface)] overflow-hidden relative border border-[var(--border-subtle)]">
                    <div 
                      class="h-full rounded-full transition-all duration-150"
                      style="width: {playbackProgress}%; background: linear-gradient(90deg, var(--card-accent), var(--card-accent-sub));"
                    ></div>
                  </div>
                {/if}
              </div>
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
            <span>{currentAudioDuration > 0 ? `${Math.round(currentAudioDuration)}s recorded` : 'Practice pronunciation'}</span>
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