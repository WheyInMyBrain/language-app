<script>
  import { metadataStore } from '../lib/stores/metadata.svelte.js';

  let { onSelectLanguage } = $props();
  let languageList = $derived(Object.values(metadataStore.languages));
</script>

<div class="max-w-md mx-auto pt-6 pb-4 px-1 space-y-6">
  <div>
    <h1 class="text-2xl font-bold tracking-tight text-[var(--text-primary)]">
      Log Language
    </h1>
  </div>

  {#if languageList.length === 0}
    <div class="py-12 px-6 rounded-2xl border border-dashed border-[var(--border-card)] text-center text-[var(--text-muted)] text-sm">
      Loading languages...
    </div>
  {:else}
    <div class="space-y-3">
      {#each languageList as lang (lang.code)}
        <button
          onclick={() => onSelectLanguage(lang.code)}
          class="w-full rounded-2xl border border-[var(--border-card)] bg-[var(--bg-surface)] py-4 px-6 text-center shadow-xs transition-transform duration-75 active:scale-[0.97] active:bg-[var(--bg-surface-active)] [@media(hover:hover)]:hover:-translate-y-0.5 [@media(hover:hover)]:hover:border-[var(--border-hover)]"
        >
          <span class="text-base font-semibold tracking-wide text-[var(--text-primary)]">
            {lang.name}
          </span>
        </button>
      {/each}
    </div>
  {/if}
</div>