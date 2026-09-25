<!-- frontend/src/components/SRSBar.svelte -->
<script>
  import { onMount } from 'svelte';
  import { activeLanguage } from '../lib/stores/activeLanguage.svelte.js';
  import { getIntervalPreview } from '../lib/srsEngine.js';

  // Vector icons
  import { 
    RotateCcw, 
    Zap, 
    Check, 
    Sparkles, 
    Calendar, 
    Flame, 
    ArrowRight, 
    TrendingUp, 
    ShieldCheck 
  } from '@lucide/svelte';

  let {
    session = {},
    activeDate = '',
    onReview = null
  } = $props();

  let barEl = $state(null);
  let isAtBottom = $state(false);

  let curRev = $derived(Number(session?.revision ?? 0));
  let curInterval = $derived(Number(session?.interval ?? 0));
  let curEase = $derived(Number(session?.ease ?? 2.50));
  let displayDueDate = $derived(session?.due_date || activeDate);

  let isSubmitting = $state(false);
  let statusMessage = $state('');
  let lastActionGrade = $state(null);

  // Specular sheen cursor tracking
  let mouseX = $state(50);
  let mouseY = $state(0);
  let isHovered = $state(false);

  let themeColor = $derived(activeLanguage.themeColor || '#a855f7');

  let formattedDueDate = $derived.by(() => {
    if (!displayDueDate || displayDueDate === activeDate) return 'Today';
    try {
      const [y, m, d] = displayDueDate.split('-').map(Number);
      const parsed = new Date(y, m - 1, d);
      return parsed.toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
    } catch {
      return displayDueDate;
    }
  });

  let gradeOptions = $derived([
    {
      id: 'again',
      label: 'Again',
      key: '1',
      icon: RotateCcw,
      interval: getIntervalPreview({ interval: curInterval, ease: curEase, grade: 'again' }),
      color: '#f43f5e',
      colorLight: '#fb7185',
      glow: 'rgba(244, 63, 94, 0.45)',
      softBg: 'rgba(244, 63, 94, 0.08)'
    },
    {
      id: 'hard',
      label: 'Hard',
      key: '2',
      icon: Zap,
      interval: getIntervalPreview({ interval: curInterval, ease: curEase, grade: 'hard' }),
      color: '#f59e0b',
      colorLight: '#fbbf24',
      glow: 'rgba(245, 158, 11, 0.45)',
      softBg: 'rgba(245, 158, 11, 0.08)'
    },
    {
      id: 'good',
      label: 'Good',
      key: '3',
      icon: Check,
      interval: getIntervalPreview({ interval: curInterval, ease: curEase, grade: 'good' }),
      color: '#10b981',
      colorLight: '#34d399',
      glow: 'rgba(16, 185, 129, 0.45)',
      softBg: 'rgba(16, 185, 129, 0.08)'
    },
    {
      id: 'easy',
      label: 'Easy',
      key: '4',
      icon: Sparkles,
      interval: getIntervalPreview({ interval: curInterval, ease: curEase, grade: 'easy' }),
      color: '#818cf8',
      colorLight: '#a5b4fc',
      glow: 'rgba(129, 140, 248, 0.45)',
      softBg: 'rgba(129, 140, 248, 0.08)'
    }
  ]);

  // Anti-jitter hysteresis scroll observer
  onMount(() => {
    const scrollParent = barEl?.closest('main') || window;
    let ticking = false;

    const checkScrollPosition = () => {
      if (ticking) return;
      ticking = true;

      requestAnimationFrame(() => {
        let distanceToBottom = 0;
        if (scrollParent === window) {
          const scrollHeight = document.documentElement.scrollHeight;
          const currentScroll = window.scrollY + window.innerHeight;
          distanceToBottom = scrollHeight - currentScroll;
        } else {
          const scrollHeight = scrollParent.scrollHeight;
          const currentScroll = scrollParent.scrollTop + scrollParent.clientHeight;
          distanceToBottom = scrollHeight - currentScroll;
        }

        if (!isAtBottom && distanceToBottom <= 45) {
          isAtBottom = true;
        } else if (isAtBottom && distanceToBottom > 115) {
          isAtBottom = false;
        }
        ticking = false;
      });
    };

    checkScrollPosition();
    scrollParent.addEventListener('scroll', checkScrollPosition, { passive: true });
    window.addEventListener('resize', checkScrollPosition, { passive: true });

    return () => {
      scrollParent.removeEventListener('scroll', checkScrollPosition);
      window.removeEventListener('resize', checkScrollPosition);
    };
  });

  function handleMouseMove(e) {
    if (!barEl) return;
    const rect = barEl.getBoundingClientRect();
    mouseX = ((e.clientX - rect.left) / rect.width) * 100;
    mouseY = ((e.clientY - rect.top) / rect.height) * 100;
  }

  async function handleGrade(grade) {
    if (isSubmitting) return;
    isSubmitting = true;
    lastActionGrade = grade;
    statusMessage = 'Saving...';

    try {
      if (onReview) await onReview(grade);
      statusMessage = 'Saved';
      setTimeout(() => {
        statusMessage = '';
        lastActionGrade = null;
      }, 1200);
    } catch (err) {
      console.error('SRS Review Error:', err);
      statusMessage = 'Error';
      setTimeout(() => {
        statusMessage = '';
        lastActionGrade = null;
      }, 1600);
    } finally {
      isSubmitting = false;
    }
  }

  function handleWindowKeydown(e) {
    if (['INPUT', 'TEXTAREA'].includes(document.activeElement?.tagName)) return;
    if (isSubmitting) return;

    if (curRev < 2) {
      if (e.key === ' ' || e.key === 'Enter') {
        e.preventDefault();
        handleGrade('increment_initial');
      }
    } else {
      if (e.key === '1') handleGrade('again');
      if (e.key === '2') handleGrade('hard');
      if (e.key === '3') handleGrade('good');
      if (e.key === '4') handleGrade('easy');
    }
  }
