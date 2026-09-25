<!-- frontend/src/components/UploadProgressBar.svelte -->
<script>
  import { uploadProgressStore } from '../lib/stores/uploadProgress.svelte.js';
  import { activeLanguage } from '../lib/stores/activeLanguage.svelte.js';

  let isUploading = $derived(uploadProgressStore.isUploading);
  let progress = $derived(uploadProgressStore.progress);

  // Dynamic system theme chroma
  let themeColor = $derived(activeLanguage.themeColor || '#6366f1');
  let colors = $derived(activeLanguage.colors || {});
  let secondaryColor = $derived(colors.vocab?.primary || colors.theme || '#a855f7');
</script>

<div
  class="fixed top-0 left-0 right-0 h-[2.5px] z-[9999] pointer-events-none transition-all duration-300 overflow-visible select-none {isUploading ? 'opacity-100' : 'opacity-0'}"
  aria-hidden="true"
  style="--prog-primary: {themeColor}; --prog-secondary: {secondaryColor};"
>
  <!-- Ambient Backdrop Diffuse Glow -->
  <div 
    class="absolute top-0 left-0 h-3 blur-md opacity-40 transition-all duration-200 ease-out transform-gpu pointer-events-none"
    style="
      width: {progress}%;
      background: linear-gradient(90deg, transparent, var(--prog-primary), var(--prog-secondary));
    "
  ></div>

  <!-- Primary Progress Rail -->
  <div
    class="relative h-full transition-all duration-200 ease-out transform-gpu"
    style="
      width: {progress}%;
      background: linear-gradient(90deg, transparent 0%, var(--prog-primary) 35%, var(--prog-secondary) 100%);
      box-shadow: 0 1px 8px color-mix(in srgb, var(--prog-secondary) 75%, transparent);
    "
  >
    <!-- Specular Sweeping Shimmer Sheen -->
    <div class="absolute inset-0 bg-gradient-to-r from-transparent via-white/40 to-transparent animate-shimmer opacity-70"></div>

    <!-- Leading Edge Photon Particle Spark -->
    <div 
      class="absolute right-0 top-1/2 -translate-y-1/2 w-2 h-2 rounded-full transform translate-x-1"
      style="
        background: radial-gradient(circle, #ffffff 30%, var(--prog-secondary) 85%);
        box-shadow: 0 0 10px 2px var(--prog-secondary), 0 0 4px #ffffff;
      "
    ></div>
  </div>
</div>

<style>
  @keyframes shimmer {
    0% {
      transform: translateX(-100%);
    }
    100% {
      transform: translateX(100%);
    }
  }

  .animate-shimmer {
    animation: shimmer 1.6s infinite cubic-bezier(0.4, 0, 0.2, 1);
  }
</style>