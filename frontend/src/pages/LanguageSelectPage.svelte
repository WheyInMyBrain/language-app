<!-- frontend/src/pages/LanguageSelectPage.svelte -->
<script>
  import { metadataStore } from '../lib/stores/metadata.svelte.js';
  import { guessLanguageCode, getDefaultConfig } from '../lib/utils/languageCode.js';

  // Razor-sharp vector icons
  import { 
    Globe, 
    Plus, 
    Sparkles, 
    Flame, 
    ArrowRight, 
    X, 
    Languages, 
    CheckCircle2,
    Compass
  } from '@lucide/svelte';

  let { onSelectLanguage } = $props();
  let languageList = $derived(Object.values(metadataStore.languages || {}));

  let isModalOpen = $state(false);
  let nameInput = $state('');
  let codeInput = $state('');
  let isCustomCode = $state(false);

  function getLanguageColor(lang) {
    return (
      lang.colors?.theme?.dark_primary || 
      lang.colors?.vocab?.dark_primary || 
      lang.colors?.theme?.light_primary || 
      '#a855f7'
    );
  }

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

  function handleKeydown(e) {
    if (e.key === 'Escape' && isModalOpen) {
      isModalOpen = false;
    }
  }
</script>

<svelte:window onkeydown={handleKeydown} />

