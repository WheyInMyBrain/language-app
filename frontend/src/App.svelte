<!-- frontend/src/App.svelte -->
<script>
  import { onMount, tick } from 'svelte';
  import { metadataStore } from './lib/stores/metadata.svelte.js';
  import { notificationService } from './lib/services/notificationService.js';
  import { srsStore } from './lib/stores/srs.svelte.js';
  import { vocabIndexStore } from './lib/stores/vocabIndex.svelte.js';
  import { ciIndexStore } from './lib/stores/ciIndex.svelte.js';
  import { listeningIndexStore } from './lib/stores/listeningIndex.svelte.js';
  import { activeLanguage } from './lib/stores/activeLanguage.svelte.js';

  import Header from './components/Header.svelte';
  import UploadProgressBar from './components/UploadProgressBar.svelte';
  import RightEdgeDrawer from './components/RightEdgeDrawer.svelte';
  import LanguageSelectPage from './pages/LanguageSelectPage.svelte';
  import DashboardPage from './pages/DashboardPage.svelte';
  import DayPage from './pages/DayPage.svelte';
  import QuizPage from './pages/QuizPage.svelte';
  import LibraryPage from './pages/LibraryPage.svelte';
  import SettingsPage from './pages/SettingsPage.svelte';

  import { 
    LayoutDashboard, 
    Target, 
    BookOpen, 
    Settings, 
    Globe, 
    Sparkles, 
    ChevronRight, 
    Zap,
    Flame,
    Activity,
    Compass,
    Layers,
    ArrowUpRight
  } from '@lucide/svelte';

  let activeRoute = $state('select-language');
  let selectedDate = $state(null);
  let mainEl = $state(null);
  let isDrawerOpen = $state(false);
  let lastConnectedLang = '';

  // Interactive Holographic Tilt State
  let heroTilt = $state({ x: 0, y: 0, active: false });

  let themeColor = $derived(activeLanguage.themeColor || '#a855f7');
  let activeLangConfig = $derived(activeLanguage.current || {});

  const scrollPositions = new Map();

  function getRouteKey(route, date) {
    return route === 'day' ? `day:${date}` : route;
  }

  function saveCurrentScroll() {
    if (!mainEl) return;
    const currentKey = getRouteKey(activeRoute, selectedDate);
    scrollPositions.set(currentKey, mainEl.scrollTop);
  }

  async function restoreScroll(targetRoute, targetDate) {
    await tick();
    if (!mainEl) return;
    const targetKey = getRouteKey(targetRoute, targetDate);
    const targetY = scrollPositions.get(targetKey) ?? 0;
    
    requestAnimationFrame(() => {
      if (mainEl) {
        mainEl.scrollTop = targetY;
      }
    });
  }

  $effect(() => {
    const lang = metadataStore.activeLanguage;
    if (lang && lang !== lastConnectedLang) {
      lastConnectedLang = lang;
      srsStore.connect(lang);
      vocabIndexStore.connect(lang);
      ciIndexStore.connect(lang);
      listeningIndexStore.connect(lang);
    }
  });

  async function navigateTo(route, payload = null) {
    saveCurrentScroll();

    if (route === 'dashboard' && payload) {
      metadataStore.activeLanguage = payload;
    }
    if (route === 'day' && payload) {
      selectedDate = payload;
    }

    activeRoute = route;
    isDrawerOpen = false;

    window.history.pushState(
      { route, lang: metadataStore.activeLanguage, date: selectedDate },
      '',
      `#${route}`
    );

    await restoreScroll(route, selectedDate);
  }

  function handleBack() {
    window.history.back();
  }

  function getTodayString() {
    const d = new Date();
    const year = d.getFullYear();
    const month = String(d.getMonth() + 1).padStart(2, '0');
    const day = String(d.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
  }
  const todayStr = getTodayString();

  let historyLogs = $derived.by(() => {
    const lang = metadataStore.activeLanguage;
    const cal = metadataStore.calendarIndex;
    if (!lang || !cal) return [];

    const prefix = `${lang}:`;
    const results = [];
    const entries = cal instanceof Map ? cal.entries() : Object.entries(cal);

    for (const [key, stat] of entries) {
      if (typeof key === 'string' && key.startsWith(prefix) && stat) {
        const dateStr = key.slice(prefix.length);
        results.push({
          date: dateStr,
          revision: Number(stat.revision || 0),
          words: Number(stat.word || 0),
          ci: Number(stat.ci || 0),
          listening: Number(stat.listening || 0)
        });
      }
    }
    return results.sort((a, b) => b.date.localeCompare(a.date));
  });

  let totalDueQuizCards = $derived.by(() => {
    if (!srsStore.getDueCounts) return 0;
    const counts = srsStore.getDueCounts();
    return (counts.audio || 0) + (counts.visual || 0);
  });

  let totalWordsCount = $derived((vocabIndexStore.entries || []).length);
  let streak = $derived(activeLangConfig?.current_streak || 0);

  function handleHeroMouseMove(e) {
    const rect = e.currentTarget.getBoundingClientRect();
    const cx = rect.left + rect.width / 2;
    const cy = rect.top + rect.height / 2;
    const dx = (e.clientX - cx) / (rect.width / 2);
    const dy = (e.clientY - cy) / (rect.height / 2);
    heroTilt = { x: dy * -6, y: dx * 6, active: true };
  }

  function handleHeroMouseLeave() {
    heroTilt = { x: 0, y: 0, active: false };
  }

  function handleDeepLink(pathname = window.location.pathname) {
    const logMatch = pathname.match(/^\/log\/([a-zA-Z0-9_-]+)\/(\d{4}-\d{2}-\d{2})$/);
    if (logMatch) {
      const [, langCode, targetDate] = logMatch;
      if (metadataStore.languages[langCode]) {
        metadataStore.activeLanguage = langCode;
      }
      navigateTo('day', targetDate);
      window.history.replaceState({}, '', '/');
      return;
    }

    const srsMatch = pathname.match(/^\/srs\/([a-zA-Z0-9_-]+)$/);
    if (srsMatch) {
      const [, langCode] = srsMatch;
      if (metadataStore.languages[langCode]) {
        metadataStore.activeLanguage = langCode;
      }
      navigateTo('quiz');
      window.history.replaceState({}, '', '/');
    }
  }

  onMount(() => {
    metadataStore.init();
    handleDeepLink();

    (async () => {
      await notificationService.init();
      if (notificationService.permission === 'granted') {
        notificationService.startScheduler(19);
      }
    })();

    const initialHash = window.location.hash.replace('#', '');
    if (initialHash === 'day') {
      activeRoute = 'day';
    } else if (initialHash === 'dashboard' || initialHash === 'calendar') {
      activeRoute = 'dashboard';
    } else if (initialHash === 'quiz') {
      activeRoute = 'quiz';
    } else if (initialHash === 'library') {
      activeRoute = 'library';
    } else {
      activeRoute = 'select-language';
    }

    window.history.replaceState(
      { route: activeRoute, lang: metadataStore.activeLanguage, date: selectedDate },
      '',
      `#${activeRoute}`
    );

    const onPopState = async (event) => {
      saveCurrentScroll();

      const nextRoute = event.state?.route || 'select-language';
      const nextDate = event.state?.date || selectedDate;

      activeRoute = nextRoute;
      if (event.state?.lang) metadataStore.activeLanguage = event.state.lang;
      if (event.state?.date) selectedDate = event.state.date;

      await restoreScroll(nextRoute, nextDate);
    };

    window.addEventListener('popstate', onPopState);
    return () => window.removeEventListener('popstate', onPopState);
  });
</script>

<div class="relative flex flex-col h-screen w-screen bg-[var(--bg-base)] text-[var(--text-primary)] antialiased transition-colors duration-200 overflow-hidden font-sans">
  
  <!-- Command Header -->
  <div class="z-30 shrink-0">
    <Header {handleBack} {activeRoute} />
  </div>

  {#if activeRoute === 'select-language'}
    <main class="flex-1 overflow-y-auto overscroll-none px-4 sm:px-6 lg:px-8 py-6 safe-bottom relative z-10 max-w-7xl mx-auto w-full">
      <LanguageSelectPage onSelectLanguage={(langCode) => navigateTo('dashboard', langCode)} />
    </main>
  {:else}
    <!-- Dual-Pane Master-Detail Studio Layout -->
    <div class="flex-1 flex flex-col lg:flex-row w-full h-full overflow-hidden relative z-10">
      
      <!-- LEFT COCKPIT: Dashboard (Strict Hardware Isolation) -->
      <aside 
        class="hidden lg:flex flex-col w-[40%] min-w-[340px] max-w-[620px] shrink-0 border-r border-[var(--border-subtle)] bg-[var(--bg-surface)]/80 h-full overflow-y-auto overscroll-none px-4 sm:px-6 py-6 shadow-xs box-border"
        style="contain: strict; isolation: isolate;"
      >
        <DashboardPage onSelectDate={(date) => navigateTo('day', date)} />
      </aside>

      <!-- RIGHT WORKSPACE: Live Stage -->
      <main 
        bind:this={mainEl} 
        class="flex-1 w-full min-w-0 h-full overflow-y-auto overscroll-none px-4 sm:px-6 lg:px-8 xl:px-10 py-6 safe-bottom relative box-border"
        style="isolation: isolate;"
      >
        {#if activeRoute === 'dashboard'}
          <!-- Mobile View -->
          <div class="block lg:hidden">
            <DashboardPage onSelectDate={(date) => navigateTo('day', date)} />
          </div>

          <!-- 🌟 HIGH-PERFORMANCE DYNAMIC DESKTOP LAUNCHPAD 🌟 -->
          <div class="hidden lg:flex flex-col items-center justify-center min-h-full max-w-3xl mx-auto relative perspective-1000">

            <!-- 🌟 KINETIC FLOATING PARTICLES & ORBITAL LIGHTING 🌟 -->
            <div class="pointer-events-none absolute inset-0 overflow-hidden -z-10 flex items-center justify-center">
              <!-- Radial Breathing Core -->
              <div 
                class="w-[500px] h-[500px] rounded-full blur-[110px] opacity-20 animate-pulse-slow"
                style="background: radial-gradient(circle, {themeColor} 0%, transparent 70%);"
              ></div>
              
              <!-- Orbital Rings -->
              <div class="absolute w-[440px] h-[440px] rounded-full border border-white/5 animate-spin-ultra-slow"></div>
              <div class="absolute w-[600px] h-[600px] rounded-full border border-dashed border-white/5 animate-spin-reverse"></div>

              <!-- Floating Ambient Micro-Badges -->
              <div class="absolute top-12 left-16 px-2.5 py-1 rounded-full bg-white/5 border border-white/10 backdrop-blur-md text-[10px] font-mono text-white/40 flex items-center gap-1.5 animate-float-1">
                <Flame size={11} class="text-amber-400" />
                <span>{streak}d consistency</span>
              </div>

              <div class="absolute bottom-16 right-12 px-2.5 py-1 rounded-full bg-white/5 border border-white/10 backdrop-blur-md text-[10px] font-mono text-white/40 flex items-center gap-1.5 animate-float-2">
                <Activity size={11} class="text-emerald-400" />
                <span>CRDT Matrix live</span>
              </div>
            </div>

            <!-- 🌟 TACTILE 3D HOLOGRAPHIC HERO POD 🌟 -->
            <div 
              role="presentation"
              class="w-full rounded-3xl border border-white/15 bg-white/70 dark:bg-[#0f1019]/80 backdrop-blur-2xl p-7 sm:p-9 shadow-2xl relative overflow-hidden transition-transform duration-200 ease-out"
              onmousemove={handleHeroMouseMove}
              onmouseleave={handleHeroMouseLeave}
              style="
                transform: rotateX({heroTilt.x}deg) rotateY({heroTilt.y}deg);
                box-shadow: 0 30px 60px -15px rgba(0,0,0,0.5), inset 0 1px 0 rgba(255,255,255,0.15);
              "
            >
              <!-- Glowing Top Horizon Specular Line -->
              <div 
                class="absolute top-0 left-0 right-0 h-[2.5px] overflow-hidden"
              >
                <div 
                  class="w-full h-full"
                  style="background: linear-gradient(90deg, transparent 0%, {themeColor} 40%, white 50%, {themeColor} 60%, transparent 100%);"
                ></div>
              </div>

              <div class="flex items-start justify-between gap-4 mb-7 relative z-10">
                <div class="space-y-1.5">
                  <div class="inline-flex items-center gap-2 px-3 py-1 rounded-full border border-white/10 text-[10px] font-mono font-bold uppercase tracking-wider text-[var(--text-primary)] backdrop-blur-md shadow-xs"
                    style="background: color-mix(in srgb, {themeColor} 14%, transparent);"
                  >
                    <span class="w-1.5 h-1.5 rounded-full animate-ping" style="background-color: {themeColor};"></span>
                    <span>Studio Cockpit Active</span>
                  </div>
                  <h2 class="text-2xl font-black text-[var(--text-primary)] tracking-tight pt-1">
                    Language Acquisition Console
                  </h2>
                  <p class="text-xs text-[var(--text-secondary)] leading-relaxed max-w-md">
                    Seamless immersion capture, auditory playback, and spaced-repetition retrieval.
                  </p>
                </div>

                <!-- 🌟 Pulsing Central Radar Beacon 🌟 -->
                <div class="relative flex items-center justify-center shrink-0">
                  <div class="absolute w-16 h-16 rounded-2xl animate-ping opacity-20" style="background-color: {themeColor};"></div>
                  <div 
                    class="w-14 h-14 rounded-2xl border flex items-center justify-center shadow-lg transition-transform duration-300 hover:rotate-6"
                    style="
                      background: color-mix(in srgb, {themeColor} 20%, var(--bg-surface));
                      border-color: color-mix(in srgb, {themeColor} 45%, transparent);
                      color: {themeColor};
                    "
                  >
                    <Zap size={24} strokeWidth={2.5} class="animate-pulse" />
                  </div>
                </div>
              </div>

              <!-- 🌟 QUICK LAUNCH INTERACTIVE TILES 🌟 -->
              <div class="grid grid-cols-1 sm:grid-cols-2 gap-3.5 pt-1 relative z-10">
                
                <!-- Primary Action: Today's Log -->
                <button
                  type="button"
                  onclick={() => navigateTo('day', todayStr)}
                  class="group relative flex items-center justify-between p-4 rounded-2xl border transition-all duration-200 active:scale-[0.98] cursor-pointer text-left overflow-hidden shadow-xs hover:shadow-lg"
                  style="
                    background: color-mix(in srgb, {themeColor} 10%, var(--bg-surface));
                    border-color: color-mix(in srgb, {themeColor} 35%, transparent);
                  "
                >
                  <!-- Light sweep line -->
                  <div class="absolute inset-0 -translate-x-full group-hover:translate-x-full transition-transform duration-700 bg-gradient-to-r from-transparent via-white/10 to-transparent pointer-events-none"></div>

                  <div class="space-y-1 relative z-10">
                    <span class="text-xs font-bold text-[var(--text-primary)] block flex items-center gap-1.5">
                      <span>Today's Immersion Log</span>
                      <span class="w-1.5 h-1.5 rounded-full" style="background-color: {themeColor};"></span>
                    </span>
                    <span class="text-[10px] font-mono text-[var(--text-muted)] block">
                      {todayStr} • Record & Capture
                    </span>
                  </div>
                  
                  <div 
                    class="w-8 h-8 rounded-xl flex items-center justify-center transition-transform group-hover:translate-x-1 duration-200 border border-white/10"
                    style="background: color-mix(in srgb, {themeColor} 20%, transparent); color: {themeColor};"
                  >
                    <ArrowUpRight size={16} strokeWidth={2.5} />
                  </div>
                </button>

                <!-- Secondary Action: Quiz Arena -->
                <button
                  type="button"
                  onclick={() => navigateTo('quiz')}
                  class="group relative flex items-center justify-between p-4 rounded-2xl border border-[var(--border-card)] bg-[var(--bg-surface-elevated)] hover:border-[var(--border-hover)] hover:bg-[var(--bg-surface-active)] transition-all duration-200 active:scale-[0.98] cursor-pointer text-left overflow-hidden shadow-xs hover:shadow-lg"
                >
                  <div class="absolute inset-0 -translate-x-full group-hover:translate-x-full transition-transform duration-700 bg-gradient-to-r from-transparent via-white/5 to-transparent pointer-events-none"></div>

                  <div class="space-y-1 relative z-10">
                    <span class="text-xs font-bold text-[var(--text-primary)] group-hover:text-[var(--text-primary)] transition-colors block flex items-center gap-1.5">
                      <span>Recall & Quiz Arena</span>
                      {#if totalDueQuizCards > 0}
                        <span class="px-1.5 py-0.2 rounded-full text-[9px] font-mono font-bold bg-rose-500/20 text-rose-400 border border-rose-500/30">
                          {totalDueQuizCards}
                        </span>
                      {/if}
                    </span>
                    <span class="text-[10px] font-mono text-[var(--text-muted)] block">
                      Spaced flashcard review
                    </span>
                  </div>

                  <div class="w-8 h-8 rounded-xl bg-black/5 dark:bg-white/5 flex items-center justify-center text-[var(--text-muted)] group-hover:text-[var(--text-primary)] transition-transform group-hover:translate-x-1 duration-200 border border-black/5 dark:border-white/10">
                    <ArrowUpRight size={16} strokeWidth={2.5} />
                  </div>
                </button>
              </div>

              <!-- 🌟 AMBIENT TELEMETRY STRIP 🌟 -->
              <div class="mt-6 pt-5 border-t border-black/5 dark:border-white/10 flex items-center justify-between text-xs relative z-10">
                <div class="flex items-center gap-3 font-mono text-[11px] text-[var(--text-muted)]">
                  <span class="flex items-center gap-1.5">
                    <Layers size={13} style="color: {themeColor};" />
                    <span>{totalWordsCount} Mastered Words</span>
                  </span>
                  <span class="opacity-40">•</span>
                  <span class="flex items-center gap-1.5">
                    <Compass size={13} class="text-sky-400" />
                    <span>{historyLogs.length} Sessions Logged</span>
                  </span>
                </div>

                <button
                  type="button"
                  onclick={() => navigateTo('library')}
                  class="inline-flex items-center gap-1.5 font-semibold text-xs text-[var(--text-secondary)] hover:text-[var(--text-primary)] transition-all cursor-pointer group"
                >
                  <BookOpen size={13} style="color: {themeColor};" />
                  <span>CI Library</span>
                  <ChevronRight size={12} class="group-hover:translate-x-0.5 transition-transform" />
                </button>
              </div>

            </div>
          </div>
        {:else if activeRoute === 'day'}
          {#if selectedDate}
            <DayPage date={selectedDate} langCode={metadataStore.activeLanguage} />
          {:else}
            <div class="flex flex-col items-center justify-center h-full text-center p-8 text-xs text-[var(--text-muted)]">
              No date selected. Pick a date from the dashboard calendar.
            </div>
          {/if}
        {:else if activeRoute === 'quiz'}
          <QuizPage langCode={metadataStore.activeLanguage} onBack={() => navigateTo('dashboard')} />
        {:else if activeRoute === 'library'}
          <LibraryPage onSelectDate={(date) => navigateTo('day', date)} />
        {:else if activeRoute === 'settings'}
          <SettingsPage />
        {/if}
      </main>

    </div>
  {/if}

  <!-- Side Navigation Drawer Component -->
  {#if activeRoute !== 'select-language'}
    <RightEdgeDrawer bind:isOpen={isDrawerOpen} width={360}>
      <div class="flex flex-col h-full space-y-4">
        
        <div class="space-y-1.5 shrink-0">
          <button
            type="button"
            onclick={() => navigateTo('select-language')}
            class="group w-full text-left px-3.5 py-3 rounded-2xl border font-semibold flex items-center justify-between transition-all duration-150 cursor-pointer {activeRoute === 'select-language'
              ? 'border-[var(--accent)] bg-[var(--accent)]/10 text-[var(--accent)] shadow-xs'
              : 'border-[var(--border-subtle)] bg-[var(--bg-surface)] hover:bg-[var(--bg-surface-elevated)] hover:border-[var(--border-hover)] text-[var(--text-primary)]'}"
          >
            <div class="flex items-center gap-2.5">
              <Globe size={16} class="group-hover:scale-110 transition-transform" />
              <span class="text-xs font-medium tracking-tight">Switch Language</span>
              {#if activeRoute === 'select-language'}
                <span class="text-[9px] font-bold uppercase px-1.5 py-0.5 rounded-md bg-[var(--accent)] text-white">Active</span>
              {/if}
            </div>
            <ChevronRight size={14} class="text-[var(--text-muted)] group-hover:translate-x-0.5 transition-transform" />
          </button>

          <button
            type="button"
            onclick={() => navigateTo('dashboard')}
            class="group w-full text-left px-3.5 py-3 rounded-2xl border font-semibold flex items-center justify-between transition-all duration-150 cursor-pointer {activeRoute === 'dashboard'
              ? 'border-[var(--accent)] bg-[var(--accent)]/10 text-[var(--accent)] shadow-xs'
              : 'border-[var(--border-subtle)] bg-[var(--bg-surface)] hover:bg-[var(--bg-surface-elevated)] hover:border-[var(--border-hover)] text-[var(--text-primary)]'}"
          >
            <div class="flex items-center gap-2.5">
              <LayoutDashboard size={16} class="group-hover:scale-110 transition-transform" />
              <span class="text-xs font-medium tracking-tight">Dashboard</span>
              {#if activeRoute === 'dashboard'}
                <span class="text-[9px] font-bold uppercase px-1.5 py-0.5 rounded-md bg-[var(--accent)] text-white">Active</span>
              {/if}
            </div>
            <ChevronRight size={14} class="text-[var(--text-muted)] group-hover:translate-x-0.5 transition-transform" />
          </button>

          <button
            type="button"
            onclick={() => navigateTo('quiz')}
            class="group w-full text-left px-3.5 py-3 rounded-2xl border font-semibold flex items-center justify-between transition-all duration-150 cursor-pointer {activeRoute === 'quiz'
              ? 'border-[var(--accent)] bg-[var(--accent)]/10 text-[var(--accent)] shadow-xs'
              : 'border-[var(--border-subtle)] bg-[var(--bg-surface)] hover:bg-[var(--bg-surface-elevated)] hover:border-[var(--border-hover)] text-[var(--text-primary)]'}"
          >
            <div class="flex items-center gap-2.5">
              <Target size={16} class="group-hover:scale-110 transition-transform" />
              <span class="text-xs font-medium tracking-tight">Quiz Arena</span>
              {#if activeRoute === 'quiz'}
                <span class="text-[9px] font-bold uppercase px-1.5 py-0.5 rounded-md bg-[var(--accent)] text-white">Active</span>
              {/if}
            </div>
            <div class="flex items-center gap-1.5">
              {#if totalDueQuizCards > 0}
                <span class="text-[10px] font-mono font-bold px-2 py-0.5 rounded-full bg-rose-500/15 text-rose-400 border border-rose-500/20 shadow-xs">
                  {totalDueQuizCards} due
                </span>
              {/if}
              <ChevronRight size={14} class="text-[var(--text-muted)] group-hover:translate-x-0.5 transition-transform" />
            </div>
          </button>

          <button
            type="button"
            onclick={() => navigateTo('library')}
            class="group w-full text-left px-3.5 py-3 rounded-2xl border font-semibold flex items-center justify-between transition-all duration-150 cursor-pointer {activeRoute === 'library'
              ? 'border-[var(--accent)] bg-[var(--accent)]/10 text-[var(--accent)] shadow-xs'
              : 'border-[var(--border-subtle)] bg-[var(--bg-surface)] hover:bg-[var(--bg-surface-elevated)] hover:border-[var(--border-hover)] text-[var(--text-primary)]'}"
          >
            <div class="flex items-center gap-2.5">
              <BookOpen size={16} class="group-hover:scale-110 transition-transform" />
              <span class="text-xs font-medium tracking-tight">CI Candidate Library</span>
              {#if activeRoute === 'library'}
                <span class="text-[9px] font-bold uppercase px-1.5 py-0.5 rounded-md bg-[var(--accent)] text-white">Active</span>
              {/if}
            </div>
            <ChevronRight size={14} class="text-[var(--text-muted)] group-hover:translate-x-0.5 transition-transform" />
          </button>
        </div>

        <!-- History Stream Section -->
        <section class="flex-1 flex flex-col min-h-0 pt-3 border-t border-[var(--border-subtle)]">
          <div class="flex items-center justify-between px-1 mb-2">
            <span class="text-[10px] font-bold uppercase tracking-wider text-[var(--text-muted)]">
              Logged Sessions
            </span>
            <span class="text-[10px] font-mono text-[var(--text-muted)] bg-[var(--badge-bg)] px-2 py-0.5 rounded-md border border-[var(--border-subtle)]">
              {historyLogs.length} total
            </span>
          </div>

          {#if historyLogs.length === 0}
            <div class="py-8 text-center text-xs text-[var(--text-muted)]">
              No session logs recorded yet.
            </div>
          {:else}
            <div class="flex-1 overflow-y-auto space-y-1.5 pr-0.5">
              {#each historyLogs as log (log.date)}
                {@const isCurrent = activeRoute === 'day' && selectedDate === log.date}
                <button
                  type="button"
                  onclick={() => navigateTo('day', log.date)}
                  class="w-full text-left p-3 rounded-2xl border transition-all duration-150 cursor-pointer flex items-center justify-between {isCurrent 
                    ? 'border-[var(--accent)] bg-[var(--accent)]/10 ring-1 ring-[var(--accent)]/30' 
                    : 'border-[var(--border-subtle)] bg-[var(--bg-surface)] hover:bg-[var(--bg-surface-elevated)] hover:border-[var(--border-hover)]'}"
                >
                  <div class="space-y-1">
                    <div class="flex items-center gap-2">
                      <span class="font-mono font-semibold text-xs {isCurrent ? 'text-[var(--accent)]' : 'text-[var(--text-primary)]'}">
                        {log.date}
                      </span>
                      {#if isCurrent}
                        <span class="text-[9px] font-bold uppercase px-1.5 py-0.2 rounded bg-[var(--accent)] text-white">
                          Current
                        </span>
                      {/if}
                    </div>
                    <div class="text-[10px] text-[var(--text-secondary)] flex items-center gap-1.5 font-medium">
                      {#if log.words > 0}<span class="px-1.5 py-0.5 rounded bg-[var(--badge-bg)]">{log.words}w</span>{/if}
                      {#if log.ci > 0}<span class="px-1.5 py-0.5 rounded bg-[var(--badge-bg)]">{log.ci}ci</span>{/if}
                      {#if log.listening > 0}<span class="px-1.5 py-0.5 rounded bg-[var(--badge-bg)]">{log.listening}lp</span>{/if}
                    </div>
                  </div>

                  <span class="text-[10px] font-mono font-bold px-2 py-1 rounded-lg border border-[var(--border-subtle)] bg-[var(--bg-surface-elevated)] text-[var(--text-secondary)]">
                    P{log.revision}
                  </span>
                </button>
              {/each}
            </div>
          {/if}
        </section>

        <!-- Language Settings Dock -->
        <div class="pt-2 shrink-0 border-t border-[var(--border-subtle)]">
          <button
            type="button"
            onclick={() => navigateTo('settings')}
            class="group w-full text-left px-3.5 py-3 rounded-2xl border font-semibold flex items-center justify-between transition-all duration-150 cursor-pointer {activeRoute === 'settings'
              ? 'border-[var(--accent)] bg-[var(--accent)]/10 text-[var(--accent)] shadow-xs'
              : 'border-[var(--border-subtle)] bg-[var(--bg-surface)] hover:bg-[var(--bg-surface-elevated)] hover:border-[var(--border-hover)] text-[var(--text-primary)]'}"
          >
            <div class="flex items-center gap-2.5">
              <Settings size={16} class="group-hover:rotate-45 transition-transform duration-200" />
              <span class="text-xs font-medium tracking-tight">Language Settings</span>
            </div>
            <ChevronRight size={14} class="text-[var(--text-muted)] group-hover:translate-x-0.5 transition-transform" />
          </button>
        </div>

      </div>
    </RightEdgeDrawer>
  {/if}

  <UploadProgressBar />
</div>

<style>
  .perspective-1000 {
    perspective: 1000px;
  }

  @keyframes pulseSlow {
    0%, 100% { transform: scale(1); opacity: 0.2; }
    50% { transform: scale(1.08); opacity: 0.28; }
  }

  @keyframes spinUltraSlow {
    from { transform: rotate(0deg); }
    to { transform: rotate(360deg); }
  }

  @keyframes spinReverse {
    from { transform: rotate(360deg); }
    to { transform: rotate(0deg); }
  }

  @keyframes floatSlow1 {
    0%, 100% { transform: translateY(0px) rotate(0deg); }
    50% { transform: translateY(-8px) rotate(-1.5deg); }
  }

  @keyframes floatSlow2 {
    0%, 100% { transform: translateY(0px) rotate(0deg); }
    50% { transform: translateY(10px) rotate(2deg); }
  }

  .animate-pulse-slow {
    animation: pulseSlow 8s ease-in-out infinite;
  }

  .animate-spin-ultra-slow {
    animation: spinUltraSlow 35s linear infinite;
  }

  .animate-spin-reverse {
    animation: spinReverse 45s linear infinite;
  }

  .animate-float-1 {
    animation: floatSlow1 6s ease-in-out infinite;
  }

  .animate-float-2 {
    animation: floatSlow2 7.5s ease-in-out infinite;
  }
</style>