</script>

<svelte:window onkeydown={handleWindowKeydown} />

<!-- 
  🌟 VISIONOS LIQUID GLASS DOCK 🌟
  - Centered floating pill while scrolling
  - 2-Tier console deck on Mobile & iPad when docked at the bottom
  - 1-Tier horizontal layout only on large desktops (xl+)
-->
<div
  bind:this={barEl}
  role="presentation"
  onmousemove={handleMouseMove}
  onmouseenter={() => (isHovered = true)}
  onmouseleave={() => (isHovered = false)}
  class="relative mx-auto box-border rounded-2xl sm:rounded-3xl border border-black/10 dark:border-white/15 bg-white/55 dark:bg-[#12131a]/60 backdrop-blur-2xl backdrop-saturate-[180%] shadow-[0_20px_45px_-12px_rgba(0,0,0,0.3),inset_0_1px_1px_rgba(255,255,255,0.45)] dark:shadow-[0_24px_45px_-12px_rgba(0,0,0,0.7),inset_0_1px_1px_rgba(255,255,255,0.18)] select-none overflow-hidden transition-[max-width,padding,transform] duration-200 hover:-translate-y-0.5 will-change-transform {isAtBottom 
    ? 'w-full max-w-full p-2.5 sm:p-3.5' 
    : 'w-fit max-w-[96vw] p-1.5 sm:p-2'}"
  style="--srs-theme: {themeColor};"
