<!-- frontend/src/pages/SettingsPage.svelte -->
<script>
  import { untrack } from 'svelte';
  import { metadataStore } from '../lib/stores/metadata.svelte.js';
  import { notificationService } from '../lib/services/notificationService.js';

  // Razor-sharp icons
  import { 
    Palette, 
    Sliders, 
    Bell, 
    Database, 
    Target, 
    Music, 
    Sparkles, 
    Check, 
    Clock, 
    Zap, 
    RefreshCw,
    CloudCheck,
    CloudUpload
  } from '@lucide/svelte';

  let currentLang = $derived(
    metadataStore.languages && metadataStore.activeLanguage
      ? metadataStore.languages[metadataStore.activeLanguage] || {}
      : {}
  );

  let goals = $state({
    vocab: 10,
    ci: 1,
    grammar: 1,
    listening_minutes: 45,
    speaking_minutes: 10
  });

  let colors = $state({
    theme: { dark_primary: '#a855f7', light_primary: '#9333ea' }
  });
  let tones = $state({});

  // Auto-save sync status: 'idle' | 'saving' | 'saved'
  let syncState = $state('idle');
  let saveDebounceTimer = null;
  let isInitialLoad = true;

  // Primary Theme Color (fallback to ultraviolet)
  let currentThemeColor = $derived(
    colors?.theme?.dark_primary || 
    colors?.theme?.light_primary || 
    '#a855f7'
  );

  const THEME_PRESETS = [
    { name: 'Ultraviolet', hex: '#a855f7' },
    { name: 'Electric Indigo', hex: '#6366f1' },
    { name: 'Emerald Neo', hex: '#10b981' },
    { name: 'Rose Quartz', hex: '#f43f5e' },
    { name: 'Cyan Pulse', hex: '#06b6d4' },
    { name: 'Amber Forge', hex: '#f59e0b' }
  ];

  // Notification UI states
  let isPushEnabled = $state(notificationService.isEnabled);
  let notifStatusMsg = $state('');
  let isTogglingNotif = $state(false);
  let reminderHour = $state(19);

  // Backup trigger state
  let isBackingUp = $state(false);
  let backupStatus = $state('');

  // 1. Initial Load from Store into Local State
  $effect(() => {
    const lang = currentLang;

    untrack(() => {
      if (!lang) return;

      if (lang.goals) {
        goals = {
          vocab: lang.goals.vocab ?? 10,
          ci: lang.goals.ci ?? 1,
          grammar: lang.goals.grammar ?? 1,
          listening_minutes: lang.goals.listening_minutes ?? 45,
          speaking_minutes: lang.goals.speaking_minutes ?? 10
        };
      }
      if (lang.colors) {
        colors = JSON.parse(JSON.stringify(lang.colors));
      }
      if (!colors.theme) {
        colors.theme = { dark_primary: '#a855f7', light_primary: '#9333ea' };
      }
      if (lang.tones) {
        tones = JSON.parse(JSON.stringify(lang.tones));
      }
      // Allow initial load to finish without triggering an auto-save
      setTimeout(() => {
        isInitialLoad = false;
      }, 50);
    });
  });

  // 2. Real-time Auto-Save Engine
  function triggerAutoSave(immediate = false) {
    if (isInitialLoad || !metadataStore.activeLanguage) return;

    syncState = 'saving';
    if (saveDebounceTimer) clearTimeout(saveDebounceTimer);

    const commitSave = () => {
      metadataStore.updateLanguageConfig(metadataStore.activeLanguage, {
        goals: $state.snapshot(goals),
        colors: $state.snapshot(colors),
        tones: $state.snapshot(tones)
      });
      syncState = 'saved';
      setTimeout(() => {
        if (syncState === 'saved') syncState = 'idle';
      }, 2000);
    };

    if (immediate) {
      commitSave();
    } else {
      saveDebounceTimer = setTimeout(commitSave, 400);
    }
  }

  function setThemePreset(hex) {
    if (!colors.theme) colors.theme = {};
    colors.theme.dark_primary = hex;
    colors.theme.light_primary = hex;
    triggerAutoSave(true);
  }

  async function handleToggleNotifications() {
    isTogglingNotif = true;
    notifStatusMsg = '';

    if (isPushEnabled) {
      await notificationService.unsubscribeFromWebPush();
      isPushEnabled = false;
      notifStatusMsg = 'Notifications disabled.';
    } else {
      if (Notification.permission !== 'granted') {
        const perm = await Notification.requestPermission();
        if (perm !== 'granted') {
          notifStatusMsg = 'Permission denied in browser settings.';
          isTogglingNotif = false;
          return;
        }
      }

      notifStatusMsg = 'Registering device...';
      await notificationService.init();
      const result = await notificationService.subscribeToWebPush();

      if (result.ok) {
        isPushEnabled = true;
        notifStatusMsg = 'Connected & registered in SQLite!';
        notificationService.startScheduler(reminderHour);
        notificationService.dispatch('🔔 Notifications & WebPush Active', {
          body: 'Your device is linked to the Rust backend.'
        });
      } else {
        isPushEnabled = false;
        notifStatusMsg = `Failed: ${result.error}`;
      }
    }

    isTogglingNotif = false;
    setTimeout(() => (notifStatusMsg = ''), 4000);
  }

  function handleTestNotification() {
    notificationService.dispatch('⚡ Test Alert', {
      body: 'Your local notification system is working!'
    });
  }

  async function handleManualBackup() {
    isBackingUp = true;
    backupStatus = 'Projecting SQLite DB...';
    try {
      const res = await fetch('/api/backup/now', { method: 'POST' });
      const data = await res.json();
      if (res.ok) {
        backupStatus = `Snapshot saved: ${data.file || 'backup.db.gz'}`;
      } else {
        backupStatus = `Error: ${data.message || 'Failed'}`;
      }
    } catch (err) {
      backupStatus = 'Connection failed';
    } finally {
      isBackingUp = false;
      setTimeout(() => (backupStatus = ''), 4000);
    }
  }
