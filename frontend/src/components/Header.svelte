<script>
  import { metadataStore } from '../lib/stores/metadata.svelte.js';

  let status = $derived(metadataStore.connectionStatus);

  let dotColor = $derived(
    status === 'connected'
      ? 'bg-emerald-500 shadow-[0_0_8px_rgba(16,185,129,0.5)]'
      : status === 'connecting'
        ? 'bg-slate-400 dark:bg-slate-600'
        : 'bg-rose-500 shadow-[0_0_8px_rgba(244,63,94,0.5)]'
  );
</script>

<header class="safe-top w-full px-5 pb-2 flex justify-end items-center pointer-events-none sticky top-0 z-50">
  <!-- Subtle Status Dot -->
  <div 
    title={`Status: ${status}`}
    class="w-1.5 h-1.5 rounded-full transition-all duration-500 {dotColor}"
  ></div>
</header>