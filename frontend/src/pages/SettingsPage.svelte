<script>
  import { untrack } from 'svelte';
  import { metadataStore } from '../lib/stores/metadata.svelte.js';
  import { notificationService } from '../lib/services/notificationService.js';

  let currentLang = $derived(metadataStore.languages[metadataStore.activeLanguage] || {});

  let goals = $state({
    vocab: 10,
    ci: 1,
    grammar: 1,
    listening_minutes: 45,
    speaking_minutes: 10
  });

  let colors = $state({});
  let tones = $state({});
  let saveStatus = $state('');

  // Notification UI states
  let isPushEnabled = $state(notificationService.isEnabled);
  let notifStatusMsg = $state('');
  let isTogglingNotif = $state(false);
  let reminderHour = $state(19);

  // Backup trigger state
  let isBackingUp = $state(false);
  let backupStatus = $state('');

  // Sync form inputs only when the language or store data updates,
  // without creating a self-triggering dependency cycle on local states
  $effect(() => {
    const lang = currentLang;

    untrack(() => {
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
      if (lang.tones) {
        tones = JSON.parse(JSON.stringify(lang.tones));
      }
    });
  });

  function handleSave() {
    metadataStore.updateLanguageConfig(metadataStore.activeLanguage, {
      goals,
      colors,
      tones
    });
    saveStatus = 'Saved!';
    setTimeout(() => (saveStatus = ''), 2000);
  }

  async function handleToggleNotifications() {
    isTogglingNotif = true;
    notifStatusMsg = '';

    if (isPushEnabled) {
      // Turn Off: Unsubscribe PushManager token and set push_enabled to false
      await notificationService.unsubscribeFromWebPush();
      isPushEnabled = false;
      notifStatusMsg = 'Notifications disabled.';
    } else {
      // Turn On: Request browser permission first
      if (Notification.permission !== 'granted') {
        const perm = await Notification.requestPermission();
        if (perm !== 'granted') {
          notifStatusMsg = 'Permission denied in browser settings.';
          isTogglingNotif = false;
          return;
        }
      }

      notifStatusMsg = 'Connecting to backend...';
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
    backupStatus = 'Projecting...';
    try {
      const res = await fetch('/api/backup/now', { method: 'POST' });
      const data = await res.json();
      if (res.ok) {
        backupStatus = `Saved: ${data.file || 'backup.db.gz'}`;
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

<div class="w-full max-w-md lg:max-w-4xl xl:max-w-5xl mx-auto space-y-6 pt-2 pb-24 px-1 lg:px-4">
  <!-- Top Bar -->
  <div class="flex items-center justify-between border-b border-[var(--border-card)] pb-4">
    <div>
      <h1 class="text-xl font-bold text-[var(--text-primary)]">
        {currentLang.name || 'Language'} Configuration
      </h1>
      <p class="text-xs font-mono text-[var(--text-muted)]">{metadataStore.activeLanguage}</p>
    </div>
    <div class="flex items-center gap-2">
      {#if saveStatus}
        <span class="text-xs font-bold text-emerald-500">{saveStatus}</span>
      {/if}
      <button
        type="button"
        onclick={handleSave}
        class="px-4 py-1.5 rounded-xl bg-emerald-600 hover:bg-emerald-500 text-xs font-bold text-white transition-all cursor-pointer shadow-xs"
      >
        Save Changes
      </button>
    </div>
  </div>

  <!-- Study Reminders & Push Section -->
  <section class="space-y-3 p-4 rounded-2xl bg-[var(--bg-surface)] border border-[var(--border-card)]">
    <div class="flex items-center justify-between">
      <div>
        <h2 class="text-xs font-mono uppercase tracking-wider font-bold text-[var(--text-primary)]">
          🔔 Study Reminders & WebPush
        </h2>
        <p class="text-[11px] text-[var(--text-muted)]">
          Native alerts & closed-app push reminders
        </p>
      </div>

      <div class="flex items-center gap-2">
        {#if notifStatusMsg}
          <span class="text-[11px] font-mono font-semibold {isPushEnabled ? 'text-emerald-500' : 'text-amber-500'}">
            {notifStatusMsg}
          </span>
        {/if}

        <button
          type="button"
          onclick={handleToggleNotifications}
          disabled={isTogglingNotif}
          class="px-3.5 py-1.5 rounded-xl text-xs font-bold transition-all cursor-pointer shadow-xs disabled:opacity-50 {isPushEnabled
            ? 'bg-rose-500/15 border border-rose-500/30 text-rose-400 hover:bg-rose-500/25'
            : 'bg-[var(--text-primary)] text-[var(--bg-base)] hover:opacity-90'}"
        >
          {isTogglingNotif ? 'Working...' : isPushEnabled ? 'Disable' : 'Enable Reminders'}
        </button>
      </div>
    </div>

    {#if isPushEnabled}
      <div class="pt-3 border-t border-[var(--border-card)] flex flex-wrap items-center justify-between gap-3">
        <div class="flex items-center gap-2">
          <label for="reminder-time" class="text-xs text-[var(--text-muted)]">Evening Nudge Time:</label>
          <select
            id="reminder-time"
            bind:value={reminderHour}
            onchange={() => {
              notificationService.stopScheduler();
              notificationService.startScheduler(reminderHour);
            }}
            class="px-2 py-1 rounded-lg text-xs bg-[var(--bg-base)] border border-[var(--border-card)] text-[var(--text-primary)] outline-none cursor-pointer"
          >
            <option value={17}>5:00 PM</option>
            <option value={18}>6:00 PM</option>
            <option value={19}>7:00 PM</option>
            <option value={20}>8:00 PM</option>
            <option value={21}>9:00 PM</option>
            <option value={22}>10:00 PM</option>
          </select>
        </div>

        <button
          type="button"
          onclick={handleTestNotification}
          class="text-xs font-medium text-[var(--text-muted)] hover:text-[var(--text-primary)] underline cursor-pointer"
        >
          Send Test Alert
        </button>
      </div>
    {/if}
  </section>

  <!-- Database & Backup Section -->
  <section class="space-y-3 p-4 rounded-2xl bg-[var(--bg-surface)] border border-[var(--border-card)]">
    <div class="flex items-center justify-between">
      <div>
        <h2 class="text-xs font-mono uppercase tracking-wider font-bold text-[var(--text-primary)]">
          💾 Data Snapshot & Backup
        </h2>
        <p class="text-[11px] text-[var(--text-muted)]">
          Nightly snapshot runs at 03:00 AM. Project live CRDT rooms into a verified, gzipped relational database now.
        </p>
      </div>

      <div class="flex items-center gap-2">
        {#if backupStatus}
          <span class="text-xs font-mono font-semibold text-emerald-500">{backupStatus}</span>
        {/if}
        <button
          type="button"
          onclick={handleManualBackup}
          disabled={isBackingUp}
          class="px-3.5 py-1.5 rounded-xl border border-[var(--border-card)] bg-[var(--bg-base)] text-[var(--text-primary)] hover:border-emerald-500 text-xs font-bold transition-all cursor-pointer shadow-xs disabled:opacity-50"
        >
          {isBackingUp ? 'Processing...' : 'Run Backup Now'}
        </button>
      </div>
    </div>
  </section>

  <!-- Daily Goals Section -->
  <section class="space-y-3 p-4 rounded-2xl bg-[var(--bg-surface)] border border-[var(--border-card)]">
    <h2 class="text-xs font-mono uppercase tracking-wider font-bold text-[var(--text-muted)]">
      🎯 Daily Targets
    </h2>
    <div class="grid grid-cols-2 sm:grid-cols-4 gap-3">
      <div>
        <label for="goal-vocab" class="block text-[11px] text-[var(--text-muted)] mb-1 cursor-pointer">Vocab Goal</label>
        <input 
          id="goal-vocab" 
          type="number" 
          bind:value={goals.vocab} 
          class="w-full px-3 py-1.5 rounded-xl text-xs bg-[var(--bg-base)] border border-[var(--border-card)] text-[var(--text-primary)]" 
        />
      </div>
      <div>
        <label for="goal-ci" class="block text-[11px] text-[var(--text-muted)] mb-1 cursor-pointer">CI Target</label>
        <input 
          id="goal-ci" 
          type="number" 
          bind:value={goals.ci} 
          class="w-full px-3 py-1.5 rounded-xl text-xs bg-[var(--bg-base)] border border-[var(--border-card)] text-[var(--text-primary)]" 
        />
      </div>
      <div>
        <label for="goal-listening" class="block text-[11px] text-[var(--text-muted)] mb-1 cursor-pointer">Listening (mins)</label>
        <input 
          id="goal-listening" 
          type="number" 
          bind:value={goals.listening_minutes} 
          class="w-full px-3 py-1.5 rounded-xl text-xs bg-[var(--bg-base)] border border-[var(--border-card)] text-[var(--text-primary)]" 
        />
      </div>
      <div>
        <label for="goal-speaking" class="block text-[11px] text-[var(--text-muted)] mb-1 cursor-pointer">Speaking (mins)</label>
        <input 
          id="goal-speaking" 
          type="number" 
          bind:value={goals.speaking_minutes} 
          class="w-full px-3 py-1.5 rounded-xl text-xs bg-[var(--bg-base)] border border-[var(--border-card)] text-[var(--text-primary)]" 
        />
      </div>
    </div>
  </section>

  <!-- Color Themes Section -->
  {#if Object.keys(colors).length > 0}
    <section class="space-y-3 p-4 rounded-2xl bg-[var(--bg-surface)] border border-[var(--border-card)]">
      <h2 class="text-xs font-mono uppercase tracking-wider font-bold text-[var(--text-muted)]">
        🎨 Theme Colors
      </h2>
      <div class="grid grid-cols-2 sm:grid-cols-3 gap-3">
        {#each Object.keys(colors) as category}
          {@const colorId = `color-${category}`}
          <div class="flex items-center justify-between p-2 rounded-xl bg-[var(--bg-base)] border border-[var(--border-card)]">
            <label for={colorId} class="text-xs capitalize cursor-pointer text-[var(--text-primary)]">{category}</label>
            <input
              id={colorId}
              type="color"
              bind:value={colors[category].dark_primary}
              class="w-6 h-6 rounded cursor-pointer border-none bg-transparent"
            />
          </div>
        {/each}
      </div>
    </section>
  {/if}

  <!-- Pitch / Tone Colors Section -->
  {#if Object.keys(tones).length > 0}
    <section class="space-y-3 p-4 rounded-2xl bg-[var(--bg-surface)] border border-[var(--border-card)]">
      <h2 class="text-xs font-mono uppercase tracking-wider font-bold text-[var(--text-muted)]">
        🎵 Tone / Pitch Accent Colors
      </h2>
      <div class="grid grid-cols-5 gap-2">
        {#each Object.keys(tones) as toneNum}
          {@const toneId = `tone-${toneNum}`}
          <div class="flex flex-col items-center gap-1.5 p-2 rounded-xl bg-[var(--bg-base)] border border-[var(--border-card)] text-center">
            <label for={toneId} class="text-[10px] font-mono font-bold cursor-pointer text-[var(--text-primary)]">Tone {toneNum}</label>
            <input
              id={toneId}
              type="color"
              bind:value={tones[toneNum]}
              class="w-6 h-6 rounded cursor-pointer border-none bg-transparent"
            />
          </div>
        {/each}
      </div>
    </section>
  {/if}
</div>