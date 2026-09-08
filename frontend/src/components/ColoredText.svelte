<script>
  let { tokens = [], fallbackClass = '' } = $props();
</script>

<span class="inline-flex items-baseline justify-center whitespace-pre max-w-full">
  {#each tokens as token}
    <span style={token.color ? `color: ${token.color};` : ''} class={!token.color ? fallbackClass : ''}>{token.text}</span>
  {/each}
</span>