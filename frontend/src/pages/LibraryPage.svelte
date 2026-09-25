<!-- frontend/src/pages/LibraryPage.svelte -->
<script>
  import { activeLanguage } from '../lib/stores/activeLanguage.svelte.js';
  import { ciIndexStore } from '../lib/stores/ciIndex.svelte.js';
  import { listeningIndexStore } from '../lib/stores/listeningIndex.svelte.js';
  import { getUnprocessedCICandidates } from '../lib/services/ciCandidateService.js';
  import VideoPlayer from '../components/VideoPlayer.svelte';

  // Razor-sharp vector icons
  import { 
    Headphones, 
    Sparkles, 
    Calendar, 
    ChevronDown, 
    Copy, 
    Check, 
    ExternalLink, 
    Film,
    Layers
  } from '@lucide/svelte';

  let { onSelectDate = null } = $props();

  let colors = $derived(activeLanguage.colors || {});
  let themeColor = $derived(activeLanguage.themeColor || '#a855f7');
  let accentColor = $derived(colors.ci?.primary || colors.ci?.dark_primary || themeColor);
  let accentColorSub = $derived(colors.ci?.light_primary || '#c084fc');

  let candidateData = $derived(
    getUnprocessedCICandidates(
      listeningIndexStore.entries,
      ciIndexStore.links
    )
  );

  let totalAvailable = $derived(candidateData.candidates.length);
  let sortedDates = $derived(candidateData.sortedDates);
  let groupedByDate = $derived(candidateData.groupedByDate);

  // Tracks open state per date
  let openAccordions = $state({});

  function toggleDate(dateKey, isOpen) {
    openAccordions = { ...openAccordions, [dateKey]: isOpen };
  }

  let copiedUrl = $state(null);

  async function handleCopy(url) {
    try {
      await navigator.clipboard.writeText(url);
      copiedUrl = url;
      setTimeout(() => {
        if (copiedUrl === url) copiedUrl = null;
      }, 1800);
    } catch (err) {
      console.error('Clipboard copy failed:', err);
    }
  }

  // 🌟 GYRO / TILT STATE (rAF-Throttled for Video Cards) 🌟
  let activeCardKey = $state(null);
  let tiltX = $state(0);
  let tiltY = $state(0);
  let glareX = $state(50);
  let glareY = $state(50);
  let tiltTicking = false;

  function handleCardMouseMove(e, key) {
    if (activeCardKey !== key) activeCardKey = key;
    if (tiltTicking) return;
    tiltTicking = true;

    const rect = e.currentTarget.getBoundingClientRect();
    const clientX = e.clientX;
    const clientY = e.clientY;

    requestAnimationFrame(() => {
      const normX = ((clientX - rect.left) / rect.width) * 2 - 1;
      const normY = ((clientY - rect.top) / rect.height) * 2 - 1;

      tiltX = -normY * 4.5;
      tiltY = normX * 4.5;
      glareX = ((clientX - rect.left) / rect.width) * 100;
      glareY = ((clientY - rect.top) / rect.height) * 100;

      tiltTicking = false;
    });
  }

  function handleCardMouseLeave() {
    activeCardKey = null;
    tiltX = 0;
    tiltY = 0;
    glareX = 50;
    glareY = 50;
  }

  function getYouTubeThumbnail(url) {
    if (!url) return null;
    const match = url.match(/(?:youtu\.be\/|youtube\.com\/(?:embed\/|v\/|watch\?v=|watch\?.+&v=))([\w-]{11})/);
    return match ? `https://img.youtube.com/vi/${match[1]}/hqdefault.jpg` : null;
  }
</script>

<div 
  class="relative w-full max-w-5xl xl:max-w-6xl mx-auto space-y-6 pt-1 sm:pt-2 pb-24 px-2 sm:px-4 md:px-6 select-none box-border"
  style="--library-accent: {accentColor}; --library-accent-sub: {accentColorSub};"