<div class="relative w-full max-w-6xl mx-auto space-y-10 pt-6 pb-28 px-3 sm:px-6 select-none">
  
  <!-- Subtle Ambient Workspace Lights -->
  <div class="pointer-events-none absolute -top-24 left-1/4 w-[500px] h-[300px] bg-purple-500/10 blur-[130px] rounded-full"></div>
  <div class="pointer-events-none absolute top-1/2 -right-24 w-[400px] h-[350px] bg-indigo-500/8 blur-[140px] rounded-full"></div>

  <!-- HEADER HERO BAR -->
  <header class="relative flex flex-col sm:flex-row sm:items-end justify-between gap-5 pb-6 border-b border-[var(--border-subtle)] z-10">
    <div class="space-y-1.5">
      <div class="inline-flex items-center gap-2 px-2.5 py-1 rounded-full bg-[var(--bg-surface)] border border-[var(--border-subtle)] shadow-xs">
        <Sparkles size={12} class="text-purple-400" />
        <span class="text-[10px] font-mono font-bold uppercase tracking-wider text-[var(--text-muted)]">
          Target Language Selection
        </span>
      </div>
      <h1 class="text-3xl sm:text-4xl font-black tracking-tight text-[var(--text-primary)]">
        Choose Workspace
      </h1>
      <p class="text-xs sm:text-sm text-[var(--text-muted)] font-medium max-w-md leading-relaxed">
        Select a configured target track to continue your habit pulse, or initialize a brand new language arena.
      </p>
    </div>

    <!-- Add Language Trigger Pill -->
    <button
      type="button"
      onclick={() => (isModalOpen = true)}
      class="group self-start sm:self-auto inline-flex items-center gap-2.5 px-4 py-2.5 rounded-2xl border border-[var(--border-card)] bg-[var(--bg-surface)]/90 hover:bg-[var(--bg-surface-elevated)] hover:border-purple-500/50 text-xs font-bold text-[var(--text-primary)] transition-all duration-200 active:scale-[0.98] cursor-pointer shadow-xs hover:shadow-[0_0_20px_rgba(168,85,247,0.2)] backdrop-blur-md"
    >
      <div class="w-6 h-6 rounded-xl bg-purple-500/15 border border-purple-500/30 flex items-center justify-center text-purple-400 transition-transform duration-200 group-hover:rotate-90">
        <Plus size={14} strokeWidth={2.5} />
      </div>
      <span>Add Target Language</span>
    </button>
  </header>

  <!-- EMPTY STATE STUDIO -->
  {#if languageList.length === 0}
    <div class="relative py-20 px-8 rounded-3xl border border-dashed border-[var(--border-card)] bg-[var(--bg-surface)]/40 backdrop-blur-xl text-center space-y-5 max-w-lg mx-auto shadow-sm overflow-hidden z-10">
      <div class="relative w-16 h-16 rounded-3xl bg-[var(--bg-surface-elevated)] border border-[var(--border-subtle)] mx-auto flex items-center justify-center text-purple-400 shadow-inner">
        <Globe size={28} strokeWidth={1.75} />
        <div class="absolute inset-0 bg-purple-500/10 rounded-3xl blur-md"></div>
      </div>

      <div class="space-y-1.5 max-w-xs mx-auto">
        <h3 class="text-base font-bold text-[var(--text-primary)] tracking-tight">No languages configured</h3>
        <p class="text-xs text-[var(--text-muted)] leading-relaxed">
          Create your first target language track to configure habit rings, SRS schedules, and word banks.
        </p>
      </div>

      <button
        type="button"
        onclick={() => (isModalOpen = true)}
        class="inline-flex items-center gap-2 px-5 py-2.5 rounded-2xl bg-purple-600 hover:bg-purple-500 text-white font-bold text-xs transition-all duration-200 shadow-[0_0_20px_rgba(168,85,247,0.35)] cursor-pointer active:scale-95"
      >
        <Plus size={15} strokeWidth={2.5} />
        <span>Create First Language</span>
      </button>
    </div>
  {:else}
    <!-- GRID OF HIGH-END LANGUAGE TILES -->
    <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4 sm:gap-5 relative z-10">
      {#each languageList as lang (lang.code)}
        {@const langColor = getLanguageColor(lang)}

        <button
          type="button"
          onclick={() => onSelectLanguage(lang.code)}
          class="group relative w-full text-left p-6 rounded-3xl border border-[var(--border-card)] bg-[var(--bg-surface)]/85 hover:bg-[var(--bg-surface-elevated)] shadow-sm hover:shadow-xl transition-all duration-300 active:scale-[0.985] flex flex-col justify-between h-48 cursor-pointer overflow-hidden backdrop-blur-xl hover:-translate-y-1.5"
          style="
            background-image: radial-gradient(circle 280px at 0% 0%, {langColor}14, transparent 100%);
          "
        >
          <!-- Hover Light Bleed -->
          <div 
            class="pointer-events-none absolute -bottom-16 -right-16 w-36 h-36 rounded-full blur-3xl opacity-0 group-hover:opacity-40 transition-opacity duration-500"
            style="background-color: {langColor};"
          ></div>

          <!-- Top Row: Icon, BCP Badge & Streak -->
          <div class="flex items-center justify-between gap-3 w-full relative z-10">
            <div 
              class="w-11 h-11 rounded-2xl flex items-center justify-center border shadow-xs transition-transform duration-300 group-hover:scale-110"
              style="
                background-color: {langColor}15; 
                border-color: {langColor}35; 
                color: {langColor};
                box-shadow: 0 0 12px {langColor}20;
              "
            >
              <Languages size={20} strokeWidth={2.2} />
            </div>

            <div class="flex items-center gap-2">
              {#if lang.current_streak > 0}
                <div 
                  class="flex items-center gap-1.5 px-2.5 py-1 rounded-xl bg-amber-500/10 border border-amber-500/25 shadow-xs"
                >
                  <Flame size={12} class="text-amber-500 fill-amber-500/20" />
                  <span class="text-[11px] font-mono font-black text-amber-500">
                    {lang.current_streak}d
                  </span>
                </div>
              {/if}

              <span class="px-2.5 py-1 rounded-xl font-mono text-[10px] font-bold uppercase tracking-wider bg-[var(--badge-bg)] text-[var(--text-secondary)] border border-[var(--border-subtle)] shadow-xs">
                {lang.code}
              </span>
            </div>
          </div>

          <!-- Bottom Row: Title & Action Affordance -->
          <div class="flex items-end justify-between gap-3 w-full pt-4 relative z-10 border-t border-[var(--border-subtle)]">
            <div class="space-y-0.5 min-w-0">
              <span class="text-lg font-black tracking-tight text-[var(--text-primary)] block truncate group-hover:text-white transition-colors">
                {lang.name}
              </span>
              <span class="text-[10px] font-mono text-[var(--text-muted)] flex items-center gap-1.5">
                <Compass size={11} style="color: {langColor};" />
                <span>Active Track</span>
              </span>
            </div>

            <!-- Animated Forward Arrow Capsule -->
            <div 
              class="w-9 h-9 rounded-2xl border flex items-center justify-center transition-all duration-300 group-hover:translate-x-1 shadow-xs"
              style="
                background-color: var(--bg-surface-elevated); 
                border-color: var(--border-subtle); 
                color: var(--text-muted);
              "
            >
              <ArrowRight size={15} strokeWidth={2.2} class="transition-colors group-hover:text-[var(--text-primary)]" />
            </div>
          </div>
        </button>
      {/each}
    </div>
  {/if}
</div>

<!-- LUXURY DIALOG MODAL -->
{#if isModalOpen}
  <div 
    class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/75 backdrop-blur-md animate-in fade-in duration-150"
    onclick={(e) => {
      if (e.target === e.currentTarget) isModalOpen = false;
    }}
    role="presentation"
  >
    <div 
      class="relative w-full max-w-md rounded-3xl bg-[var(--bg-surface)] border border-[var(--border-card)] p-6 sm:p-7 shadow-2xl space-y-6 overflow-hidden animate-in zoom-in-95 duration-150"
      role="dialog"
      aria-modal="true"
      style="
        background-image: radial-gradient(circle 320px at 100% 0%, rgba(168, 85, 247, 0.12), transparent 100%);
      "
    >
      <!-- Modal Header -->
      <div class="flex items-center justify-between border-b border-[var(--border-subtle)] pb-4">
        <div class="flex items-center gap-2.5">
          <div class="w-8 h-8 rounded-xl bg-purple-500/15 border border-purple-500/30 flex items-center justify-center text-purple-400">
            <Plus size={16} strokeWidth={2.5} />
          </div>
          <div>
            <h2 class="text-sm font-bold text-[var(--text-primary)] tracking-tight block">
              Add Target Language
            </h2>
            <span class="text-[10px] font-mono text-[var(--text-muted)]">
              Register BCP-47 Language Code
            </span>
          </div>
        </div>

        <button 
          type="button" 
          onclick={() => (isModalOpen = false)} 
          class="w-7 h-7 rounded-xl flex items-center justify-center text-[var(--text-muted)] hover:text-[var(--text-primary)] hover:bg-[var(--bg-surface-elevated)] border border-transparent hover:border-[var(--border-subtle)] transition-all cursor-pointer"
        >
          <X size={14} strokeWidth={2.2} />
        </button>
      </div>

      <!-- Form Inputs -->
      <form onsubmit={handleCreateLanguage} class="space-y-4">
        
        <!-- Language Name Field -->
        <div class="space-y-1.5">
          <label 
            for="lang-name-input" 
            class="block text-[10px] font-bold text-[var(--text-muted)] uppercase tracking-wider cursor-pointer"
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
            class="w-full px-4 py-3 rounded-2xl text-xs sm:text-sm bg-[var(--bg-base)] border border-[var(--border-card)] text-[var(--text-primary)] placeholder-[var(--text-muted)]/60 outline-none focus:border-purple-500 focus:ring-2 focus:ring-purple-500/20 transition-all font-medium shadow-inner"
          />
        </div>

        <!-- Language Code Field -->
        <div class="space-y-1.5">
          <div class="flex items-center justify-between">
            <label 
              for="lang-code-input" 
              class="text-[10px] font-bold text-[var(--text-muted)] uppercase tracking-wider cursor-pointer"
            >
              Language Code (BCP 47)
            </label>
            {#if !isCustomCode && codeInput}
              <span class="inline-flex items-center gap-1 text-[10px] text-purple-400 font-mono font-bold">
                <CheckCircle2 size={11} />
                <span>auto-detected</span>
              </span>
            {/if}
          </div>

          <div class="relative flex items-center">
            <input
              id="lang-code-input"
              type="text"
              placeholder="e.g. ja, de, es, zh-CN"
              bind:value={codeInput}
              oninput={() => (isCustomCode = true)}
              required
              class="w-full px-4 py-3 rounded-2xl text-xs sm:text-sm font-mono font-bold uppercase bg-[var(--bg-base)] border border-[var(--border-card)] text-[var(--text-primary)] placeholder-[var(--text-muted)]/60 outline-none focus:border-purple-500 focus:ring-2 focus:ring-purple-500/20 transition-all shadow-inner"
            />
          </div>
        </div>

        <!-- Footer Actions -->
        <div class="flex items-center justify-end gap-2.5 pt-4 border-t border-[var(--border-subtle)]">
          <button
            type="button"
            onclick={() => (isModalOpen = false)}
            class="px-4 py-2.5 rounded-2xl border border-[var(--border-card)] text-xs font-semibold text-[var(--text-secondary)] hover:bg-[var(--bg-surface-elevated)] hover:text-[var(--text-primary)] transition-all cursor-pointer"
          >
            Cancel
          </button>
          
          <button
            type="submit"
            class="inline-flex items-center gap-1.5 px-5 py-2.5 rounded-2xl bg-purple-600 hover:bg-purple-500 text-xs font-bold text-white transition-all shadow-[0_0_18px_rgba(168,85,247,0.35)] cursor-pointer active:scale-95"
          >
            <Sparkles size={13} />
            <span>Create Workspace</span>
          </button>
        </div>
      </form>
    </div>
  </div>
{/if}