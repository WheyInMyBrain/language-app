<!-- frontend/src/components/RightEdgeDrawer.svelte -->
<script>
  import { activeLanguage } from '../lib/stores/activeLanguage.svelte.js';
  import { ChevronLeft, X, Sparkles, Layers } from '@lucide/svelte';

  let {
    isOpen = $bindable(false),
    width = 380,
    children
  } = $props();

  let isDragging = $state(false);
  let startX = 0;
  let dragOffset = $state(0);
  let hasDragged = false;

  let themeColor = $derived(activeLanguage.themeColor || '#a855f7');

  function handleTouchStart(e) {
    const touch = e.touches[0];
    isDragging = true;
    hasDragged = false;
    startX = touch.clientX;
    dragOffset = isOpen ? width : 0;
  }

  function handleTouchMove(e) {
    if (!isDragging) return;
    const touch = e.touches[0];
    const deltaX = startX - touch.clientX;

    if (Math.abs(deltaX) > 6) {
      hasDragged = true;
      if (e.cancelable) e.preventDefault();
    }

    if (!isOpen) {
      dragOffset = Math.max(0, Math.min(width, deltaX));
    } else {
      dragOffset = Math.max(0, Math.min(width, width - (touch.clientX - startX)));
    }
  }

  function handleTouchEnd() {
    if (!isDragging) return;
    isDragging = false;

    if (!hasDragged) {
      isOpen = !isOpen;
    } else {
      if (!isOpen) {
        isOpen = dragOffset > width * 0.28;
      } else {
        isOpen = dragOffset >= width * 0.72;
      }
    }
    dragOffset = 0;
  }

  function dragHeader(node) {
    node.addEventListener('touchstart', handleTouchStart, { passive: true });
    node.addEventListener('touchmove', handleTouchMove, { passive: false });
    node.addEventListener('touchend', handleTouchEnd, { passive: true });
    node.addEventListener('touchcancel', handleTouchEnd, { passive: true });

    return {
      destroy() {
        node.removeEventListener('touchstart', handleTouchStart);
        node.removeEventListener('touchmove', handleTouchMove);
        node.removeEventListener('touchend', handleTouchEnd);
        node.removeEventListener('touchcancel', handleTouchEnd);
      }
    };
  }

  function isolateTouchScroll(node) {
    const onTouchMove = (e) => e.stopPropagation();
    node.addEventListener('touchmove', onTouchMove, { passive: true });

    return {
      destroy() {
        node.removeEventListener('touchmove', onTouchMove);
      }
    };
  }

  // Fluid transform and dynamic drag calculations
  let translateX = $derived.by(() => {
    if (isDragging) {
      const hiddenPx = width - dragOffset;
      return `${hiddenPx}px`;
    }
    return isOpen ? '0px' : '100%';
  });

  let backdropOpacity = $derived.by(() => {
    if (isDragging) {
      return (dragOffset / width) * 0.65;
    }
    return isOpen ? 0.65 : 0;
  });

  // Dynamic glass refraction blur based on open progress
  let dynamicBlur = $derived.by(() => {
    if (isDragging) {
      return `${Math.max(4, Math.round((dragOffset / width) * 24))}px`;
    }
    return isOpen ? '24px' : '0px';
  });
</script>

<svelte:window
  onkeydown={(e) => {
    if (e.key === 'Escape' && isOpen) isOpen = false;
  }}
/>

