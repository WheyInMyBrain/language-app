<!-- frontend/src/components/RightEdgeDrawer.svelte -->
<script>
  let {
    isOpen = $bindable(false),
    width = 340,
    children
  } = $props();

  let isDragging = $state(false);
  let startX = 0;
  let dragOffset = $state(0);
  let hasDragged = false;

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

  // Action helper to bind touch-drag without a11y_no_static_element_interactions
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

  // Action helper for scroll isolation
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
      return (dragOffset / width) * 0.5;
    }
    return isOpen ? 0.5 : 0;
  });
</script>

<svelte:window
  onkeydown={(e) => {
    if (e.key === 'Escape' && isOpen) isOpen = false;
  }}
/>

<!-- Right Edge Pill Handle (Button is interactive, passes a11y) -->
{#if !isOpen}
  <button
    type="button"
    aria-label="Open Side Panel"
    class="fixed top-1/2 -translate-y-1/2 right-0 z-30 h-16 w-5 rounded-l-xl bg-[var(--bg-surface)] border-y border-l border-[var(--border-card)] shadow-md flex items-center justify-center cursor-pointer touch-none active:scale-95 transition-transform"
    onclick={() => (isOpen = true)}
    ontouchstart={handleTouchStart}
    ontouchmove={handleTouchMove}
    ontouchend={handleTouchEnd}
    ontouchcancel={handleTouchEnd}
  >
    <div class="w-1 h-7 rounded-full bg-[var(--text-muted)] opacity-60"></div>
  </button>
{/if}

<!-- Backdrop -->
<div
  class="fixed inset-0 bg-black z-40 transition-opacity select-none touch-none"
  style="
    opacity: {backdropOpacity};
    pointer-events: {isOpen || isDragging ? 'auto' : 'none'};
    transition-duration: {isDragging ? '0ms' : '220ms'};
  "
  onclick={() => (isOpen = false)}
  aria-hidden="true"
></div>

<!-- Slide-out Drawer Panel -->
<aside
  class="fixed top-0 right-0 h-full bg-[var(--bg-surface)] border-l border-[var(--border-card)] shadow-2xl z-50 flex flex-col will-change-transform select-none"
  style="
    width: min({width}px, 86vw);
    transform: translateX({translateX});
    transition: {isDragging ? 'none' : 'transform 240ms cubic-bezier(0.16, 1, 0.3, 1)'};
  "
>
  <!-- Header / Drag-to-Dismiss Bar (Uses action instead of inline listeners) -->
  <div 
    class="flex items-center justify-between px-4 py-3 border-b border-[var(--border-card)] bg-[var(--bg-base)] shrink-0 touch-none cursor-grab"
    use:dragHeader
  >
    <span class="text-xs font-mono font-black text-[var(--interactive-accent,var(--text-primary))] uppercase tracking-wider">
      Quick Hub
    </span>
    <button
      onclick={() => (isOpen = false)}
      class="w-7 h-7 flex items-center justify-center rounded-lg hover:bg-[var(--bg-surface)] text-xs text-[var(--text-muted)] hover:text-[var(--text-primary)] cursor-pointer transition-colors"
      aria-label="Close"
    >
      ✕
    </button>
  </div>

  <!-- Scrollable Panel Body (tabindex removed to fix a11y_no_noninteractive_tabindex) -->
  <div 
    class="flex-1 overflow-y-auto overscroll-contain p-4 space-y-4 text-xs touch-pan-y"
    role="region"
    aria-label="Quick panel content"
    use:isolateTouchScroll
  >
    {@render children?.()}
  </div>
</aside>