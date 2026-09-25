<!-- frontend/src/components/ColoredText.svelte -->
<script>
  import { activeLanguage } from '../lib/stores/activeLanguage.svelte.js';
  import { fetchGlyphDetails } from '../lib/services/glyphLexicon.js';
  import GlyphHologram from './GlyphHologram.svelte';

  let {
    tokens = [],
    fallbackClass = 'text-white',
    lang = 'zh-CN'
  } = $props();

  let activeGlyphData = $state(null);
  let isLoading = $state(false);

  let langConfig = $derived(activeLanguage.current || {});
  let glyphConfig = $derived(langConfig.glyphConfig || null);

  async function handleCharClick(char, e) {
    if (!char || !glyphConfig) return;

    // Check if the clicked character is inspectable according to this language
    const isInspectable = typeof glyphConfig.isInspectable === 'function' 
      ? glyphConfig.isInspectable(char) 
      : false;

    if (!isInspectable) return;

    e.stopPropagation();
    isLoading = true;
    try {
      const data = await fetchGlyphDetails(lang, char);
      if (data) {
        activeGlyphData = data;
      }
    } finally {
      isLoading = false;
    }
  }
</script>

<span class="inline-flex flex-wrap items-baseline">
  {#each tokens as token}
    {#if token.chars && token.chars.length > 0}
      {#each token.chars as ch}
        <span
          role="button"
          tabindex="0"
          onclick={(e) => handleCharClick(ch, e)}
          onkeydown={(e) => { if (e.key === 'Enter') handleCharClick(ch, e); }}
          class="transition-transform duration-100 hover:scale-110 active:scale-95 cursor-pointer inline-block"
          style={token.color ? `color: ${token.color};` : ''}
        >
          {ch}
        </span>
      {/each}
    {:else}
      <span
        role="button"
        tabindex="0"
        onclick={(e) => handleCharClick(token.text, e)}
        onkeydown={(e) => { if (e.key === 'Enter') handleCharClick(token.text, e); }}
        class="transition-transform duration-100 hover:scale-110 active:scale-95 cursor-pointer inline-block {token.color ? '' : fallbackClass}"
        style={token.color ? `color: ${token.color};` : ''}
      >
        {token.text}
      </span>
    {/if}
  {/each}
</span>

{#if activeGlyphData}
  <GlyphHologram
    data={activeGlyphData}
    {lang}
    onClose={() => (activeGlyphData = null)}
  />
{/if}