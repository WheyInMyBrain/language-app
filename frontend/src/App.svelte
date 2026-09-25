<!-- frontend/src/App.svelte -->
<script>
  import { onMount, tick } from 'svelte';
  import { metadataStore } from './lib/stores/metadata.svelte.js';
  import { notificationService } from './lib/services/notificationService.js';
  import { srsStore } from './lib/stores/srs.svelte.js';
  import { vocabIndexStore } from './lib/stores/vocabIndex.svelte.js';
  import { ciIndexStore } from './lib/stores/ciIndex.svelte.js';
  import { listeningIndexStore } from './lib/stores/listeningIndex.svelte.js';

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
    Zap 
  } from '@lucide/svelte';

  let activeRoute = $state('select-language');
  let selectedDate = $state(null);
  let mainEl = $state(null);
  let isDrawerOpen = $state(false);
  let lastConnectedLang = '';

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

  // 🌟 GUARDED STORE CONNECTIONS (Zero cascade re-triggers) 🌟
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

  // Cached history extraction - only processes when calendarIndex or activeLanguage changes
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
  
  <!-- Zero-GPU Ambient Radial Lighting -->
  <div 
    class="pointer-events-none absolute -top-40 left-1/3 w-[650px] h-[350px] -z-10"
    style="background: radial-gradient(ellipse at center, rgba(99, 102, 241, 0.08) 0%, transparent 70%); transform: translateZ(0);"
  ></div>
  <div 
    class="pointer-events-none absolute bottom-0 right-1/4 w-[500px] h-[300px] -z-10"
    style="background: radial-gradient(ellipse at center, rgba(168, 85, 247, 0.05) 0%, transparent 70%); transform: translateZ(0);"
  ></div>

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

      <!-- RIGHT WORKSPACE: Live Stage (Isolated Stacking Plane) -->
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

          <!-- Desktop View -->
          <div class="hidden lg:flex flex-col items-center justify-center min-h-[80%] max-w-2xl mx-auto space-y-6">
            
            <div class="w-full rounded-3xl border border-[var(--border-card)] bg-[var(--bg-surface)] p-6 sm:p-8 shadow-sm relative overflow-hidden">
              <div class="absolute top-0 left-0 right-0 h-1 bg-gradient-to-r from-indigo-500 via-purple-500 to-sky-400"></div>

              <div class="flex items-start justify-between gap-4 mb-6">
                <div class="space-y-1">
                  <div class="inline-flex items-center gap-2 px-2.5 py-1 rounded-full bg-[var(--badge-bg)] border border-[var(--border-subtle)] text-[10px] font-mono font-bold uppercase tracking-wider text-[var(--accent)]">
                    <Sparkles size={12} class="text-[var(--accent)]" />
                    <span>Workspace Active</span>
                  </div>
                  <h2 class="text-xl font-black text-[var(--text-primary)] tracking-tight pt-1">
                    Ready to practice today?
                  </h2>
                  <p class="text-xs text-[var(--text-secondary)] leading-relaxed">
                    Pick up today's session or jump straight into your scheduled flashcards.
                  </p>
                </div>

                <div class="w-12 h-12 rounded-2xl bg-[var(--bg-surface-elevated)] border border-[var(--border-subtle)] flex items-center justify-center text-indigo-400 shadow-inner shrink-0">
                  <Zap size={22} />
                </div>
              </div>

              <div class="grid grid-cols-1 sm:grid-cols-2 gap-3 pt-2">
                <button
                  type="button"
                  onclick={() => navigateTo('day', todayStr)}
                  class="group flex items-center justify-between p-4 rounded-2xl border border-indigo-500/30 bg-indigo-500/5 hover:bg-indigo-500/10 hover:border-indigo-500/50 transition-all duration-150 active:scale-[0.98] cursor-pointer text-left shadow-xs"
                >
                  <div class="space-y-0.5">
                    <span class="text-xs font-bold text-[var(--text-primary)] group-hover:text-indigo-400 transition-colors block">
                      Today's Log
                    </span>
                    <span class="text-[10px] font-mono text-[var(--text-muted)]">
                      {todayStr}
                    </span>
                  </div>
                  <ChevronRight size={16} class="text-indigo-400 group-hover:translate-x-1 transition-transform" />
                </button>

                <button
                  type="button"
                  onclick={() => navigateTo('quiz')}
                  class="group flex items-center justify-between p-4 rounded-2xl border border-[var(--border-card)] bg-[var(--bg-surface-elevated)] hover:border-[var(--border-hover)] hover:bg-[var(--bg-surface-active)] transition-all duration-150 active:scale-[0.98] cursor-pointer text-left shadow-xs"
                >
                  <div class="space-y-0.5">
                    <span class="text-xs font-bold text-[var(--text-primary)] group-hover:text-[var(--accent)] transition-colors block">
                      Quiz Arena
                    </span>
                    <span class="text-[10px] font-mono text-[var(--text-muted)]">
                      {totalDueQuizCards} cards due
                    </span>
                  </div>
                  <ChevronRight size={16} class="text-[var(--text-muted)] group-hover:text-[var(--text-primary)] group-hover:translate-x-1 transition-transform" />
                </button>
              </div>
            </div>

            <div class="w-full flex items-center justify-between px-2 text-xs text-[var(--text-muted)]">
              <span class="font-mono text-[11px]">
                Tip: Click any past date on the left to review its notes & audio
              </span>
              <button
                type="button"
                onclick={() => navigateTo('library')}
                class="inline-flex items-center gap-1.5 font-semibold text-[var(--text-secondary)] hover:text-[var(--text-primary)] cursor-pointer transition-colors"
              >
                <BookOpen size={14} />
                <span>Open CI Library</span>
              </button>
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