<!-- 🌟 FLOATING LIQUID GLASS PULL PADDLE 🌟 -->
{#if !isOpen}
  <button
    type="button"
    aria-label="Open Quick Hub"
    class="group fixed top-1/2 -translate-y-1/2 right-0 z-30 h-24 w-8 rounded-l-2xl border-y border-l border-white/30 dark:border-white/20 bg-white/70 dark:bg-[#0c0d16]/70 backdrop-blur-xl shadow-[-12px_0_30px_-6px_rgba(0,0,0,0.35)] flex flex-col items-center justify-center gap-1.5 cursor-pointer touch-none active:scale-90 hover:w-10 transition-all duration-300 overflow-hidden"
    onclick={() => (isOpen = true)}
    ontouchstart={handleTouchStart}
    ontouchmove={handleTouchMove}
    ontouchend={handleTouchEnd}
    ontouchcancel={handleTouchEnd}
  >
    <!-- Caustic Neon Rim Highlight -->
    <div 
      class="absolute left-0 top-0 bottom-0 w-[2.5px] opacity-80 group-hover:opacity-100 transition-opacity"
      style="background: linear-gradient(180deg, transparent 5%, {themeColor} 45%, color-mix(in srgb, {themeColor} 40%, white) 55%, transparent 95%); box-shadow: 0 0 10px {themeColor};"
    ></div>

    <!-- Soft Ambient Light Beacon -->
    <div 
      class="absolute inset-0 opacity-0 group-hover:opacity-30 transition-opacity duration-300 pointer-events-none"
      style="background: radial-gradient(circle at right center, {themeColor} 0%, transparent 80%);"
    ></div>

    <!-- Directional Icon with Spring Hop -->
    <ChevronLeft 
      size={15} 
      strokeWidth={3} 
      class="text-neutral-600 dark:text-white/70 group-hover:text-neutral-950 dark:group-hover:text-white group-hover:-translate-x-1 transition-transform duration-200" 
    />

    <!-- Luminescent Touch Bead -->
    <div 
      class="w-1.5 h-3.5 rounded-full transition-all duration-300 group-hover:h-5 shadow-[0_0_8px_var(--glow)]" 
      style="--glow: {themeColor}; background-color: {themeColor};"
    ></div>
  </button>
{/if}

<!-- 🌟 FROSTED AMBIENT BACKDROP 🌟 -->
<div
  class="fixed inset-0 bg-black/45 z-40 transition-all select-none touch-none"
  style="
    opacity: {backdropOpacity};
    backdrop-filter: blur({dynamicBlur});
    -webkit-backdrop-filter: blur({dynamicBlur});
    pointer-events: {isOpen || isDragging ? 'auto' : 'none'};
    transition-duration: {isDragging ? '0ms' : '360ms'};
    transition-timing-function: cubic-bezier(0.32, 0.72, 0, 1);
  "
  onclick={() => (isOpen = false)}
  aria-hidden="true"
></div>

<!-- 🌟 VISIONOS LIQUID GLASS DRAWER 🌟 -->
<aside
  class="fixed top-0 right-0 h-full z-50 flex flex-col will-change-transform select-none overflow-hidden border-l border-white/20 dark:border-white/10"
  style="
    width: min({width}px, 90vw);
    transform: translateX({translateX});
    background: color-mix(in srgb, var(--bg-base, #0c0d14) 82%, transparent);
    backdrop-filter: blur(36px) saturate(210%);
    -webkit-backdrop-filter: blur(36px) saturate(210%);
    box-shadow: -28px 0 80px -15px rgba(0, 0, 0, 0.65), inset 1px 0 0 0 rgba(255, 255, 255, 0.12);
    transition: {isDragging ? 'none' : 'transform 380ms cubic-bezier(0.32, 0.72, 0, 1)'};
  "
>
  <!-- 🌟 CAUSTIC GLASS SPECULAR EDGE (Animated Shimmer on Open) 🌟 -->
  <div 
    class="pointer-events-none absolute left-0 top-0 bottom-0 w-[2px] z-30 overflow-hidden"
  >
    <div 
      class="w-full h-full"
      style="background: linear-gradient(180deg, transparent 0%, {themeColor} 30%, color-mix(in srgb, {themeColor} 60%, white) 50%, {themeColor} 70%, transparent 100%);"
    ></div>
    <!-- Moving specular light glint -->
    <div 
      class="absolute inset-x-0 w-full h-32 bg-gradient-to-b from-transparent via-white to-transparent opacity-80 animate-shimmer"
      style="animation: glassSweep 3.5s ease-in-out infinite;"
    ></div>
  </div>

  <!-- Inner Ambient Volumetric Light Orbs -->
  <div 
    class="pointer-events-none absolute -top-32 -right-32 w-80 h-80 rounded-full blur-[100px] opacity-25 -z-10"
    style="background: radial-gradient(circle at center, {themeColor} 0%, transparent 70%);"
  ></div>
  <div 
    class="pointer-events-none absolute -bottom-32 -left-32 w-72 h-72 rounded-full blur-[90px] opacity-15 -z-10"
    style="background: radial-gradient(circle at center, {themeColor} 0%, transparent 70%);"
  ></div>

  <!-- Header / Drag-to-Dismiss Zone -->
  <div 
    class="flex flex-col border-b border-black/[0.06] dark:border-white/[0.08] bg-white/40 dark:bg-white/[0.02] shrink-0 touch-none cursor-grab active:cursor-grabbing relative z-20 backdrop-blur-md"
    use:dragHeader
  >
    <!-- Tactile Elastic Pull Bar Indicator -->
    <div class="w-full flex justify-center pt-2.5 pb-1">
      <div class="w-12 h-1 rounded-full bg-neutral-300 dark:bg-white/20 transition-all duration-200 hover:bg-neutral-400 dark:hover:bg-white/40"></div>
    </div>

    <div class="flex items-center justify-between px-5 pb-3.5 pt-1">
      <div class="flex items-center gap-2.5">
        <div 
          class="relative flex items-center justify-center w-6 h-6 rounded-lg border border-white/20 shadow-xs"
          style="background: color-mix(in srgb, {themeColor} 20%, transparent);"
        >
          <Sparkles size={13} style="color: {themeColor};" />
        </div>
        <div class="flex flex-col leading-none">
          <span class="text-xs font-mono font-black text-neutral-900 dark:text-white uppercase tracking-wider">
            Quick Hub
          </span>
          <span class="text-[9px] font-mono text-[var(--text-muted)] tracking-widest uppercase mt-0.5">
            Active Cockpit
          </span>
        </div>
      </div>

      <button
        type="button"
        onclick={() => (isOpen = false)}
        class="w-7 h-7 flex items-center justify-center rounded-xl bg-black/[0.04] dark:bg-white/[0.06] hover:bg-black/[0.08] dark:hover:bg-white/[0.12] text-neutral-500 dark:text-white/60 hover:text-neutral-900 dark:hover:text-white cursor-pointer active:scale-90 transition-all border border-black/[0.06] dark:border-white/10 shadow-2xs"
        aria-label="Close"
      >
        <X size={13} strokeWidth={2.5} />
      </button>
    </div>
  </div>

  <!-- Scrollable Panel Body with Staggered Slide-In -->
  <div 
    class="flex-1 overflow-y-auto overscroll-contain p-5 space-y-4 text-xs touch-pan-y no-scrollbar relative z-10 transition-all duration-500"
    style="
      opacity: {isOpen ? 1 : 0};
      transform: {isOpen ? 'none' : 'translateX(12px) scale(0.98)'};
      transition-delay: {isOpen ? '80ms' : '0ms'};
    "
    role="region"
    aria-label="Quick panel content"
    use:isolateTouchScroll
  >
    {@render children?.()}
  </div>
</aside>

<style>
  @keyframes glassSweep {
    0% { transform: translateY(-100%); }
    50% { transform: translateY(120%); }
    100% { transform: translateY(120%); }
  }
</style>