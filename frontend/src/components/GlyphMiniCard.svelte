<!-- frontend/src/components/GlyphMiniCard.svelte -->
<script>
  import { onMount } from 'svelte';
  import { pointsToSvgPath, fetchGlyphDetails } from '../lib/services/glyphLexicon.js';

  let {
    char = '',
    role = '',
    accentColor = '#10b981',
    lang = 'zh-CN',
    isFocused = false,
    onHover = () => {},
    onLeave = () => {}
  } = $props();

  let details = $state(null);
  let strokeLengths = $state([]);

  onMount(async () => {
    if (!char) return;
    details = await fetchGlyphDetails(lang, char);
    if (details?.medians) {
      strokeLengths = details.medians.map((pts) => {
        let len = 0;
        for (let i = 0; i < pts.length - 1; i++) {
          len += Math.hypot(pts[i + 1][0] - pts[i][0], pts[i + 1][1] - pts[i][1]);
        }
        return Math.max(len * 1.25, 180);
      });
    }
  });
</script>

<div
  role="region"
  aria-label="{role} details"
  onmouseenter={onHover}
  onmouseleave={onLeave}
  class="relative flex flex-col p-4 rounded-2xl border transition-all duration-200 cursor-pointer overflow-hidden backdrop-blur-xl {isFocused
    ? 'border-white/50 bg-white/10 scale-[1.02]'
    : 'border-white/10 bg-white/5 hover:border-white/20'}"
  style="--card-accent: {accentColor};"
>
  <!-- Card Header -->
  <div class="flex items-center justify-between pb-2 border-b border-white/10">
    <span class="text-xs font-mono font-bold" style="color: var(--card-accent);">
      {role}
    </span>
    {#if details?.phonetic || details?.pinyin}
      <span class="text-xs font-mono text-white/50">
        {details.phonetic || details.pinyin}
      </span>
    {/if}
  </div>

  <!-- Body: Live Mini Canvas + Component Meaning -->
  <div class="flex items-center gap-3.5 pt-3">
    <div class="relative w-16 h-16 shrink-0 rounded-xl bg-black/60 border border-white/10 flex items-center justify-center p-1 overflow-hidden">
      {#if details?.strokes && details.strokes.length > 0}
        <svg viewBox="0 0 1024 1024" class="w-full h-full">
          <defs>
            {#each details.strokes as strokeD, idx}
              <clipPath id="mini-clip-{char}-{idx}">
                <path d={strokeD} transform="scale(1, -1) translate(0, -900)" />
              </clipPath>
            {/each}
          </defs>
          {#each details.medians as medianPts, idx}
            {@const len = strokeLengths[idx] || 250}
            <g clip-path="url(#mini-clip-{char}-{idx})">
              <path
                d={pointsToSvgPath(medianPts)}
                transform="scale(1, -1) translate(0, -900)"
                fill="none"
                stroke="var(--card-accent)"
                stroke-width="140"
                stroke-linecap="round"
                stroke-linejoin="round"
                style="stroke-dasharray: {len}; stroke-dashoffset: 0;"
              />
            </g>
          {/each}
        </svg>
      {:else}
        <span class="text-2xl font-black text-white">{char}</span>
      {/if}
    </div>

    <div class="space-y-1 min-w-0">
      <span class="text-2xl font-black text-white block">{char}</span>
      <p class="text-xs text-white/80 leading-snug line-clamp-2">
        {details?.definition || 'Component glyph'}
      </p>
    </div>
  </div>
</div>