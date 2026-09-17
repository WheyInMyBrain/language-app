<script>
  import { metadataStore } from '../lib/stores/metadata.svelte.js';

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

  // Re-sync local form states whenever active language or metadata hydrates/changes
  $effect(() => {
    if (currentLang.goals) {
      goals = { ...goals, ...currentLang.goals };
    }
    if (currentLang.colors) {
      colors = JSON.parse(JSON.stringify(currentLang.colors));
    }
    if (currentLang.tones) {
      tones = JSON.parse(JSON.stringify(currentLang.tones));
    }
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
</script>

<div class="w-full max-w-md lg:max-w-4xl xl:max-w-5xl mx-auto space-y-8 pt-2 pb-24 px-1 lg:px-4">
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

  <!-- Daily Goals Section -->
  <section class="space-y-3 p-4 rounded-2xl bg-[var(--bg-surface)] border border-[var(--border-card)]">
    <h2 class="text-xs font-mono uppercase tracking-wider font-bold text-[var(--text-muted)]">
      🎯 Daily Targets
    </h2>
    <div class="grid grid-cols-2 gap-3">
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