>
  
  <!-- Dynamic Specular Glare Sheen -->
  <div 
    class="pointer-events-none absolute inset-0 opacity-0 transition-opacity duration-200 -z-0 {isHovered ? 'opacity-100' : ''}"
    style="background: radial-gradient(circle 350px at {mouseX}% {mouseY}%, rgba(255,255,255,0.16), transparent 70%);"
  ></div>

  <!-- Accent Top Neon Line -->
  <div 
    class="pointer-events-none absolute top-0 left-0 right-0 h-[2px] opacity-80"
    style="background: linear-gradient(90deg, transparent 5%, var(--srs-theme) 30%, color-mix(in srgb, var(--srs-theme) 40%, white) 70%, transparent 95%);"
  ></div>

  <!-- 
    🌟 LAYOUT ENGINE 🌟
    - When isAtBottom: flex-col on Mobile & iPad (<xl), flex-row only on Desktop (xl+)
    - When floating: flex-row centered
  -->
  <div class="flex items-center justify-between gap-2.5 sm:gap-3.5 w-full min-w-0 relative z-10 {isAtBottom ? 'flex-col xl:flex-row' : 'flex-row'}">
    
    <!-- 
      TIER 1: TELEMETRY POD
      - Never wraps underneath buttons
      - Hidden while floating on Mobile & iPad (only shown on xl+ screens where width is plentiful)
      - Perfectly structured top tier when at the bottom
    -->
    <div class="items-center justify-between sm:justify-center xl:justify-start gap-1.5 sm:gap-2.5 w-full xl:w-auto shrink min-w-0 {isAtBottom 
      ? 'flex' 
      : 'hidden xl:flex'}">
      
      <!-- Stage Indicator Pill -->
      <div 
        class="flex items-center gap-1.5 px-2.5 py-1 rounded-xl sm:rounded-2xl border shadow-[inset_0_1px_2px_rgba(0,0,0,0.06)] dark:shadow-[inset_0_1px_2px_rgba(0,0,0,0.3)] shrink-0"
        style="
          background-color: color-mix(in srgb, var(--srs-theme) 12%, transparent);
          border-color: color-mix(in srgb, var(--srs-theme) 28%, transparent);
        "
      >
        <span class="w-1.5 h-1.5 rounded-full animate-pulse" style="background-color: var(--srs-theme); box-shadow: 0 0 8px var(--srs-theme);"></span>
        <span class="text-[10px] sm:text-xs font-mono font-black tracking-tight" style="color: var(--srs-theme);">
          {curRev < 2 ? `Pass ${curRev}` : `Pass ${curRev} • Mature`}
        </span>
      </div>

      <!-- Telemetry Chips -->
      <div class="flex items-center gap-1 sm:gap-2 min-w-0 flex-wrap">
        
        <!-- Interval Chip -->
        <div class="flex items-center gap-1 px-2 py-0.5 sm:py-1 rounded-lg sm:rounded-xl bg-black/[0.04] dark:bg-white/[0.05] border border-black/[0.06] dark:border-white/[0.08] shadow-xs">
          <Calendar size={11} class="text-neutral-400 dark:text-white/40 shrink-0" />
          <span class="text-[10px] font-bold text-neutral-400 dark:text-white/40">Int:</span>
          <span class="font-mono font-bold text-neutral-800 dark:text-white/90 text-[10px] sm:text-[11px]">{curInterval}d</span>
        </div>

        <!-- Ease Multiplier Chip -->
        <div class="flex items-center gap-1 px-2 py-0.5 sm:py-1 rounded-lg sm:rounded-xl bg-black/[0.04] dark:bg-white/[0.05] border border-black/[0.06] dark:border-white/[0.08] shadow-xs">
          <TrendingUp size={11} class="text-neutral-400 dark:text-white/40 shrink-0" />
          <span class="text-[10px] font-bold text-neutral-400 dark:text-white/40">Ease:</span>
          <span class="font-mono font-bold text-neutral-800 dark:text-white/90 text-[10px] sm:text-[11px]">{curEase.toFixed(2)}x</span>
        </div>

        <!-- Due Date Chip -->
        <div class="flex items-center gap-1 px-2 py-0.5 sm:py-1 rounded-lg sm:rounded-xl bg-black/[0.04] dark:bg-white/[0.05] border border-black/[0.06] dark:border-white/[0.08] shadow-xs truncate">
          <ShieldCheck size={11} style="color: var(--srs-theme);" class="shrink-0" />
          <span class="text-[10px] font-bold text-neutral-400 dark:text-white/40">Due:</span>
          <span class="font-mono font-bold text-neutral-800 dark:text-white/90 text-[10px] sm:text-[11px] truncate">{formattedDueDate}</span>
        </div>

      </div>

    </div>

    <!-- 
      TIER 2: CONTROL PEDALS
      - On Mobile & iPad at bottom: Clean full-width 4-column pedal array
      - On Desktop: Aligned neatly to the right
      - While floating: Clean centered floating capsule
    -->
    <div class="flex items-center justify-center xl:justify-end gap-1.5 sm:gap-2 w-full xl:w-auto shrink-0">
      
      {#if statusMessage}
        <span class="text-[10px] sm:text-xs font-mono font-bold px-2 py-0.5 rounded-lg bg-black/10 dark:bg-white/10 text-neutral-800 dark:text-white border border-black/10 dark:border-white/10 animate-pulse">
          {statusMessage}
        </span>
      {/if}

      <!-- INITIAL ADVANCE (Pass 0 / 1) -->
      {#if curRev < 2}
        <button
          type="button"
          onclick={() => handleGrade('increment_initial')}
          disabled={isSubmitting}
          class="group relative flex items-center justify-center gap-1.5 sm:gap-2 px-4 sm:px-6 py-1.5 sm:py-2 rounded-xl sm:rounded-2xl text-[11px] sm:text-xs font-black text-white shadow-lg active:scale-95 transition-all duration-100 cursor-pointer disabled:opacity-50 overflow-hidden {isAtBottom ? 'w-full sm:w-auto' : 'w-auto'}"
          style="
            background: linear-gradient(135deg, var(--srs-theme), color-mix(in srgb, var(--srs-theme) 40%, white));
            box-shadow: 0 4px 18px -2px var(--srs-theme);
          "
        >
          <Flame size={13} class="transition-transform group-hover:scale-110 shrink-0" />
          <span class="tracking-tight whitespace-nowrap">Advance to Pass {curRev + 1}</span>
          <ArrowRight size={12} class="transition-transform group-hover:translate-x-0.5 shrink-0" />
          <kbd class="hidden md:inline-flex items-center text-[9px] font-mono px-1 py-0.2 rounded bg-white/20 border border-white/30 text-white ml-0.5">
            Space
          </kbd>
        </button>

      <!-- SM-2 CHROMA PEDAL POD -->
      {:else}
        <div class="grid grid-cols-4 gap-1 sm:gap-1.5 p-0.5 sm:p-1 rounded-xl sm:rounded-2xl bg-black/[0.04] dark:bg-white/[0.05] border border-black/[0.06] dark:border-white/[0.08] shadow-[inset_0_1px_2px_rgba(0,0,0,0.06)] dark:shadow-[inset_0_1px_2px_rgba(0,0,0,0.3)] {isAtBottom ? 'w-full sm:w-auto' : 'w-auto'}">
          {#each gradeOptions as opt}
            {@const Icon = opt.icon}
            {@const isGraded = lastActionGrade === opt.id}
            
            <button
              type="button"
              onclick={() => handleGrade(opt.id)}
              disabled={isSubmitting}
              class="group relative flex items-center justify-center gap-1 sm:gap-1.5 px-2 sm:px-3 py-1 sm:py-1.5 rounded-lg sm:rounded-xl transition-all duration-100 cursor-pointer disabled:opacity-50 active:scale-95 border min-h-[32px] sm:min-h-[36px]"
              style="
                background-color: {isGraded ? opt.color : opt.softBg};
                border-color: {isGraded ? opt.color : 'color-mix(in srgb, ' + opt.color + ' 25%, transparent)'};
                color: {isGraded ? '#fff' : 'inherit'};
                box-shadow: {isGraded ? `0 0 16px ${opt.glow}` : 'none'};
              "
            >
              
              <!-- Top Highlight Rim -->
              <div 
                class="pointer-events-none absolute top-0 left-0 right-0 h-[1px] opacity-40 group-hover:opacity-100"
                style="background: linear-gradient(90deg, transparent, {opt.colorLight}, transparent);"
              ></div>

              <!-- Icon & Label -->
              <Icon 
                size={11} 
                strokeWidth={2.8} 
                style="color: {isGraded ? '#fff' : opt.color};" 
                class="shrink-0 transition-transform group-hover:scale-110" 
              />
              <span class="text-[10px] sm:text-[11px] font-black tracking-tight whitespace-nowrap {isGraded ? 'text-white' : 'text-neutral-700 dark:text-white/80'}">
                {opt.label}
              </span>

              <!-- Interval Badge -->
              <span 
                class="font-mono text-[9px] sm:text-[10px] font-black px-1 py-0.2 rounded border transition-colors shadow-2xs"
                style="
                  background-color: {isGraded ? 'rgba(255,255,255,0.2)' : 'rgba(0,0,0,0.1)'};
                  border-color: {isGraded ? 'rgba(255,255,255,0.3)' : opt.color + '30'};
                  color: {isGraded ? '#fff' : opt.color};
                "
              >
                +{opt.interval}
              </span>

              <!-- Desktop Hotkey -->
              <span class="hidden 2xl:inline text-[9px] font-mono text-neutral-400 dark:text-white/40">
                [{opt.key}]
              </span>

            </button>
          {/each}
        </div>
      {/if}

    </div>

  </div>

</div>