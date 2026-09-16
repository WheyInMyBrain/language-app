<script>
  import { metadataStore } from '../lib/stores/metadata.svelte.js';
  import { guessLanguageCode, getDefaultConfig } from '../lib/utils/languageCode.js';

  let { onSelectLanguage } = $props();
  let languageList = $derived(Object.values(metadataStore.languages));

  let isModalOpen = $state(false);
  let nameInput = $state('');
  let codeInput = $state('');
  let isCustomCode = $state(false);

  function handleNameChange(e) {
    nameInput = e.target.value;
    if (!isCustomCode) {
      codeInput = guessLanguageCode(nameInput);
    }
  }

  function handleCreateLanguage(e) {
    e.preventDefault();
    const cleanName = nameInput.trim();
    const cleanCode = codeInput.trim() || guessLanguageCode(cleanName);

    if (!cleanName || !cleanCode) return;

    const newConfig = getDefaultConfig(cleanCode, cleanName);
    metadataStore.addLanguage(newConfig);

    isModalOpen = false;
    nameInput = '';
    codeInput = '';
    isCustomCode = false;

    onSelectLanguage(cleanCode);
  }
</script>

<div class="max-w-md mx-auto pt-6 pb-4 px-1 space-y-6">
  <div class="flex items-center justify-between">
    <h1 class="text-2xl font-bold tracking-tight text-[var(--text-primary)]">
      Select Language
    </h1>
    <button
      type="button"
      onclick={() => (isModalOpen = true)}
      class="px-3 py-1.5 rounded-xl border border-[var(--border-card)] bg-[var(--bg-surface)] hover:bg-[var(--bg-surface-active)] text-xs font-bold flex items-center gap-1.5 transition-all active:scale-95 cursor-pointer shadow-xs"
    >
      <span>➕</span>
      <span>Add Language</span>
    </button>
  </div>

  {#if languageList.length === 0}
    <div class="py-12 px-6 rounded-2xl border border-dashed border-[var(--border-card)] text-center text-[var(--text-muted)] text-sm space-y-3">
      <p>No languages registered yet.</p>
      <button
        type="button"
        onclick={() => (isModalOpen = true)}
        class="px-4 py-2 rounded-xl bg-emerald-600 text-white font-bold text-xs cursor-pointer"
      >
        Create Your First Language
      </button>
    </div>
  {:else}
    <div class="space-y-3">
      {#each languageList as lang (lang.code)}
        <button
          type="button"
          onclick={() => onSelectLanguage(lang.code)}
          class="w-full rounded-2xl border border-[var(--border-card)] bg-[var(--bg-surface)] py-4 px-6 text-center shadow-xs transition-transform duration-75 active:scale-[0.97] active:bg-[var(--bg-surface-active)] [@media(hover:hover)]:hover:-translate-y-0.5 [@media(hover:hover)]:hover:border-[var(--border-hover)] flex items-center justify-between cursor-pointer"
        >
          <div class="text-left">
            <span class="text-base font-semibold tracking-wide text-[var(--text-primary)] block">
              {lang.name}
            </span>
            <span class="text-[10px] font-mono text-[var(--text-muted)] uppercase tracking-wider">
              {lang.code}
            </span>
          </div>
          <span class="text-xs font-mono font-bold text-[var(--text-muted)]">
            🔥 {lang.current_streak || 0}d
          </span>
        </button>
      {/each}
    </div>
  {/if}
</div>

{#if isModalOpen}
  <div class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-xs">
    <div class="w-full max-w-sm rounded-2xl bg-[var(--bg-surface)] border border-[var(--border-card)] p-5 shadow-2xl space-y-4">
      <div class="flex items-center justify-between">
        <h2 class="text-sm font-black text-[var(--text-primary)]">Add New Target Language</h2>
        <button 
          type="button" 
          onclick={() => (isModalOpen = false)} 
          class="text-xs text-[var(--text-muted)] hover:text-white cursor-pointer"
        >
          ✕
        </button>
      </div>

      <form onsubmit={handleCreateLanguage} class="space-y-3.5">
        <div>
          <label 
            for="lang-name-input" 
            class="block text-[11px] font-bold text-[var(--text-muted)] uppercase tracking-wider mb-1 cursor-pointer"
          >
            Language Name
          </label>
          <input
            id="lang-name-input"
            type="text"
            placeholder="e.g. Japanese, German, Spanish"
            value={nameInput}
            oninput={handleNameChange}
            required
            class="w-full px-3 py-2 rounded-xl text-xs bg-[var(--bg-base)] border border-[var(--border-card)] text-[var(--text-primary)] outline-none focus:border-emerald-500 font-medium"
          />
        </div>

        <div>
          <div class="flex items-center justify-between mb-1">
            <label 
              for="lang-code-input" 
              class="text-[11px] font-bold text-[var(--text-muted)] uppercase tracking-wider cursor-pointer"
            >
              Language Code (BCP 47)
            </label>
            <span class="text-[10px] text-emerald-500 font-mono">auto-detected</span>
          </div>
          <input
            id="lang-code-input"
            type="text"
            placeholder="e.g. ja, de, es"
            bind:value={codeInput}
            oninput={() => (isCustomCode = true)}
            required
            class="w-full px-3 py-2 rounded-xl text-xs font-mono bg-[var(--bg-base)] border border-[var(--border-card)] text-[var(--text-primary)] outline-none focus:border-emerald-500"
          />
        </div>

        <div class="flex items-center justify-end gap-2 pt-2">
          <button
            type="button"
            onclick={() => (isModalOpen = false)}
            class="px-3 py-1.5 rounded-xl border border-[var(--border-card)] text-xs font-semibold text-[var(--text-muted)] hover:bg-[var(--bg-surface-active)] cursor-pointer"
          >
            Cancel
          </button>
          <button
            type="submit"
            class="px-4 py-1.5 rounded-xl bg-emerald-600 hover:bg-emerald-500 text-xs font-bold text-white transition-all shadow-xs cursor-pointer"
          >
            Create Language
          </button>
        </div>
      </form>
    </div>
  </div>
{/if}