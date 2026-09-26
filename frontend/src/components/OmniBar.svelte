<!-- frontend/src/components/OmniBar.svelte -->
<script>
  import { onMount, onDestroy } from 'svelte';
  import { vocabIndexStore } from '../lib/stores/vocabIndex.svelte.js';
  import { listeningIndexStore } from '../lib/stores/listeningIndex.svelte.js';
  import { VideoTimerService } from '../lib/services/videoTimerService.js';
  import { canonicalizeVideoUrl } from '../lib/mediaResolver.js';
  import { fetchYouTubeDuration } from '../lib/services/youtubeDurationFetcher.js';
  import { getAllAdaptiveGoals } from '../lib/services/momentumEngine.js';

  // Razor-sharp vector icons
  import { 
    MessageSquare, 
    Play, 
    Headphones, 
    BookOpen, 
    RotateCcw, 
    Plus, 
    Edit3,
    CornerDownLeft,
    Film,
    ChevronDown,
    Sparkles
  } from '@lucide/svelte';

  let {
    words = [],
    ciActivities = [],
    listeningActivities = [],
    grammarActivities = [],
    activeDate = '',
    colors = {},
    goals = {},
    onAddWord,
    onUpdateWord,
    onAddCI,
    onUpdateCI,
    onAddListening,
    onUpdateListening,
    onAddGrammar,
    onUpdateGrammar
  } = $props();

  // 100% Localized, Sealed State
  let activeTab = $state('vocab');
  let isEditMode = $state(false);
  let selectedIndex = $state(1);
  let statusMessage = $state('');
  let isSubmitting = $state(false);

  // Scroll Compact Mode
  let isScrolledPast = $state(false);
  let isManuallyOpened = $state(false);
  let barContainerEl = $state(null);
  let lastScrollPos = 0;

  // Specular sheen pointer state
  let mouseX = $state(50);
  let mouseY = $state(0);
  let isHovered = $state(false);

  let isCompact = $derived(isScrolledPast && !isManuallyOpened);

  // 🌟 Dynamic Targets Computed via momentumEngine 🌟
  let dynamicGoals = $derived.by(() => {
    return getAllAdaptiveGoals();
  });

  // --- 1. VOCAB STATES ---
  let vLink = $state('');
  let vNative = $state('');
  let vPron = $state('');
  let isPronManuallyEdited = $state(false);
  let vLinkEl = $state(null);
  let vNativeEl = $state(null);
  let vPronEl = $state(null);

  // --- 2. CI STATES ---
  let ciLink = $state('');
  let ciDuration = $state('');
  let ciLinkEl = $state(null);
  let ciDurationEl = $state(null);

  // --- 3. LISTENING STATES ---
  let listLink = $state('');
  let listDuration = $state('');
  let listLinkEl = $state(null);
  let listDurationEl = $state(null);

  // --- 4. GRAMMAR STATES ---
  let gTitle = $state('');
  let gPron = $state('');
  let gStructure = $state('');
  let gMeaning = $state('');
  let gLink = $state('');
  let gTitleEl = $state(null);
  let gPronEl = $state(null);
  let gStructureEl = $state(null);
  let gMeaningEl = $state(null);
  let gLinkEl = $state(null);

  // Debounced Duplicate State
  let vocabDuplicates = $state([]);
  let listeningDuplicates = $state([]);
  let vocabDebounceTimer = null;
  let listeningDebounceTimer = null;
  let isFetchingCIDuration = $state(false);
  let isFetchingListDuration = $state(false);
  let ciFetchDebounce = null;
  let listFetchDebounce = null;

  onDestroy(() => {
    if (vocabDebounceTimer) clearTimeout(vocabDebounceTimer);
    if (listeningDebounceTimer) clearTimeout(listeningDebounceTimer);
  });

  const CATEGORIES = [
    { id: 'vocab', label: 'Vocab', fullLabel: 'Vocab', keyNum: '1', icon: MessageSquare },
    { id: 'ci', label: 'CI', fullLabel: 'CI Video', keyNum: '2', icon: Play },
    { id: 'listening', label: 'Audio', fullLabel: 'Listening', keyNum: '3', icon: Headphones },
    { id: 'grammar', label: 'Grammar', fullLabel: 'Grammar', keyNum: '4', icon: BookOpen }
  ];

  let activeColor = $derived.by(() => {
    if (activeTab === 'vocab') return colors.vocab?.dark_primary || colors.vocab?.primary || '#10b981';
    if (activeTab === 'ci') return colors.ci?.dark_primary || colors.ci?.primary || '#a855f7';
    if (activeTab === 'listening') return colors.listening?.dark_primary || colors.listening?.primary || '#f97316';
    return colors.grammar?.dark_primary || colors.grammar?.primary || '#0ea5e9';
  });

  let activeColorSecondary = $derived.by(() => {
    if (activeTab === 'vocab') return colors.vocab?.light_primary || '#34d399';
    if (activeTab === 'ci') return colors.ci?.light_primary || '#c084fc';
    if (activeTab === 'listening') return colors.listening?.light_primary || '#fb923c';
    return colors.grammar?.light_primary || '#38bdf8';
  });

  let currentList = $derived.by(() => {
    if (activeTab === 'vocab') return words;
    if (activeTab === 'ci') return ciActivities;
    if (activeTab === 'listening') return listeningActivities;
    return grammarActivities;
  });

  let hudStats = $derived.by(() => {
    if (activeTab === 'vocab') {
      const target = dynamicGoals.vocab?.target || goals.vocab || 10;
      const count = words.length;
      const pct = target > 0 ? Math.min(100, Math.round((count / target) * 100)) : 0;
      return { count: `${count}/${target}`, pct, label: 'words' };
    }
    if (activeTab === 'ci') {
      const target = goals.ci || 1;
      const count = ciActivities.length;
      const pct = target > 0 ? Math.min(100, Math.round((count / target) * 100)) : 0;
      return { count: `${count}/${target}`, pct, label: 'vids' };
    }
    if (activeTab === 'listening') {
      const targetMins = dynamicGoals.listening?.target || goals.listening_minutes || goals.listening || 45;
      const totalSec = listeningActivities.reduce((acc, it) => acc + (it.link_duration || it.durationSec || 0), 0);
      const curMins = Math.floor(totalSec / 60);
      const pct = targetMins > 0 ? Math.min(100, Math.round((curMins / targetMins) * 100)) : 0;
      return { count: `${curMins}m/${targetMins}m`, pct, label: 'audio' };
    }
    const target = goals.grammar || 1;
    const count = grammarActivities.length;
    const pct = target > 0 ? Math.min(100, Math.round((count / target) * 100)) : 0;
    return { count: `${count}/${target}`, pct, label: 'pts' };
  });

  let activeMediaPreview = $derived.by(() => {
    if (activeTab === 'vocab' && vLink.trim()) return vLink.trim();
    return null;
  });

  function triggerVocabDuplicateCheck(val) {
    if (vocabDebounceTimer) clearTimeout(vocabDebounceTimer);
    const q = val.trim();
    if (!q || activeTab !== 'vocab') {
      vocabDuplicates = [];
      return;
    }
    vocabDebounceTimer = setTimeout(() => {
      const matches = vocabIndexStore.entries.filter((entry) => {
        if (isEditMode) {
          const curWord = words.find((w) => (w.word_index ?? w.id) === selectedIndex);
          if (curWord && curWord.native_script === q && entry.date === activeDate) return false;
        }
        return entry.native_script === q && entry.date !== activeDate;
      });
      vocabDuplicates = matches;
    }, 150);
  }

  function triggerListeningDuplicateCheck(val) {
    if (listeningDebounceTimer) clearTimeout(listeningDebounceTimer);
    const raw = val.trim();
    if (!raw || activeTab !== 'listening') {
      listeningDuplicates = [];
      return;
    }
    listeningDebounceTimer = setTimeout(() => {
      if (isEditMode) {
        const cur = listeningActivities.find((a) => a.item_index === selectedIndex);
        if (cur && canonicalizeVideoUrl(cur.link) === canonicalizeVideoUrl(raw)) {
          listeningDuplicates = [];
          return;
        }
      }
      listeningDuplicates = listeningIndexStore.findMatches(raw, activeDate) || [];
    }, 150);
  }

  onMount(() => {
    const scrollParent = barContainerEl?.closest('main') || window;

    const onScroll = () => {
      const currentPos = scrollParent === window ? window.scrollY : scrollParent.scrollTop;
      isScrolledPast = currentPos > 70;
      if (currentPos <= 30) {
        isManuallyOpened = false;
      }
      const diff = Math.abs(currentPos - lastScrollPos);
      if (isScrolledPast && isManuallyOpened && diff > 40) {
        isManuallyOpened = false;
      }
      lastScrollPos = currentPos;
    };

    scrollParent.addEventListener('scroll', onScroll, { passive: true });
    return () => scrollParent.removeEventListener('scroll', onScroll);
  });

  function handleMouseMove(e) {
    if (!barContainerEl) return;
    const rect = barContainerEl.getBoundingClientRect();
    mouseX = ((e.clientX - rect.left) / rect.width) * 100;
    mouseY = ((e.clientY - rect.top) / rect.height) * 100;
  }

  function handleNativeInput(e) {
    vNative = e.target.value;
    triggerVocabDuplicateCheck(vNative);
    if (!vNative.trim()) {
      vPron = '';
      isPronManuallyEdited = false;
      return;
    }
    if (!isPronManuallyEdited) {
      vPron = vocabIndexStore.predictPronunciation(vNative) || '';
    }
  }

  let isFetchingDuration = $state(false);

  async function handleCIUrlInput(e) {
    ciLink = e.target.value;
    
    // 1. Instant check for embedded timestamps (?t=...)
    const fallback = VideoTimerService.handleUrlInput(ciLink, ciDuration);
    if (fallback.suggestedDuration) {
      ciDuration = fallback.suggestedDuration;
    }

    // 2. Fetch the REAL YouTube video length from the headless player
    if (ciLink.includes('youtu')) {
      isFetchingDuration = true;
      try {
        const meta = await fetchYouTubeDuration(ciLink);
        if (meta && meta.formatted) {
          ciDuration = meta.formatted; 
        }
      } finally {
        isFetchingDuration = false;
      }
    }
  }

  async function handleListeningInput(e) {
    listLink = e.target.value;
    triggerListeningDuplicateCheck(listLink);

    // 1. Instant check for embedded timestamps (?t=...)
    const fallback = VideoTimerService.handleUrlInput(listLink, listDuration);
    if (fallback.suggestedDuration) {
      listDuration = fallback.suggestedDuration;
    }

    // 2. Fetch the REAL YouTube video length from the headless player
    if (listLink.includes('youtu')) {
      isFetchingDuration = true;
      try {
        const meta = await fetchYouTubeDuration(listLink);
        if (meta && meta.formatted) {
          listDuration = meta.formatted; 
        }
      } finally {
        isFetchingDuration = false;
      }
    }
  }

  function resetToAutoPronunciation() {
    isPronManuallyEdited = false;
    vPron = vocabIndexStore.predictPronunciation(vNative) || '';
  }

  function selectItemForEdit(idx) {
    selectedIndex = idx;
    if (activeTab === 'vocab') {
      const w = words.find((x) => (x.word_index ?? x.id) === idx);
      if (w) {
        vLink = w.link || '';
        vNative = w.native_script || '';
        vPron = w.pronunciation || '';
        isPronManuallyEdited = true;
        triggerVocabDuplicateCheck(vNative);
      }
    } else if (activeTab === 'ci') {
      const c = ciActivities.find((x) => x.item_index === idx);
      if (c) {
        ciLink = c.link || '';
        const sec = c.link_duration ?? c.durationSec ?? c.duration ?? 0;
        ciDuration = sec > 0 ? VideoTimerService.formatDuration(sec) : '';
      }
    } else if (activeTab === 'listening') {
      const l = listeningActivities.find((x) => x.item_index === idx);
      if (l) {
        listLink = l.link || '';
        const sec = l.link_duration ?? l.durationSec ?? l.duration ?? 0;
        listDuration = sec > 0 ? VideoTimerService.formatDuration(sec) : '';
        triggerListeningDuplicateCheck(listLink);
      }
    } else {
      const g = grammarActivities.find((x) => x.item_index === idx);
      if (g) {
        const meta = g.metadata || {};
        gTitle = meta.title || '';
        gPron = meta.pronunciation || '';
        gStructure = meta.structure || '';
        gMeaning = meta.meaning || '';
        gLink = g.link || '';
      }
    }
  }

  function switchTab(newTab) {
    if (activeTab === newTab && isScrolledPast) {
      isManuallyOpened = !isManuallyOpened;
      return;
    }
    activeTab = newTab;
    isEditMode = false;
    if (isScrolledPast) {
      isManuallyOpened = true;
    }
  }

  function toggleEditMode() {
    isEditMode = !isEditMode;
    if (isEditMode && currentList.length > 0) {
      const firstItem = currentList[0];
      const idx = firstItem.word_index ?? firstItem.item_index ?? firstItem.id ?? 1;
      selectItemForEdit(idx);
    } else {
      clearInputs();
    }
  }

  function clearInputs() {
    vLink = '';
    vNative = '';
    vPron = '';
    isPronManuallyEdited = false;
    ciLink = '';
    ciDuration = '';
    listLink = '';
    listDuration = '';
    gTitle = '';
    gPron = '';
    gStructure = '';
    gMeaning = '';
    gLink = '';
    vocabDuplicates = [];
    listeningDuplicates = [];
  }

  async function handleFormSubmit() {
    isSubmitting = true;
    try {
      if (activeTab === 'vocab') {
        const cleanNative = vNative.trim();
        const cleanPron = vPron.trim();
        const cleanLink = vLink.trim();
        if (!cleanNative && !cleanPron && !cleanLink) {
          statusMessage = '⚠️ Enter word details';
          return;
        }
        const payload = { native_script: cleanNative, pronunciation: cleanPron, link: cleanLink || null };
        if (isEditMode) {
          if (onUpdateWord) await onUpdateWord(selectedIndex, payload);
          statusMessage = `🔄 Updated #${selectedIndex}!`;
        } else {
          if (onAddWord) await onAddWord(payload);
          statusMessage = `✅ Added #${words.length + 1}!`;
          clearInputs();
          vLinkEl?.focus();
        }
      } else if (activeTab === 'ci') {
        const cleanUrl = canonicalizeVideoUrl(ciLink.trim());
        if (!cleanUrl) {
          statusMessage = '⚠️ Enter video URL';
          return;
        }
        const payload = VideoTimerService.createActivityPayload({
          link: cleanUrl,
          durationInput: ciDuration
        });

        if (isEditMode) {
          if (onUpdateCI) await onUpdateCI(selectedIndex, payload);
          statusMessage = `🔄 Updated #${selectedIndex}!`;
        } else {
          if (onAddCI) await onAddCI(payload);
          statusMessage = `✅ Added #${ciActivities.length + 1}!`;
          clearInputs();
          ciLinkEl?.focus();
        }
      } else if (activeTab === 'listening') {
        const cleanUrl = canonicalizeVideoUrl(listLink.trim());
        const durationSec = VideoTimerService.parseDuration(listDuration);
        if (!cleanUrl && durationSec <= 0) {
          statusMessage = '⚠️ Enter link or minutes';
          return;
        }
        const payload = VideoTimerService.createActivityPayload({
          link: cleanUrl,
          durationInput: listDuration
        });

        if (isEditMode) {
          if (onUpdateListening) await onUpdateListening(selectedIndex, payload);
          statusMessage = `🔄 Updated #${selectedIndex}!`;
        } else {
          if (onAddListening) await onAddListening(payload);
          statusMessage = `✅ Added #${listeningActivities.length + 1}!`;
          clearInputs();
          listLinkEl?.focus();
        }
      } else if (activeTab === 'grammar') {
        const cleanTitle = gTitle.trim();
        const cleanLink = gLink.trim();
        if (!cleanTitle && !cleanLink) {
          statusMessage = '⚠️ Enter grammar title';
          return;
        }
        const payload = {
          title: cleanTitle,
          pronunciation: gPron.trim(),
          structure: gStructure.trim(),
          meaning: gMeaning.trim(),
          link: cleanLink || null
        };
        if (isEditMode) {
          if (onUpdateGrammar) await onUpdateGrammar(selectedIndex, payload);
          statusMessage = `🔄 Updated #${selectedIndex}!`;
        } else {
          if (onAddGrammar) await onAddGrammar(payload);
          statusMessage = `✅ Added #${grammarActivities.length + 1}!`;
          clearInputs();
          gTitleEl?.focus();
        }
      }

      if (isScrolledPast) {
        setTimeout(() => {
          isManuallyOpened = false;
        }, 1200);
      }
    } catch (err) {
      console.error('Failed to submit OmniBar item:', err);
      statusMessage = '❌ Error saving';
    } finally {
      isSubmitting = false;
      setTimeout(() => (statusMessage = ''), 2500);
    }
  }

  function handleKeydown(e, nextEl) {
    if (e.key === 'Enter') {
      e.preventDefault();
      if (nextEl) {
        nextEl.focus();
      } else {
        handleFormSubmit();
      }
    }
  }

  function handleWindowKeydown(e) {
    if (['INPUT', 'TEXTAREA'].includes(document.activeElement?.tagName)) return;
    if (e.key === '1') switchTab('vocab');
    if (e.key === '2') switchTab('ci');
    if (e.key === '3') switchTab('listening');
    if (e.key === '4') switchTab('grammar');
  }

  async function checkAndAutoFillCIDuration(url) {
    if (!url || !url.includes('youtu')) return;
    
    if (ciFetchDebounce) clearTimeout(ciFetchDebounce);
    ciFetchDebounce = setTimeout(async () => {
      isFetchingCIDuration = true;
      try {
        const result = await fetchYouTubeDuration(url);
        if (result?.formatted) {
          ciDuration = result.formatted;
        }
      } catch (e) {
        console.warn('Failed to resolve video length:', e);
      } finally {
        isFetchingCIDuration = false;
      }
    }, 100);
  }

  async function checkAndAutoFillListDuration(url) {
    if (!url || !url.includes('youtu')) return;
    
    if (listFetchDebounce) clearTimeout(listFetchDebounce);
    listFetchDebounce = setTimeout(async () => {
      isFetchingListDuration = true;
      try {
        const result = await fetchYouTubeDuration(url);
        if (result?.formatted) {
          listDuration = result.formatted;
        }
      } catch (e) {
        console.warn('Failed to resolve audio length:', e);
      } finally {
        isFetchingListDuration = false;
      }
    }, 100);
  }

  const inputClass = "w-full py-2 px-3.5 rounded-xl sm:rounded-2xl text-xs sm:text-sm font-semibold bg-white/70 dark:bg-white/[0.06] border border-black/[0.08] dark:border-white/[0.14] text-neutral-900 dark:text-white placeholder-neutral-400 dark:placeholder-white/35 outline-none focus:outline-none focus:ring-2 focus:ring-[var(--omni-color)]/25 focus:border-[var(--omni-color)] transition-all shadow-[0_2px_8px_-2px_rgba(0,0,0,0.04)] dark:shadow-[0_2px_8px_-2px_rgba(0,0,0,0.3)] box-border min-w-0";
