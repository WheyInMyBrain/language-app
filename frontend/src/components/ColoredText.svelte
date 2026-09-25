<script>
  let { tokens = [], fallbackClass = '' } = $props();
</script>

<span class="inline-flex items-baseline justify-center whitespace-pre max-w-full font-inherit tracking-normal selection:bg-white/20">
  {#each tokens as token}
    <span
      style={token.color 
        ? `
            color: ${token.color};
            text-shadow: 
              0 0 12px color-mix(in srgb, ${token.color} 30%, transparent),
              0 1px 2px rgba(0, 0, 0, 0.45);
          ` 
        : ''}
      class="inline-block transition-colors duration-150 ease-out {!token.color ? fallbackClass : ''}"
    >{token.text}</span>
  {/each}
</span>