>
  
  <!-- 🌟 HEADER GLASS POD 🌟 -->
  <div 
    class="relative flex items-center justify-between p-4 sm:p-5 rounded-3xl border border-black/10 dark:border-white/15 bg-white/70 dark:bg-[#12131a]/75 backdrop-blur-2xl backdrop-saturate-[180%] shadow-[0_20px_50px_-12px_rgba(0,0,0,0.18),inset_0_1px_1px_rgba(255,255,255,0.45)] dark:shadow-[0_24px_50px_-12px_rgba(0,0,0,0.7),inset_0_1px_1px_rgba(255,255,255,0.15)] overflow-hidden"
  >
    <!-- Top Specular Neon Highlight Lip -->
    <div 
      class="pointer-events-none absolute top-0 left-0 right-0 h-[2px] opacity-90 z-20"
      style="background: linear-gradient(90deg, transparent 5%, var(--library-accent) 30%, var(--library-accent-sub) 70%, transparent 95%); box-shadow: 0 1px 12px var(--library-accent);"
    ></div>

    <div class="flex items-center gap-3 min-w-0 relative z-10">
      <div 
        class="w-10 h-10 rounded-2xl flex items-center justify-center border shadow-inner shrink-0"
        style="
          background-color: color-mix(in srgb, var(--library-accent) 18%, transparent);
          border-color: color-mix(in srgb, var(--library-accent) 38%, transparent);
          color: var(--library-accent);
        "
      >
        <Headphones size={20} strokeWidth={2.5} class="animate-pulse" />
      </div>

      <div class="space-y-0.5">
        <h1 class="text-sm sm:text-base font-black tracking-tight text-neutral-900 dark:text-white flex items-center gap-1.5">
          <span>CI Candidate Queue</span>
          <span class="w-1.5 h-1.5 rounded-full" style="background-color: var(--library-accent); box-shadow: 0 0 6px var(--library-accent);"></span>
        </h1>
        <p class="text-[11px] text-neutral-500 dark:text-white/50 font-medium">
          Listened media ready to be processed into Comprehensible Input
        </p>
      </div>
    </div>

    <div class="flex items-center gap-2 relative z-10">
      <span
        class="text-xs font-mono font-black px-3 py-1.5 rounded-2xl border shadow-xs"
        style="
          color: var(--library-accent); 
          background-color: color-mix(in srgb, var(--library-accent) 15%, transparent); 
          border-color: color-mix(in srgb, var(--library-accent) 35%, transparent);
          box-shadow: 0 0 12px color-mix(in srgb, var(--library-accent) 15%, transparent);
        "
      >
        {totalAvailable} {totalAvailable === 1 ? 'candidate' : 'candidates'}
      </span>
    </div>
  </div>

  <!-- 🌟 QUEUE SECTION 🌟 -->
  {#if sortedDates.length === 0}
    <div class="py-16 px-6 text-center space-y-3 rounded-3xl border border-dashed border-black/10 dark:border-white/10 bg-white/30 dark:bg-white/[0.02] backdrop-blur-md max-w-md mx-auto">
      <div 
        class="w-12 h-12 rounded-2xl flex items-center justify-center mx-auto border shadow-sm"
        style="
          background-color: color-mix(in srgb, var(--library-accent) 18%, transparent);
          border-color: color-mix(in srgb, var(--library-accent) 38%, transparent);
          color: var(--library-accent);
        "
      >
        <Sparkles size={24} strokeWidth={2.5} />
      </div>

      <div class="space-y-1">
        <h2 class="text-sm font-black text-neutral-900 dark:text-white tracking-tight">
          All Caught Up!
        </h2>
        <p class="text-xs text-neutral-500 dark:text-white/40 max-w-xs mx-auto leading-relaxed">
          All listened videos have been processed into Comprehensible Input. Log more listening sessions to generate new candidates.
        </p>
      </div>
    </div>
  {:else}
    <div class="space-y-3 relative z-10">
      {#each sortedDates as dateKey (dateKey)}
        {@const videos = groupedByDate[dateKey]}
        {@const isOpen = !!openAccordions[dateKey]}
        
        <details
          open={isOpen}
          ontoggle={(e) => toggleDate(dateKey, e.currentTarget.open)}
          class="group rounded-3xl border border-black/10 dark:border-white/10 bg-white/70 dark:bg-[#12131a]/70 backdrop-blur-xl shadow-md overflow-hidden transition-all duration-200"
        >
          <!-- Summary Capsule Header -->
          <summary class="flex items-center justify-between p-3.5 sm:p-4 cursor-pointer list-none hover:bg-black/[0.03] dark:hover:bg-white/[0.04] transition-colors select-none">
            <div class="flex items-center gap-2.5 min-w-0">
              <span 
                class="w-2 h-2 rounded-full" 
                style="background-color: var(--library-accent); box-shadow: 0 0 8px var(--library-accent);"
              ></span>
              <div class="flex items-center gap-2 font-mono font-bold text-xs sm:text-sm text-neutral-900 dark:text-white tracking-tight">
                <Calendar size={13} style="color: var(--library-accent);" />
                <span>{dateKey}</span>
              </div>
            </div>

            <div class="flex items-center gap-2 shrink-0">
              <span 
                class="text-[10px] font-mono font-bold px-2.5 py-1 rounded-xl border bg-black/[0.03] dark:bg-white/[0.05] border-black/[0.06] dark:border-white/[0.08] text-neutral-600 dark:text-white/70 flex items-center gap-1.5 shadow-2xs"
              >
                <Film size={11} style="color: var(--library-accent);" />
                <span>{videos.length} {videos.length === 1 ? 'video' : 'videos'}</span>
              </span>

              <div class="w-6 h-6 rounded-lg flex items-center justify-center text-neutral-400 dark:text-white/40 group-open:rotate-180 transition-transform duration-200">
                <ChevronDown size={14} strokeWidth={2.5} />
              </div>
            </div>
          </summary>

          <!-- 🌟 ACCORDION EXPANSION: 3D GYROSCOPIC TILT VIDEO CARDS 🌟 -->
          {#if isOpen}
            <div class="p-3.5 sm:p-5 border-t border-black/10 dark:border-white/10 bg-black/[0.02] dark:bg-black/30 grid grid-cols-1 lg:grid-cols-2 gap-4 sm:gap-5 [perspective:1000px]">
              {#each videos as item, i (`${dateKey}_${item.url}_${i}`)}
                {@const cardKey = `${dateKey}_${item.url}_${i}`}
                {@const isCardHovered = activeCardKey === cardKey}
                {@const thumb = getYouTubeThumbnail(item.url)}

                <div 
                  role="presentation"
                  onmousemove={(e) => handleCardMouseMove(e, cardKey)}
                  onmouseleave={handleCardMouseLeave}
                  class="group/card relative flex flex-col justify-between rounded-3xl border border-black/10 dark:border-white/15 bg-white/80 dark:bg-[#0c0d14]/85 shadow-xl overflow-hidden will-change-transform"
                  style="
                    transform: {isCardHovered ? `rotateX(${tiltX}deg) rotateY(${tiltY}deg) translateY(-4px) scale(1.01)` : 'rotateX(0deg) rotateY(0deg) translateY(0) scale(1)'};
                    transform-style: preserve-3d;
                    transition: transform 0.12s cubic-bezier(0.16, 1, 0.3, 1), box-shadow 0.2s ease, border-color 0.2s ease;
                    box-shadow: {isCardHovered 
                      ? `0 24px 50px -12px rgba(0,0,0,0.6), 0 0 24px color-mix(in srgb, var(--library-accent) 25%, transparent)` 
                      : '0 10px 25px -8px rgba(0,0,0,0.2)'};
                  "
                >
                  <!-- Full-Bleed Artwork / Video Backlight -->
                  {#if thumb}
                    <div class="pointer-events-none absolute inset-0 rounded-3xl overflow-hidden -z-10">
                      <img 
                        src={thumb} 
                        alt="" 
                        aria-hidden="true" 
                        class="w-full h-full object-cover blur-2xl scale-135 saturate-[240%] opacity-40 dark:opacity-50 transition-transform duration-500 transform-gpu group-hover/card:scale-150"
                      />
                      <div class="absolute inset-0 bg-gradient-to-b from-white/40 via-white/15 to-white/90 dark:from-black/40 dark:via-black/20 dark:to-black/90"></div>
                    </div>
                  {:else}
                    <div 
                      class="pointer-events-none absolute inset-0 rounded-3xl opacity-25 -z-10"
                      style="background: radial-gradient(circle at center, var(--library-accent) 0%, transparent 75%);"
                    ></div>
                  {/if}

                  <!-- Cursor Glare Sheen -->
                  <div 
                    class="pointer-events-none absolute inset-0 opacity-0 transition-opacity duration-150 z-20 {isCardHovered ? 'opacity-100' : ''}"
                    style="background: radial-gradient(circle 280px at {glareX}% {glareY}%, rgba(255,255,255,0.18), transparent 75%);"
                  ></div>

                  <!-- Top Specular Lip -->
                  <div 
                    class="pointer-events-none absolute top-0 left-0 right-0 h-[2px] opacity-80 z-20"
                    style="background: linear-gradient(90deg, transparent, var(--library-accent), var(--library-accent-sub), transparent);"
                  ></div>

                  <!-- Video Player Container -->
                  <div class="w-full overflow-hidden rounded-t-3xl border-b border-black/10 dark:border-white/10 bg-black/50 relative z-10">
                    <VideoPlayer src={item.url} accentColor={accentColor} />
                  </div>

                  <!-- Control Deck Footer -->
                  <div class="p-3.5 sm:p-4 flex items-center justify-between gap-2 bg-white/40 dark:bg-black/40 backdrop-blur-md relative z-10">
                    {#if onSelectDate}
                      <button
                        type="button"
                        onclick={() => onSelectDate(dateKey)}
                        class="inline-flex items-center gap-1.5 text-xs font-mono font-bold text-neutral-800 dark:text-white/90 hover:text-neutral-950 dark:hover:text-white transition-colors cursor-pointer truncate"
                      >
                        <Calendar size={11} style="color: var(--library-accent);" />
                        <span class="hover:underline">{dateKey}</span>
                      </button>
                    {:else}
                      <span class="inline-flex items-center gap-1.5 text-xs font-mono font-bold text-neutral-500 dark:text-white/50 truncate">
                        <Calendar size={11} />
                        <span>{dateKey}</span>
                      </span>
                    {/if}

                    <div class="flex items-center gap-1.5 shrink-0">
                      <!-- Copy URL Button -->
                      <button
                        type="button"
                        onclick={() => handleCopy(item.url)}
                        class="inline-flex items-center gap-1.5 px-3 py-1.5 text-[11px] font-mono font-bold rounded-xl border border-black/10 dark:border-white/15 bg-white/70 dark:bg-white/[0.06] hover:bg-white dark:hover:bg-white/15 text-neutral-800 dark:text-white/90 transition-all active:scale-90 cursor-pointer shadow-2xs"
                        style={copiedUrl === item.url ? `color: var(--library-accent); border-color: var(--library-accent);` : ''}
                      >
                        {#if copiedUrl === item.url}
                          <Check size={11} strokeWidth={2.8} />
                          <span>Copied!</span>
                        {:else}
                          <Copy size={11} />
                          <span>Copy</span>
                        {/if}
                      </button>

                      <!-- Open Link Button -->
                      <a
                        href={item.url}
                        target="_blank"
                        rel="noopener noreferrer"
                        class="p-1.5 rounded-xl border border-black/10 dark:border-white/15 bg-white/70 dark:bg-white/[0.06] hover:bg-white dark:hover:bg-white/15 text-neutral-600 dark:text-white/70 hover:text-neutral-950 dark:hover:text-white transition-all cursor-pointer shadow-2xs active:scale-90"
                        title="Open source in new tab"
                      >
                        <ExternalLink size={12} strokeWidth={2.2} />
                      </a>
                    </div>
                  </div>
                </div>
              {/each}
            </div>
          {/if}
        </details>
      {/each}
    </div>
  {/if}

</div>