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

  let activeRoute = $state('select-language');
  let selectedDate = $state(null);
  let mainEl = $state(null);
  let isDrawerOpen = $state(false);

  // Scroll retention
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
    if (lang) {
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

  // Pull history entries for active language, sorted latest -> oldest
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

  // Calculate total due flashcards across both visual & audio types
  let totalDueQuizCards = $derived.by(() => {
    if (!srsStore.getDueCounts) return 0;
    const counts = srsStore.getDueCounts();
    return (counts.audio || 0) + (counts.visual || 0);
  });

  // Handles URLs opened by notification clicks
  function handleDeepLink(pathname = window.location.pathname) {
    // 1. Session log deep-link: /log/{lang}/{date}
    const logMatch = pathname.match(/^\/log\/([a-zA-Z0-9_-]+)\/(\d{4}-\d{2}-\d{2})$/);
    if (logMatch) {
      const [, langCode, targetDate] = logMatch;
      if (metadataStore.languages[langCode]) {
        metadataStore.activeLanguage = langCode;
      }
      activeLanguage.selectedDate = targetDate;
      window.history.replaceState({}, '', '/');
      return;
    }

    // 2. SRS review deep-link: /srs/{lang}
    const srsMatch = pathname.match(/^\/srs\/([a-zA-Z0-9_-]+)$/);
    if (srsMatch) {
      const [, langCode] = srsMatch;
      if (metadataStore.languages[langCode]) {
        metadataStore.activeLanguage = langCode;
      }
      activeLanguage.activeTab = 'srs';
      window.history.replaceState({}, '', '/');
      return;
    }
  }

  onMount(() => {
    metadataStore.init();

    handleDeepLink();
    window.addEventListener('popstate', () => handleDeepLink());

    // 1. Initialize Service Worker & Native Notification loop asynchronously
    (async () => {
      await notificationService.init();
      if (notificationService.permission === 'granted') {
        notificationService.startScheduler(19); // 7:00 PM default evening check
      }
    })();

    // 2. Hash routing setup
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

    // Teardown cleanup stays intact
    return () => window.removeEventListener('popstate', onPopState);
  });
</script>

<div class="relative flex flex-col h-full w-full bg-[var(--bg-base)] text-[var(--text-primary)] select-none transition-colors duration-200 overflow-hidden">
  <Header {handleBack} {activeRoute} />

  {#if activeRoute === 'select-language'}
    <main class="flex-1 overflow-y-auto overscroll-none px-4 py-3 safe-bottom">
      <LanguageSelectPage onSelectLanguage={(langCode) => navigateTo('dashboard', langCode)} />
    </main>
  {:else}
    <div class="flex-1 flex flex-col lg:flex-row w-full h-full overflow-hidden">
      
      <!-- LEFT PANE: Fixed 720px Dashboard on PC -->
      <aside class="hidden lg:flex flex-col w-[720px] shrink-0 border-r border-[var(--border-card)] bg-[var(--bg-surface)] h-full overflow-y-auto overscroll-none px-4 py-3">
        <DashboardPage onSelectDate={(date) => navigateTo('day', date)} />
      </aside>

      <!-- RIGHT PANE: Dynamic Workspace -->
      <main 
        bind:this={mainEl} 
        class="flex-1 h-full overflow-y-auto overscroll-none px-4 py-3 safe-bottom"
      >
        {#if activeRoute === 'dashboard'}
          <!-- Mobile shows Dashboard here -->
          <div class="block lg:hidden">
            <DashboardPage onSelectDate={(date) => navigateTo('day', date)} />
          </div>

          <!-- Desktop prompt -->
          <div class="hidden lg:flex flex-col items-center justify-center h-full text-center px-4 py-16 text-[var(--text-muted)] space-y-4">
            <div class="w-16 h-16 rounded-2xl border border-[var(--border-card)] bg-[var(--bg-surface)] flex items-center justify-center text-2xl shadow-xs">
              👈
            </div>
            <div class="space-y-1">
              <h2 class="text-sm font-bold text-[var(--text-primary)]">
                Select a Date or Tab
              </h2>
              <p class="text-xs max-w-xs">
                Pick a date from the calendar or choose an option from the menu to open your workspace.
              </p>
            </div>
            <div class="flex items-center gap-2 pt-2">
              <button
                type="button"
                onclick={() => navigateTo('quiz')}
                class="flex items-center gap-1.5 px-3 py-1.5 rounded-xl border border-[var(--border-card)] bg-[var(--bg-surface)] hover:bg-[var(--bg-surface-active)] text-xs font-bold text-[var(--text-primary)] transition-colors cursor-pointer"
              >
                <span>🎯</span>
                <span>Quiz Arena</span>
              </button>
              <button
                type="button"
                onclick={() => navigateTo('library')}
                class="flex items-center gap-1.5 px-3 py-1.5 rounded-xl border border-[var(--border-card)] bg-[var(--bg-surface)] hover:bg-[var(--bg-surface-active)] text-xs font-bold text-[var(--text-primary)] transition-colors cursor-pointer"
              >
                <span>📚</span>
                <span>CI Library</span>
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
    <RightEdgeDrawer bind:isOpen={isDrawerOpen} width={340}>
      <div class="space-y-1.5 shrink-0">
        <!-- 1. Switch Language Button -->
        <button
          type="button"
          onclick={() => navigateTo('select-language')}
          class="w-full text-left px-3.5 py-2.5 rounded-xl border font-bold flex items-center justify-between transition-all cursor-pointer {activeRoute === 'select-language'
            ? 'border-[var(--interactive-accent,var(--text-primary))] bg-[var(--bg-base)] ring-1 ring-[var(--interactive-accent,var(--text-primary))]'
            : 'border-[var(--border-card)] bg-[var(--bg-base)] hover:bg-[var(--bg-surface-active)]'}"
        >
          <div class="flex items-center gap-2">
            <span>🌐</span>
            <span class={activeRoute === 'select-language' ? 'text-[var(--interactive-accent,var(--text-primary))]' : 'text-[var(--text-primary)]'}>
              Switch Language
            </span>
            {#if activeRoute === 'select-language'}
              <span class="text-[9px] font-black uppercase px-1 py-0.5 rounded bg-[var(--interactive-accent,var(--text-primary))] text-[var(--bg-base)]">
                Current
              </span>
            {/if}
          </div>
          <span class="text-[var(--text-muted)] font-mono text-xs">→</span>
        </button>

        <!-- 2. Dashboard Button -->
        <button
          type="button"
          onclick={() => navigateTo('dashboard')}
          class="w-full text-left px-3.5 py-2.5 rounded-xl border font-bold flex items-center justify-between transition-all cursor-pointer {activeRoute === 'dashboard'
            ? 'border-[var(--interactive-accent,var(--text-primary))] bg-[var(--bg-base)] ring-1 ring-[var(--interactive-accent,var(--text-primary))]'
            : 'border-[var(--border-card)] bg-[var(--bg-base)] hover:bg-[var(--bg-surface-active)]'}"
        >
          <div class="flex items-center gap-2">
            <span>📊</span>
            <span class={activeRoute === 'dashboard' ? 'text-[var(--interactive-accent,var(--text-primary))]' : 'text-[var(--text-primary)]'}>
              Dashboard
            </span>
            {#if activeRoute === 'dashboard'}
              <span class="text-[9px] font-black uppercase px-1 py-0.5 rounded bg-[var(--interactive-accent,var(--text-primary))] text-[var(--bg-base)]">
                Current
              </span>
            {/if}
          </div>
          <span class="text-[var(--text-muted)] font-mono text-xs">→</span>
        </button>

        <!-- 3. Quiz Arena Button -->
        <button
          type="button"
          onclick={() => navigateTo('quiz')}
          class="w-full text-left px-3.5 py-2.5 rounded-xl border font-bold flex items-center justify-between transition-all cursor-pointer {activeRoute === 'quiz'
            ? 'border-[var(--interactive-accent,var(--text-primary))] bg-[var(--bg-base)] ring-1 ring-[var(--interactive-accent,var(--text-primary))]'
            : 'border-[var(--border-card)] bg-[var(--bg-base)] hover:bg-[var(--bg-surface-active)]'}"
        >
          <div class="flex items-center gap-2">
            <span>🎯</span>
            <span class={activeRoute === 'quiz' ? 'text-[var(--interactive-accent,var(--text-primary))]' : 'text-[var(--text-primary)]'}>
              Quiz Arena
            </span>
            {#if activeRoute === 'quiz'}
              <span class="text-[9px] font-black uppercase px-1 py-0.5 rounded bg-[var(--interactive-accent,var(--text-primary))] text-[var(--bg-base)]">
                Current
              </span>
            {/if}
          </div>
          <div class="flex items-center gap-1.5">
            {#if totalDueQuizCards > 0}
              <span class="text-[10px] font-mono font-black px-2 py-0.5 rounded-full bg-rose-500/15 text-rose-500 border border-rose-500/20">
                {totalDueQuizCards} due
              </span>
            {/if}
            <span class="text-[var(--text-muted)] font-mono text-xs">→</span>
          </div>
        </button>

        <!-- 4. Library Button -->
        <button
          type="button"
          onclick={() => navigateTo('library')}
          class="w-full text-left px-3.5 py-2.5 rounded-xl border font-bold flex items-center justify-between transition-all cursor-pointer {activeRoute === 'library'
            ? 'border-[var(--interactive-accent,var(--text-primary))] bg-[var(--bg-base)] ring-1 ring-[var(--interactive-accent,var(--text-primary))]'
            : 'border-[var(--border-card)] bg-[var(--bg-base)] hover:bg-[var(--bg-surface-active)]'}"
        >
          <div class="flex items-center gap-2">
            <span>📚</span>
            <span class={activeRoute === 'library' ? 'text-[var(--interactive-accent,var(--text-primary))]' : 'text-[var(--text-primary)]'}>
              CI Candidate Library
            </span>
            {#if activeRoute === 'library'}
              <span class="text-[9px] font-black uppercase px-1 py-0.5 rounded bg-[var(--interactive-accent,var(--text-primary))] text-[var(--bg-base)]">
                Current
              </span>
            {/if}
          </div>
          <span class="text-[var(--text-muted)] font-mono text-xs">→</span>
        </button>
      </div>

      <!-- History Section -->
      <section class="space-y-2 pt-2 border-t border-[var(--border-card)]">
        <div class="flex items-center justify-between px-1">
          <span class="text-[10px] font-extrabold uppercase tracking-wider text-[var(--text-muted)]">
            History
          </span>
          <span class="text-[10px] font-mono text-[var(--text-muted)] font-bold">
            {historyLogs.length} sessions
          </span>
        </div>

        {#if historyLogs.length === 0}
          <div class="py-8 text-center text-[11px] text-[var(--text-muted)]">
            No history available.
          </div>
        {:else}
          <div class="space-y-1 pr-0.5">
            {#each historyLogs as log (log.date)}
              {@const isCurrent = activeRoute === 'day' && selectedDate === log.date}
              <button
                type="button"
                onclick={() => navigateTo('day', log.date)}
                class="w-full text-left p-2.5 rounded-xl border transition-all cursor-pointer flex items-center justify-between {isCurrent 
                  ? 'border-[var(--interactive-accent,var(--text-primary))] bg-[var(--bg-base)] ring-1 ring-[var(--interactive-accent,var(--text-primary))]' 
                  : 'border-[var(--border-card)] bg-[var(--bg-base)] hover:bg-[var(--bg-surface-active)]'}"
              >
                <div class="space-y-0.5">
                  <div class="flex items-center gap-2">
                    <span class="font-mono font-bold text-xs {isCurrent ? 'text-[var(--interactive-accent,var(--text-primary))]' : 'text-[var(--text-primary)]'}">
                      {log.date}
                    </span>
                    {#if isCurrent}
                      <span class="text-[9px] font-black uppercase px-1 py-0.5 rounded bg-[var(--interactive-accent,var(--text-primary))] text-[var(--bg-base)]">
                        Current
                      </span>
                    {/if}
                  </div>
                  <div class="text-[10px] text-[var(--text-muted)] flex items-center gap-1.5 font-medium">
                    {#if log.words > 0}<span>{log.words}w</span>{/if}
                    {#if log.ci > 0}<span>{log.ci}ci</span>{/if}
                    {#if log.listening > 0}<span>{log.listening}lp</span>{/if}
                  </div>
                </div>

                <span class="text-[10px] font-mono font-extrabold px-2 py-0.5 rounded-md border border-[var(--border-card)] bg-[var(--bg-surface)] text-[var(--text-muted)]">
                  P{log.revision}
                </span>
              </button>
            {/each}
          </div>
        {/if}
      </section>

      <!-- 6. Settings Button -->
      <button
        type="button"
        onclick={() => navigateTo('settings')}
        class="w-full text-left px-3.5 py-2.5 rounded-xl border font-bold flex items-center justify-between transition-all cursor-pointer {activeRoute === 'settings'
          ? 'border-[var(--interactive-accent,var(--text-primary))] bg-[var(--bg-base)] ring-1 ring-[var(--interactive-accent,var(--text-primary))]'
          : 'border-[var(--border-card)] bg-[var(--bg-base)] hover:bg-[var(--bg-surface-active)]'}"
      >
        <div class="flex items-center gap-2">
          <span>⚙️</span>
          <span class={activeRoute === 'settings' ? 'text-[var(--interactive-accent,var(--text-primary))]' : 'text-[var(--text-primary)]'}>
            Language Settings
          </span>
        </div>
        <span class="text-[var(--text-muted)] font-mono text-xs">→</span>
      </button>
    </RightEdgeDrawer>
  {/if}

  <UploadProgressBar />
</div>