</script>

<div class="relative w-full max-w-4xl xl:max-w-5xl mx-auto space-y-8 pt-4 pb-28 px-3 sm:px-6 select-none">
  
  <!-- Reactive Ambient Backlight -->
  <div 
    class="pointer-events-none absolute -top-32 left-1/3 w-[650px] h-[380px] rounded-full blur-[140px] opacity-20 transition-all duration-700 ease-out"
    style="background-color: {currentThemeColor};"
  ></div>

  <!-- TOP BAR: Title & Auto-Save Telemetry Chip -->
  <header class="relative flex flex-col sm:flex-row sm:items-center justify-between gap-4 pb-5 border-b border-[var(--border-subtle)] z-10">
    <div class="space-y-1">
      <div class="inline-flex items-center gap-2 px-2.5 py-1 rounded-full bg-[var(--bg-surface)] border border-[var(--border-subtle)] shadow-xs">
        <Sliders size={12} style="color: {currentThemeColor};" />
        <span class="text-[10px] font-mono font-bold uppercase tracking-widest text-[var(--text-muted)]">
          Target Workspace Studio
        </span>
      </div>
      <h1 class="text-2xl sm:text-3xl font-black tracking-tight text-[var(--text-primary)]">
        {currentLang.name || 'Language'} Configuration
      </h1>
      <p class="text-xs font-mono text-[var(--text-muted)] flex items-center gap-1.5">
        <span>Target:</span>
        <span class="px-1.5 py-0.2 rounded bg-[var(--badge-bg)] text-[var(--text-primary)] font-bold">{metadataStore.activeLanguage}</span>
      </p>
    </div>

    <!-- Auto-Save Pulse Indicator -->
    <div class="flex items-center gap-2">
      {#if syncState === 'saving'}
        <div class="inline-flex items-center gap-2 px-3.5 py-1.5 rounded-xl bg-amber-500/10 border border-amber-500/25 text-amber-400 font-mono text-xs font-bold animate-pulse shadow-xs">
          <CloudUpload size={14} class="animate-bounce" />
          <span>Syncing changes...</span>
        </div>
      {:else if syncState === 'saved'}
        <div class="inline-flex items-center gap-2 px-3.5 py-1.5 rounded-xl bg-emerald-500/10 border border-emerald-500/25 text-emerald-400 font-mono text-xs font-bold shadow-[0_0_12px_rgba(16,185,129,0.2)] animate-in fade-in duration-200">
          <Check size={14} strokeWidth={2.5} />
          <span>Changes synchronized</span>
        </div>
      {:else}
        <div class="inline-flex items-center gap-2 px-3.5 py-1.5 rounded-xl bg-[var(--bg-surface)] border border-[var(--border-subtle)] text-[var(--text-muted)] font-mono text-[11px] font-medium shadow-xs">
          <span class="w-1.5 h-1.5 rounded-full bg-emerald-400"></span>
          <span>Auto-save active</span>
        </div>
      {/if}
    </div>
  </header>

  <!-- SECTION 1: PRIMARY LANGUAGE AURA & THEME -->
  <section class="relative p-6 rounded-3xl border border-[var(--border-card)] bg-[var(--bg-surface)]/85 shadow-sm space-y-5 backdrop-blur-xl z-10 overflow-hidden">
    <div class="flex items-center justify-between border-b border-[var(--border-subtle)] pb-4">
      <div class="flex items-center gap-2.5">
        <div 
          class="w-8 h-8 rounded-xl flex items-center justify-center border shadow-xs"
          style="background-color: {currentThemeColor}15; border-color: {currentThemeColor}35; color: {currentThemeColor};"
        >
          <Sparkles size={16} strokeWidth={2.5} />
        </div>
        <div>
          <h2 class="text-xs font-black uppercase tracking-wider text-[var(--text-primary)]">
            Language Theme & Aura
          </h2>
          <p class="text-[11px] text-[var(--text-muted)]">
            Instantly tunes the ambient glow, graph trajectories, and header accents for this language
          </p>
        </div>
      </div>

      <!-- Live Color Picker -->
      <div class="relative flex items-center gap-2">
        <label 
          for="primary-theme-picker" 
          class="flex items-center gap-2 px-3 py-1.5 rounded-xl bg-[var(--bg-base)] border border-[var(--border-card)] cursor-pointer hover:border-[var(--border-hover)] transition-all shadow-xs"
        >
          <span 
            class="w-3.5 h-3.5 rounded-full shadow-sm"
            style="background-color: {currentThemeColor}; box-shadow: 0 0 8px {currentThemeColor};"
          ></span>
          <span class="font-mono text-xs font-bold uppercase" style="color: {currentThemeColor};">
            {currentThemeColor}
          </span>
        </label>
        <input
          id="primary-theme-picker"
          type="color"
          value={currentThemeColor}
          oninput={(e) => {
            if (!colors.theme) colors.theme = {};
            colors.theme.dark_primary = e.target.value;
            colors.theme.light_primary = e.target.value;
            triggerAutoSave(true);
          }}
          class="absolute inset-0 opacity-0 cursor-pointer w-full h-full"
        />
      </div>
    </div>

    <!-- Quick Preset Swatches -->
    <div class="space-y-2">
      <span class="text-[10px] font-mono font-bold uppercase tracking-wider text-[var(--text-muted)] block">
        Quick Palette Presets
      </span>
      <div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-2.5">
        {#each THEME_PRESETS as preset}
          {@const isSelected = currentThemeColor.toLowerCase() === preset.hex.toLowerCase()}
          <button
            type="button"
            onclick={() => setThemePreset(preset.hex)}
            class="group flex items-center gap-2 p-2 rounded-xl bg-[var(--bg-base)] border transition-all duration-150 cursor-pointer active:scale-95 text-left {isSelected 
              ? 'border-[var(--text-primary)] shadow-sm' 
              : 'border-[var(--border-card)] hover:border-[var(--border-hover)]'}"
          >
            <span 
              class="w-4 h-4 rounded-lg shrink-0 transition-transform group-hover:scale-110"
              style="background-color: {preset.hex}; box-shadow: {isSelected ? `0 0 10px ${preset.hex}` : 'none'};"
            ></span>
            <span class="text-[11px] font-bold truncate text-[var(--text-primary)]">
              {preset.name}
            </span>
          </button>
        {/each}
      </div>
    </div>
  </section>

  <!-- SECTION 2: DAILY HABIT TARGETS -->
  <section class="relative p-6 rounded-3xl border border-[var(--border-card)] bg-[var(--bg-surface)]/85 shadow-sm space-y-4 backdrop-blur-xl z-10">
    <div class="flex items-center gap-2.5 border-b border-[var(--border-subtle)] pb-4">
      <div class="w-8 h-8 rounded-xl bg-indigo-500/15 border border-indigo-500/30 flex items-center justify-center text-indigo-400">
        <Target size={16} strokeWidth={2.5} />
      </div>
      <div>
        <h2 class="text-xs font-black uppercase tracking-wider text-[var(--text-primary)]">
          Daily Activity Targets
        </h2>
        <p class="text-[11px] text-[var(--text-muted)]">
          Calibrates the 5 concentric Apple-style fitness rings on your today cockpit
        </p>
      </div>
    </div>

    <div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-3 pt-1">
      
      <!-- Vocab -->
      <div class="p-3.5 rounded-2xl bg-[var(--bg-base)] border border-[var(--border-card)] space-y-1.5 focus-within:border-emerald-500 transition-colors">
        <label for="goal-vocab" class="block text-[10px] font-mono font-bold uppercase tracking-wider text-[var(--text-muted)]">
          Vocab Goal
        </label>
        <div class="flex items-baseline gap-1">
          <input 
            id="goal-vocab" 
            type="number" 
            min="1"
            bind:value={goals.vocab}
            oninput={() => triggerAutoSave()} 
            class="w-full bg-transparent text-lg font-black font-mono text-[var(--text-primary)] outline-none" 
          />
          <span class="text-xs font-mono font-bold text-[var(--text-muted)]">words</span>
        </div>
      </div>

      <!-- Listening -->
      <div class="p-3.5 rounded-2xl bg-[var(--bg-base)] border border-[var(--border-card)] space-y-1.5 focus-within:border-orange-500 transition-colors">
        <label for="goal-listening" class="block text-[10px] font-mono font-bold uppercase tracking-wider text-[var(--text-muted)]">
          Listening
        </label>
        <div class="flex items-baseline gap-1">
          <input 
            id="goal-listening" 
            type="number" 
            min="1"
            bind:value={goals.listening_minutes}
            oninput={() => triggerAutoSave()} 
            class="w-full bg-transparent text-lg font-black font-mono text-[var(--text-primary)] outline-none" 
          />
          <span class="text-xs font-mono font-bold text-[var(--text-muted)]">mins</span>
        </div>
      </div>

      <!-- Speaking -->
      <div class="p-3.5 rounded-2xl bg-[var(--bg-base)] border border-[var(--border-card)] space-y-1.5 focus-within:border-pink-500 transition-colors">
        <label for="goal-speaking" class="block text-[10px] font-mono font-bold uppercase tracking-wider text-[var(--text-muted)]">
          Speaking
        </label>
        <div class="flex items-baseline gap-1">
          <input 
            id="goal-speaking" 
            type="number" 
            min="1"
            bind:value={goals.speaking_minutes}
            oninput={() => triggerAutoSave()} 
            class="w-full bg-transparent text-lg font-black font-mono text-[var(--text-primary)] outline-none" 
          />
          <span class="text-xs font-mono font-bold text-[var(--text-muted)]">mins</span>
        </div>
      </div>

      <!-- CI Target -->
      <div class="p-3.5 rounded-2xl bg-[var(--bg-base)] border border-[var(--border-card)] space-y-1.5 focus-within:border-purple-500 transition-colors">
        <label for="goal-ci" class="block text-[10px] font-mono font-bold uppercase tracking-wider text-[var(--text-muted)]">
          CI Videos
        </label>
        <div class="flex items-baseline gap-1">
          <input 
            id="goal-ci" 
            type="number" 
            min="1"
            bind:value={goals.ci}
            oninput={() => triggerAutoSave()} 
            class="w-full bg-transparent text-lg font-black font-mono text-[var(--text-primary)] outline-none" 
          />
          <span class="text-xs font-mono font-bold text-[var(--text-muted)]">vids</span>
        </div>
      </div>

      <!-- Grammar -->
      <div class="p-3.5 rounded-2xl bg-[var(--bg-base)] border border-[var(--border-card)] space-y-1.5 focus-within:border-sky-500 transition-colors">
        <label for="goal-grammar" class="block text-[10px] font-mono font-bold uppercase tracking-wider text-[var(--text-muted)]">
          Grammar
        </label>
        <div class="flex items-baseline gap-1">
          <input 
            id="goal-grammar" 
            type="number" 
            min="1"
            bind:value={goals.grammar}
            oninput={() => triggerAutoSave()} 
            class="w-full bg-transparent text-lg font-black font-mono text-[var(--text-primary)] outline-none" 
          />
          <span class="text-xs font-mono font-bold text-[var(--text-muted)]">pts</span>
        </div>
      </div>

    </div>
  </section>

  <!-- SECTION 3: SKILL CATEGORY PALETTE -->
  {#if colors && Object.keys(colors).length > 0}
    <section class="relative p-6 rounded-3xl border border-[var(--border-card)] bg-[var(--bg-surface)]/85 shadow-sm space-y-4 backdrop-blur-xl z-10">
      <div class="flex items-center gap-2.5 border-b border-[var(--border-subtle)] pb-4">
        <div class="w-8 h-8 rounded-xl bg-emerald-500/15 border border-emerald-500/30 flex items-center justify-center text-emerald-400">
          <Palette size={16} strokeWidth={2.5} />
        </div>
        <div>
          <h2 class="text-xs font-black uppercase tracking-wider text-[var(--text-primary)]">
            Skill Track Accent Hues
          </h2>
          <p class="text-[11px] text-[var(--text-muted)]">
            Individual colors applied to habit cards, charts, and progress badges
          </p>
        </div>
      </div>

      <div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-3 pt-1">
        {#each Object.keys(colors).filter(k => k !== 'theme') as category}
          {@const colorVal = colors[category]?.dark_primary || '#64748b'}
          <div class="relative flex items-center justify-between p-3 rounded-2xl bg-[var(--bg-base)] border border-[var(--border-card)] hover:border-[var(--border-hover)] transition-all overflow-hidden group">
            
            <div class="space-y-0.5 min-w-0 pr-2">
              <span class="text-xs font-bold capitalize text-[var(--text-primary)] block truncate">
                {category}
              </span>
              <span class="text-[10px] font-mono uppercase text-[var(--text-muted)] block">
                {colorVal}
              </span>
            </div>

            <label 
              for={`color-${category}`} 
              class="relative w-7 h-7 rounded-xl border border-white/10 shrink-0 cursor-pointer shadow-sm group-hover:scale-105 transition-transform"
              style="background-color: {colorVal}; box-shadow: 0 0 10px {colorVal}60;"
            >
              <input
                id={`color-${category}`}
                type="color"
                value={colorVal}
                oninput={(e) => {
                  if (!colors[category]) colors[category] = {};
                  colors[category].dark_primary = e.target.value;
                  colors[category].light_primary = e.target.value;
                  triggerAutoSave(true);
                }}
                class="absolute inset-0 opacity-0 cursor-pointer w-full h-full"
              />
            </label>
          </div>
        {/each}
      </div>
    </section>
  {/if}

  <!-- SECTION 4: TONE / PITCH ACCENT PALETTE -->
  {#if tones && Object.keys(tones).length > 0}
    <section class="relative p-6 rounded-3xl border border-[var(--border-card)] bg-[var(--bg-surface)]/85 shadow-sm space-y-4 backdrop-blur-xl z-10">
      <div class="flex items-center gap-2.5 border-b border-[var(--border-subtle)] pb-4">
        <div class="w-8 h-8 rounded-xl bg-pink-500/15 border border-pink-500/30 flex items-center justify-center text-pink-400">
          <Music size={16} strokeWidth={2.5} />
        </div>
        <div>
          <h2 class="text-xs font-black uppercase tracking-wider text-[var(--text-primary)]">
            Phonetic Tone Colors
          </h2>
          <p class="text-[11px] text-[var(--text-muted)]">
            Used to colorize Chinese Pinyin / Kanji diacritics in vocabulary streams and flashcards
          </p>
        </div>
      </div>

      <div class="grid grid-cols-2 sm:grid-cols-5 gap-3 pt-1">
        {#each Object.keys(tones) as toneNum}
          {@const toneVal = tones[toneNum] || '#64748b'}
          <div class="relative flex flex-col items-center justify-between p-3.5 rounded-2xl bg-[var(--bg-base)] border border-[var(--border-card)] text-center space-y-2 group hover:border-[var(--border-hover)] transition-all">
            <span class="text-xs font-mono font-black text-[var(--text-primary)]">
              Tone {toneNum}
            </span>

            <label 
              for={`tone-${toneNum}`}
              class="relative w-8 h-8 rounded-xl border border-white/10 shrink-0 cursor-pointer shadow-sm group-hover:scale-110 transition-transform"
              style="background-color: {toneVal}; box-shadow: 0 0 10px {toneVal}60;"
            >
              <input
                id={`tone-${toneNum}`}
                type="color"
                value={toneVal}
                oninput={(e) => {
                  tones[toneNum] = e.target.value;
                  triggerAutoSave(true);
                }}
                class="absolute inset-0 opacity-0 cursor-pointer w-full h-full"
              />
            </label>

            <span class="text-[10px] font-mono text-[var(--text-muted)] uppercase">
              {toneVal}
            </span>
          </div>
        {/each}
      </div>
    </section>
  {/if}

  <!-- SECTION 5: STUDY REMINDERS & NOTIFICATIONS -->
  <section class="relative p-6 rounded-3xl border border-[var(--border-card)] bg-[var(--bg-surface)]/85 shadow-sm space-y-4 backdrop-blur-xl z-10">
    <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-4 border-b border-[var(--border-subtle)] pb-4">
      <div class="flex items-center gap-2.5">
        <div class="w-8 h-8 rounded-xl bg-amber-500/15 border border-amber-500/30 flex items-center justify-center text-amber-400">
          <Bell size={16} strokeWidth={2.5} />
        </div>
        <div>
          <h2 class="text-xs font-black uppercase tracking-wider text-[var(--text-primary)]">
            Study Reminders & WebPush
          </h2>
          <p class="text-[11px] text-[var(--text-muted)]">
            Browser notifications and native closed-app reminders
          </p>
        </div>
      </div>

      <div class="flex items-center gap-3">
        {#if notifStatusMsg}
          <span class="text-xs font-mono font-bold {isPushEnabled ? 'text-emerald-400' : 'text-amber-400'}">
            {notifStatusMsg}
          </span>
        {/if}

        <button
          type="button"
          onclick={handleToggleNotifications}
          disabled={isTogglingNotif}
          class="px-4 py-2 rounded-2xl text-xs font-bold transition-all cursor-pointer shadow-xs active:scale-95 disabled:opacity-50 {isPushEnabled
            ? 'bg-rose-500/15 border border-rose-500/30 text-rose-400 hover:bg-rose-500/25'
            : 'bg-[var(--text-primary)] text-[var(--bg-base)] hover:opacity-90'}"
        >
          {isTogglingNotif ? 'Syncing...' : isPushEnabled ? 'Disable Reminders' : 'Enable WebPush'}
        </button>
      </div>
    </div>

    {#if isPushEnabled}
      <div class="flex flex-wrap items-center justify-between gap-3 pt-2">
        <div class="flex items-center gap-2.5">
          <Clock size={15} class="text-[var(--text-muted)]" />
          <label for="reminder-time" class="text-xs font-semibold text-[var(--text-muted)]">Evening Nudge:</label>
          <select
            id="reminder-time"
            bind:value={reminderHour}
            onchange={() => {
              notificationService.stopScheduler();
              notificationService.startScheduler(reminderHour);
            }}
            class="px-3 py-1.5 rounded-xl text-xs font-mono font-bold bg-[var(--bg-base)] border border-[var(--border-card)] text-[var(--text-primary)] outline-none cursor-pointer"
          >
            <option value={17}>5:00 PM</option>
            <option value={18}>6:00 PM</option>
            <option value={19}>7:00 PM (Default)</option>
            <option value={20}>8:00 PM</option>
            <option value={21}>9:00 PM</option>
            <option value={22}>10:00 PM</option>
          </select>
        </div>

        <button
          type="button"
          onclick={handleTestNotification}
          class="inline-flex items-center gap-1.5 text-xs font-semibold text-[var(--text-secondary)] hover:text-[var(--text-primary)] cursor-pointer transition-colors"
        >
          <Zap size={13} class="text-amber-400" />
          <span>Send Test Alert</span>
        </button>
      </div>
    {/if}
  </section>

  <!-- SECTION 6: SNAPSHOTS & BACKUP -->
  <section class="relative p-6 rounded-3xl border border-[var(--border-card)] bg-[var(--bg-surface)]/85 shadow-sm space-y-4 backdrop-blur-xl z-10">
    <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
      <div class="flex items-center gap-2.5">
        <div class="w-8 h-8 rounded-xl bg-sky-500/15 border border-sky-500/30 flex items-center justify-center text-sky-400">
          <Database size={16} strokeWidth={2.5} />
        </div>
        <div>
          <h2 class="text-xs font-black uppercase tracking-wider text-[var(--text-primary)]">
            Data Snapshots & Vault
          </h2>
          <p class="text-[11px] text-[var(--text-muted)] max-w-md">
            Project active Yjs CRDT room memory into a compressed SQLite archive on your disk
          </p>
        </div>
      </div>

      <div class="flex items-center gap-3">
        {#if backupStatus}
          <span class="text-xs font-mono font-bold text-emerald-400">{backupStatus}</span>
        {/if}

        <button
          type="button"
          onclick={handleManualBackup}
          disabled={isBackingUp}
          class="inline-flex items-center gap-2 px-4 py-2.5 rounded-2xl border border-[var(--border-card)] bg-[var(--bg-base)] text-[var(--text-primary)] hover:border-emerald-500/50 hover:bg-[var(--bg-surface-elevated)] text-xs font-bold transition-all cursor-pointer shadow-xs active:scale-95 disabled:opacity-50"
        >
          <RefreshCw size={13} class={isBackingUp ? 'animate-spin' : ''} />
          <span>{isBackingUp ? 'Projecting Archive...' : 'Create Snapshot Now'}</span>
        </button>
      </div>
    </div>
  </section>

</div>