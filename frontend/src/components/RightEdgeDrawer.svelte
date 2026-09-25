<!-- frontend/src/components/RightEdgeDrawer.svelte -->
<script>
  import { activeLanguage } from '../lib/stores/activeLanguage.svelte.js';
  import { ChevronLeft, X, Sparkles, GripVertical } from '@lucide/svelte';

  let {
    isOpen = $bindable(false),
    width = 360,
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
        isOpen = dragOffset > width * 0.25;
      } else {
        isOpen = dragOffset >= width * 0.75;
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

  let translateX = $derived.by(() => {
    if (isDragging) {
      const hiddenPx = width - dragOffset;
      return `${hiddenPx}px`;
    }
    return isOpen ? '0px' : '100%';
  });

  let backdropOpacity = $derived.by(() => {
    if (isDragging) {
      return (dragOffset / width) * 0.6;
    }
    return isOpen ? 0.6 : 0;
  });
</script>

<svelte:window
  onkeydown={(e) => {
    if (e.key === 'Escape' && isOpen) isOpen = false;
  }}
/>

<!-- 🌟 RIGHT EDGE LIQUID GLASS HANDLE PADDLE 🌟 -->
{#if !isOpen}
  <button
    type="button"
    aria-label="Open Quick Hub"
    class="group fixed top-1/2 -translate-y-1/2 right-0 z-30 h-20 w-7 rounded-l-2xl border-y border-l border-white/20 dark:border-white/15 bg-white/70 dark:bg-[#12131a]/75 backdrop-blur-xl shadow-[-8px_0_24px_-4px_rgba(0,0,0,0.25)] flex flex-col items-center justify-center gap-1 cursor-pointer touch-none active:scale-95 hover:w-9 transition-all duration-200 overflow-hidden"
    onclick={() => (isOpen = true)}
    ontouchstart={handleTouchStart}
    ontouchmove={handleTouchMove}
    ontouchend={handleTouchEnd}
    ontouchcancel={handleTouchEnd}
  >
    <!-- Left Specular Neon Lip -->
    <div 
      class="absolute left-0 top-0 bottom-0 w-[2px] opacity-80 group-hover:opacity-100 transition-opacity"
      style="background: linear-gradient(180deg, transparent 10%, {themeColor} 50%, transparent 90%);"
    ></div>

    <!-- Active Hover Glow Aura -->
    <div 
      class="absolute inset-0 opacity-0 group-hover:opacity-20 transition-opacity duration-300 pointer-events-none"
      style="background: radial-gradient(circle at center, {themeColor} 0%, transparent 75%);"
    ></div>

    <!-- Directional Glyph -->
    <ChevronLeft 
      size={14} 
      strokeWidth={2.5} 
      class="text-neutral-500 dark:text-white/60 group-hover:text-neutral-900 dark:group-hover:text-white group-hover:-translate-x-0.5 transition-all duration-150" 
    />

    <!-- Grip Pill Indicator -->
    <div class="w-1 h-3 rounded-full bg-neutral-400 dark:bg-white/30 group-hover:bg-[var(--hub-accent)] transition-colors" style="--hub-accent: {themeColor};"></div>
  </button>
{/if}

<!-- 🌟 FROSTED AMBIENT BACKDROP 🌟 -->
<div
  class="fixed inset-0 bg-black/40 backdrop-blur-xs z-40 transition-opacity select-none touch-none"
  style="
    opacity: {backdropOpacity};
    pointer-events: {isOpen || isDragging ? 'auto' : 'none'};
    transition-duration: {isDragging ? '0ms' : '240ms'};
  "
  onclick={() => (isOpen = false)}
  aria-hidden="true"
></div>

<!-- 🌟 SLIDE-OUT VISIONOS GLASS DRAWER PANEL 🌟 -->
<aside
  class="fixed top-0 right-0 h-full bg-white/80 dark:bg-[#0c0d14]/85 backdrop-blur-2xl backdrop-saturate-[190%] border-l border-black/10 dark:border-white/10 shadow-[-20px_0_60px_-15px_rgba(0,0,0,0.5)] z-50 flex flex-col will-change-transform select-none overflow-hidden"
  style="
    width: min({width}px, 88vw);
    transform: translateX({translateX});
    transition: {isDragging ? 'none' : 'transform 260ms cubic-bezier(0.16, 1, 0.3, 1)'};
  "
>
  <!-- Specular Left Edge Neon Strip -->
  <div 
    class="pointer-events-none absolute left-0 top-0 bottom-0 w-[2px] opacity-70 z-30"
    style="background: linear-gradient(180deg, transparent 5%, {themeColor} 30%, color-mix(in srgb, {themeColor} 50%, white) 70%, transparent 95%);"
  ></div>

  <!-- Top Ambient Glow Bleed -->
  <div 
    class="pointer-events-none absolute -top-24 right-0 w-64 h-64 rounded-full blur-[80px] opacity-20 -z-10"
    style="background: radial-gradient(circle at center, {themeColor} 0%, transparent 70%);"
  ></div>

  <!-- Header / Drag-to-Dismiss Bar -->
  <div 
    class="flex flex-col border-b border-black/[0.06] dark:border-white/[0.08] bg-white/40 dark:bg-white/[0.03] shrink-0 touch-none cursor-grab active:cursor-grabbing"
    use:dragHeader
  >
    <!-- Centered Tactile Drag Handle Pill -->
    <div class="w-full flex justify-center pt-2 pb-0.5">
      <div class="w-10 h-1 rounded-full bg-neutral-300 dark:bg-white/20"></div>
    </div>

    <div class="flex items-center justify-between px-4 pb-3 pt-1">
      <div class="flex items-center gap-2">
        <span 
          class="w-2 h-2 rounded-full" 
          style="background-color: {themeColor}; box-shadow: 0 0 8px {themeColor};"
        ></span>
        <span class="text-xs font-mono font-black text-neutral-900 dark:text-white uppercase tracking-wider flex items-center gap-1.5">
          <span>Quick Hub</span>
        </span>
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

  <!-- Scrollable Panel Body -->
  <div 
    class="flex-1 overflow-y-auto overscroll-contain p-4 space-y-4 text-xs touch-pan-y no-scrollbar"
    role="region"
    aria-label="Quick panel content"
    use:isolateTouchScroll
  >
    {@render children?.()}
  </div>
</aside>