</script>

<svelte:window onkeydown={handleWindowKeydown} />

<!-- DYNAMIC HEIGHT ENVELOPE DOCK -->
<div 
  bind:this={barContainerEl}
  role="presentation"
  onmousemove={handleMouseMove}
  onmouseenter={() => (isHovered = true)}
  onmouseleave={() => (isHovered = false)}
  class="w-full max-w-full box-border transition-all duration-200 {isCompact 
    ? 'min-h-[38px] sm:min-h-[40px]' 
    : 'min-h-[200px] sm:min-h-[185px]'}"
  style="--omni-color: {activeColor}; --omni-color-sub: {activeColorSecondary};"
>
  <!-- APPLE VISIONOS / LIQUID GLASS CAPSULE -->
  <div 
    class="relative w-full max-w-full box-border rounded-2xl sm:rounded-3xl border border-black/10 dark:border-white/15 bg-white/60 dark:bg-[#12131a]/65 backdrop-blur-2xl backdrop-saturate-[180%] shadow-[0_20px_50px_-12px_rgba(0,0,0,0.18),inset_0_1px_1px_rgba(255,255,255,0.6)] dark:shadow-[0_24px_50px_-12px_rgba(0,0,0,0.7),inset_0_1px_1px_rgba(255,255,255,0.18)] select-none overflow-hidden transition-transform duration-100 hover:-translate-y-0.5 will-change-transform"
  >
    <!-- Dynamic Cursor Glare Sheen -->
    <div 
      class="pointer-events-none absolute inset-0 opacity-0 transition-opacity duration-200 -z-0 {isHovered ? 'opacity-100' : ''}"
      style="background: radial-gradient(circle 350px at {mouseX}% {mouseY}%, rgba(255,255,255,0.14), transparent 70%);"
    ></div>

    <!-- Active Accent Neon Top Highlight Lip -->
    <div
      class="absolute top-0 left-0 right-0 h-[2px] opacity-90 transition-all duration-300 pointer-events-none"
      style="background: linear-gradient(90deg, transparent 5%, var(--omni-color) 30%, var(--omni-color-sub) 70%, transparent 95%);"
    ></div>

    <div class="p-1 sm:p-1.5 w-full box-border relative z-10">
      <!-- ROW 1: ULTRA-COMPACT LIQUID PEDALS & HUD -->
      <div class="flex items-center justify-between gap-1 sm:gap-2 w-full min-w-0">
        <!-- Segmented Tab Group -->
        <div class="flex items-center rounded-xl sm:rounded-2xl bg-white/50 dark:bg-white/[0.05] p-0.5 sm:p-1 border border-black/[0.06] dark:border-white/[0.08] shadow-[inset_0_1px_2px_rgba(0,0,0,0.03)] shrink min-w-0">
          {#each CATEGORIES as cat}
            {@const IconComp = cat.icon}
            {@const isActive = activeTab === cat.id}
            <button
              type="button"
              onclick={() => switchTab(cat.id)}
              class="group relative flex items-center justify-center gap-1 sm:gap-1.5 px-2 sm:px-3 py-1 sm:py-1.5 rounded-lg sm:rounded-xl text-[11px] sm:text-xs font-bold transition-all duration-100 cursor-pointer outline-none active:scale-95 whitespace-nowrap min-h-[30px] sm:min-h-[34px] {isActive 
                ? 'text-white' 
                : 'text-neutral-600 dark:text-white/60 hover:text-neutral-900 dark:hover:text-white hover:bg-black/[0.03] dark:hover:bg-white/[0.06]'}"
              style={isActive ? 'background: linear-gradient(135deg, var(--omni-color), var(--omni-color-sub)); box-shadow: 0 4px 18px -2px var(--omni-color);' : ''}
            >
              <IconComp size={12} strokeWidth={2.8} class="shrink-0 drop-shadow-xs" />
              <span class="tracking-tight hidden sm:inline">{cat.fullLabel}</span>
              <span class="tracking-tight sm:hidden">{cat.label}</span>
              
              <span 
                class="hidden md:inline-flex items-center justify-center font-mono text-[9px] px-1 rounded border {isActive ? 'bg-white/20 border-white/30 text-white' : 'bg-black/[0.04] dark:bg-white/[0.06] text-neutral-500 dark:text-white/40 border-black/[0.06] dark:border-white/10'}"
              >
                {cat.keyNum}
              </span>
            </button>
          {/each}
        </div>

        <!-- Telemetry & Controls Dock -->
        <div class="flex items-center gap-1 sm:gap-1.5 shrink-0">
          {#if !isEditMode}
            <div class="flex items-center gap-1.5 sm:gap-2 px-2 sm:px-2.5 py-1 rounded-xl sm:rounded-2xl bg-white/50 dark:bg-white/[0.05] border border-black/[0.06] dark:border-white/[0.08] shadow-[inset_0_1px_2px_rgba(0,0,0,0.03)]">
              <div class="flex items-center gap-1.5">
                <span class="w-1.5 h-1.5 rounded-full shrink-0 shadow-xs" style="background-color: var(--omni-color-sub); box-shadow: 0 0 8px var(--omni-color);"></span>
                <span class="text-[10px] sm:text-[11px] font-bold font-mono text-neutral-800 dark:text-white/90">
                  {hudStats.count}
                </span>
                <span class="hidden lg:inline text-[10px] font-mono text-neutral-500 dark:text-white/50">
                  {hudStats.label}
                </span>
              </div>
              <div class="w-8 sm:w-14 h-1.5 rounded-full bg-black/[0.06] dark:bg-white/10 overflow-hidden shrink-0">
                <div
                  class="h-full rounded-full transition-all duration-300"
                  style="width: {hudStats.pct}%; background: linear-gradient(90deg, var(--omni-color), var(--omni-color-sub));"
                ></div>
              </div>
            </div>
          {:else}
            <div class="flex items-center gap-1 overflow-x-auto max-w-[130px] sm:max-w-[200px] p-0.5 rounded-xl bg-white/50 dark:bg-white/[0.05] border border-black/[0.06] dark:border-white/[0.08] shrink-0">
              {#each currentList as item (item.word_index ?? item.item_index ?? item.id)}
                {@const idx = item.word_index ?? item.item_index ?? item.id}
                {@const isSelected = idx === selectedIndex}
                <button
                  type="button"
                  onclick={() => selectItemForEdit(idx)}
                  class="px-1.5 py-0.5 rounded-lg text-[9px] sm:text-[10px] font-bold font-mono transition-colors duration-75 cursor-pointer shrink-0 {isSelected
                    ? 'text-white shadow-xs'
                    : 'text-neutral-500 dark:text-white/50 hover:text-neutral-900 dark:hover:text-white'}"
                  style={isSelected ? 'background-color: var(--omni-color);' : ''}
                >
                  #{idx}
                </button>
              {/each}
            </div>
          {/if}

          {#if isScrolledPast}
            <button
              type="button"
              onclick={() => (isManuallyOpened = !isManuallyOpened)}
              class="w-7 h-7 sm:w-8 sm:h-8 rounded-xl bg-white/60 dark:bg-white/10 hover:bg-white dark:hover:bg-white/20 border border-black/[0.06] dark:border-white/10 flex items-center justify-center text-neutral-700 dark:text-white/80 hover:text-neutral-900 dark:hover:text-white transition-all cursor-pointer active:scale-90 shadow-2xs"
              title="Toggle Omnibar"
            >
              <ChevronDown size={14} class="transition-transform duration-200 {isManuallyOpened ? 'rotate-180' : ''}" />
            </button>
          {/if}
        </div>
      </div>

      <!-- FORM CHAMBERS -->
      <div 
        class="grid transition-[grid-template-rows,opacity,margin] duration-150 ease-out {!isCompact 
          ? 'grid-rows-[1fr] opacity-100 mt-2' 
          : 'grid-rows-[0fr] opacity-0 pointer-events-none mt-0'}"
      >
        <div class="overflow-hidden min-h-0">
          <div class="space-y-2 pt-1 pb-1 box-border">
            <div class="w-full relative z-10 box-border">
              
              <!-- 1. VOCABULARY MODE INPUTS -->
              <div class="grid grid-cols-1 md:grid-cols-2 gap-2 w-full box-border {activeTab === 'vocab' ? '' : 'hidden'}">
                <div class="md:col-span-2 relative flex items-center group w-full min-w-0">
                  {#if activeMediaPreview}
                    <div class="absolute left-2.5 w-6 h-6 rounded-lg overflow-hidden border border-black/10 dark:border-white/20 bg-white dark:bg-black/60 shrink-0 shadow-xs z-10">
                      <img src={activeMediaPreview} alt="" class="w-full h-full object-cover" />
                    </div>
                  {/if}
                  <input
                    bind:this={vLinkEl}
                    bind:value={vLink}
                    onkeydown={(e) => handleKeydown(e, vNativeEl)}
                    type="text"
                    placeholder="1. Media URL (Direct Image, GIF, WebP)..."
                    class="{inputClass} {activeMediaPreview ? 'pl-11' : 'pl-3.5'}"
                  />
                </div>

                <div class="relative flex items-center group w-full min-w-0">
                  <input
                    bind:this={vNativeEl}
                    value={vNative}
                    oninput={handleNativeInput}
                    onkeydown={(e) => handleKeydown(e, vPronEl)}
                    type="text"
                    placeholder="2. Native script (汉语, 苹果)..."
                    class={inputClass}
                  />

                  {#if vocabDuplicates.length > 0}
                    <span
                      title="Logged on {vocabDuplicates.map((m) => m.date).join(', ')}"
                      class="absolute right-2 text-[9px] font-bold font-mono px-1.5 py-0.5 rounded-md bg-amber-500/20 text-amber-600 dark:text-amber-300 border border-amber-500/30 whitespace-nowrap pointer-events-none shadow-2xs"
                    >
                      ⚠️ {vocabDuplicates.length === 1 ? vocabDuplicates[0].date : `${vocabDuplicates.length}x`}
                    </span>
                  {/if}
                </div>

                <div class="relative flex items-center group w-full min-w-0">
                  <input
                    bind:this={vPronEl}
                    value={vPron}
                    oninput={(e) => { vPron = e.target.value; isPronManuallyEdited = true; }}
                    onkeydown={(e) => handleKeydown(e, null)}
                    type="text"
                    placeholder="3. Pronunciation (hàn yǔ)..."
                    class="{inputClass} pr-9 font-mono"
                  />

                  {#if isPronManuallyEdited && vNative}
                    <button
                      type="button"
                      onclick={resetToAutoPronunciation}
                      title="Reset auto pronunciation"
                      class="absolute right-2 p-1 rounded-md text-neutral-500 dark:text-white/50 hover:text-neutral-900 dark:hover:text-white bg-black/[0.04] dark:bg-white/10 transition-colors cursor-pointer border border-black/[0.08] dark:border-white/10"
                    >
                      <RotateCcw size={11} />
                    </button>
                  {/if}
                </div>
              </div>

              <!-- 2. CI VIDEO MODE INPUTS -->
              <div class="grid grid-cols-1 md:grid-cols-3 gap-2 w-full box-border {activeTab === 'ci' ? '' : 'hidden'}">
                <div class="md:col-span-2 relative flex items-center w-full min-w-0">
                  <Film size={14} class="absolute left-3 text-neutral-400 dark:text-white/40 pointer-events-none" />
                  <input
                    bind:this={ciLinkEl}
                    bind:value={ciLink}
                    oninput={(e) => checkAndAutoFillCIDuration(e.target.value)}
                    onpaste={(e) => {
                      const pasted = e.clipboardData?.getData('text') || '';
                      checkAndAutoFillCIDuration(pasted);
                    }}
                    onkeydown={(e) => handleKeydown(e, ciDurationEl)}
                    type="text"
                    placeholder="1. Video URL (https://youtu.be/...)"
                    class="{inputClass} pl-9"
                  />
                </div>

                <div class="relative w-full min-w-0">
                  <input
                    bind:this={ciDurationEl}
                    bind:value={ciDuration}
                    onkeydown={(e) => handleKeydown(e, null)}
                    type="text"
                    placeholder={isFetchingCIDuration ? "Fetching duration..." : "2. Duration (14:20 or mm:ss)..."}
                    class="{inputClass} font-mono {isFetchingCIDuration ? 'animate-pulse text-amber-500' : ''}"
                  />
                </div>
              </div>

              <!-- 3. LISTENING IMMERSION MODE INPUTS -->
              <div class="grid grid-cols-1 md:grid-cols-3 gap-2 w-full box-border {activeTab === 'listening' ? '' : 'hidden'}">
                <div class="md:col-span-2 relative flex items-center w-full min-w-0">
                  <Headphones size={14} class="absolute left-3 text-neutral-400 dark:text-white/40 pointer-events-none" />
                  <input
                    bind:this={listLinkEl}
                    bind:value={listLink}
                    oninput={(e) => {
                      handleListeningInput(e);
                      checkAndAutoFillListDuration(e.target.value);
                    }}
                    onpaste={(e) => {
                      const pasted = e.clipboardData?.getData('text') || '';
                      checkAndAutoFillListDuration(pasted);
                    }}
                    onkeydown={(e) => handleKeydown(e, listDurationEl)}
                    type="text"
                    placeholder="1. Podcast or Audio URL..."
                    class="{inputClass} pl-9 pr-16"
                  />

                  {#if listeningDuplicates.length > 0}
                    <span
                      title="Logged on {listeningDuplicates.map((m) => m.date).join(', ')}"
                      class="absolute right-2 text-[9px] font-bold font-mono px-1.5 py-0.5 rounded-md bg-amber-500/20 text-amber-600 dark:text-amber-300 border border-amber-500/30 whitespace-nowrap pointer-events-none shadow-2xs"
                    >
                      ⚠️ {listeningDuplicates.length}x
                    </span>
                  {/if}
                </div>

                <div class="relative w-full min-w-0">
                  <input
                    bind:this={listDurationEl}
                    bind:value={listDuration}
                    onkeydown={(e) => handleKeydown(e, null)}
                    type="text"
                    placeholder={isFetchingListDuration ? "Fetching duration..." : "2. Minutes (20m, 15:30)..."}
                    class="{inputClass} font-mono {isFetchingListDuration ? 'animate-pulse text-amber-500' : ''}"
                  />
                </div>
              </div>

              <!-- 4. GRAMMAR MODE INPUTS -->
              <div class="grid grid-cols-1 md:grid-cols-2 gap-2 w-full box-border {activeTab === 'grammar' ? '' : 'hidden'}">
                <div class="md:col-span-2 w-full min-w-0">
                  <input
                    bind:this={gTitleEl}
                    bind:value={gTitle}
                    onkeydown={(e) => handleKeydown(e, gPronEl)}
                    type="text"
                    placeholder="1. Grammar Point (e.g. 把字句)..."
                    class={inputClass}
                  />
                </div>

                <div class="w-full min-w-0">
                  <input
                    bind:this={gPronEl}
                    bind:value={gPron}
                    onkeydown={(e) => handleKeydown(e, gStructureEl)}
                    type="text"
                    placeholder="2. Reading (bǎ zìjù)..."
                    class="{inputClass} font-mono"
                  />
                </div>

                <div class="w-full min-w-0">
                  <input
                    bind:this={gStructureEl}
                    bind:value={gStructure}
                    onkeydown={(e) => handleKeydown(e, gMeaningEl)}
                    type="text"
                    placeholder="3. Formula (Subj + 把 + Obj + Verb)..."
                    class={inputClass}
                  />
                </div>

                <div class="md:col-span-2 w-full min-w-0">
                  <input
                    bind:this={gMeaningEl}
                    bind:value={gMeaning}
                    onkeydown={(e) => handleKeydown(e, gLinkEl)}
                    type="text"
                    placeholder="4. Meaning / Usage explanation..."
                    class={inputClass}
                  />
                </div>

                <div class="md:col-span-2 w-full min-w-0">
                  <input
                    bind:this={gLinkEl}
                    bind:value={gLink}
                    onkeydown={(e) => handleKeydown(e, null)}
                    type="text"
                    placeholder="5. Reference link / Diagram (optional)..."
                    class={inputClass}
                  />
                </div>
              </div>

            </div>

            <!-- BOTTOM CONTROLS & SUBMIT -->
            <div class="flex items-center justify-between gap-2 pt-2 pb-2 border-t border-black/[0.06] dark:border-white/[0.08] relative z-10 w-full min-w-0 box-border">
              <div class="flex items-center gap-2 flex-wrap min-w-0 py-1">
                <button
                  type="button"
                  onclick={handleFormSubmit}
                  disabled={isSubmitting}
                  class="inline-flex items-center justify-center gap-1.5 px-3.5 py-1.5 sm:py-2 rounded-xl sm:rounded-2xl text-xs font-bold text-white shadow-lg active:scale-95 transition-all duration-75 cursor-pointer disabled:opacity-50"
                  style="background: linear-gradient(135deg, var(--omni-color), var(--omni-color-sub)); box-shadow: 0 4px 14px -2px var(--omni-color);"
                >
                  <Plus size={13} strokeWidth={2.8} />
                  <span>{isEditMode ? `Update #${selectedIndex}` : `Add ${CATEGORIES.find(c => c.id === activeTab).label}`}</span>
                </button>

                {#if currentList.length > 0}
                  <button
                    type="button"
                    onclick={toggleEditMode}
                    class="inline-flex items-center justify-center gap-1 px-2.5 py-1.5 sm:py-2 rounded-xl sm:rounded-2xl text-xs font-semibold bg-white/60 dark:bg-white/10 hover:bg-white dark:hover:bg-white/15 text-neutral-700 dark:text-white/80 hover:text-neutral-900 dark:hover:text-white border border-black/[0.06] dark:border-white/10 active:scale-95 transition-all duration-75 cursor-pointer shadow-2xs"
                  >
                    <Edit3 size={11} />
                    <span>{isEditMode ? 'Add' : 'Edit'}</span>
                  </button>
                {/if}

                {#if statusMessage}
                  <span class="text-xs font-mono font-bold animate-in fade-in" style="color: var(--omni-color-sub);">
                    {statusMessage}
                  </span>
                {/if}
              </div>

              <div class="hidden xl:flex items-center gap-1.5 font-mono text-[10px] text-neutral-500 dark:text-white/40 shrink-0">
                <span>Press</span>
                <kbd class="inline-flex items-center gap-1 px-1.5 py-0.5 rounded bg-white/70 dark:bg-black/40 border border-black/[0.08] dark:border-white/10 font-bold text-neutral-700 dark:text-white/70 shadow-xs">
                  <span>Enter</span>
                  <CornerDownLeft size={10} />
                </kbd>
              </div>
            </div>

          </div>
        </div>
      </div>

    </div>

  </div>
</div>