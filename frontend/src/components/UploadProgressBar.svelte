<!-- frontend/src/components/UploadProgressBar.svelte -->
<script>
  import { uploadProgressStore } from '../lib/stores/uploadProgress.svelte.js';

  let isUploading = $derived(uploadProgressStore.isUploading);
  let progress = $derived(uploadProgressStore.progress);
</script>

<div
  class="fixed bottom-0 left-0 right-0 h-[2.5px] z-50 pointer-events-none transition-opacity duration-300 {isUploading ? 'opacity-100' : 'opacity-0'}"
  aria-hidden="true"
>
  <div
    class="h-full bg-emerald-500 shadow-[0_0_8px_rgba(16,185,129,0.8)] transition-all duration-150 ease-out"
    style="width: {progress}%;"
  ></div>
</div>