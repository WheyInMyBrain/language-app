<!-- frontend/src/components/AudioBar.svelte -->
<script>
  import { onDestroy, tick } from 'svelte';
  import { resolveAudioSource, saveAudioRecord } from '../lib/audioSync.js';
  import { getDocHandle, createSyncedDoc } from '../lib/yjs.js';
  import { metadataStore } from '../lib/stores/metadata.svelte.js';

  import { 
    Play, 
    Pause, 
    Square, 
    Mic, 
    CloudUpload, 
    Sparkles,
    Activity
  } from '@lucide/svelte';

  let {
    lang = 'zh-CN',
    date = '',
    category = 'vocab',
    index = 1,
    initialDuration = 0,
    accentColor = '#10b981',
    accentColorSub = '#34d399',
    type = 'vocab',
    item = {},
    onDurationChange = null
  } = $props();

  let isRecording = $state(false);
  let isPlaying = $state(false);
  let isPendingSync = $state(false);
  let isLoadingAudio = $state(false);
  let elapsedSec = $state(0);
  let playbackProgress = $state(0);
  let currentTimeDisplay = $state('0:00');

  let recordedDuration = $state(null);
  let currentAudioDuration = $derived(recordedDuration ?? (initialDuration || 0));

  let resolvedUrl = $state(null);
  let audioEl = $state(null);
  let timerInterval = null;
  let playbackInterval = null;
  let mediaRecorder = null;
  let recordedChunks = [];

  // Canvas & Web Audio API
  let canvasEl = $state(null);
  let audioCtx = null;
  let analyserNode = null;
  let animFrameId = null;
  let micStream = null;

  function formatTime(s) {
    const mins = Math.floor(s / 60);
    const secs = Math.floor(s % 60);
    return `${mins}:${secs < 10 ? '0' : ''}${secs}`;
  }

  function getSupportedAudioMime() {
    const types = [
      'audio/webm;codecs=opus',
      'audio/webm',
      'audio/mp4',
      'audio/ogg;codecs=opus'
    ];
    for (const t of types) {
      if (typeof MediaRecorder !== 'undefined' && MediaRecorder.isTypeSupported(t)) {
        return t;
      }
    }
    return '';
  }

  function persistDurationLocally(seconds) {
    const roomName = `${lang}:${date}`;
    const handle = getDocHandle(roomName) || createSyncedDoc(roomName);
    if (!handle?.doc) return;

    if (type === 'vocab') {
      const wordsArr = handle.doc.getArray('words');
      const list = wordsArr.toArray().flat();
      const targetIdx = list.findIndex((w) => Number(w.word_index ?? w.id) === Number(index));

      if (targetIdx !== -1) {
        handle.doc.transact(() => {
          const updated = { ...list[targetIdx], audio_duration: seconds };
          wordsArr.delete(targetIdx, 1);
          wordsArr.insert(targetIdx, [updated]);
        });
      }
    } else {
      const actsArr = handle.doc.getArray('activities');
      const list = actsArr.toArray().flat();
      const targetIdx = list.findIndex(
        (a) => a.activity_type === type && Number(a.item_index) === Number(index)
      );

      if (targetIdx !== -1) {
        handle.doc.transact(() => {
          const updated = { ...list[targetIdx], audio_duration: seconds };
          actsArr.delete(targetIdx, 1);
          actsArr.insert(targetIdx, [updated]);
        });
      }
    }

    metadataStore.refreshDayTotals(lang, date);
    if (onDurationChange) onDurationChange(seconds);
  }

  // 🌟 FULL-SPECTRUM BALANCED HUMAN VOICE AUDIOGRAPH 🌟
  async function startVisualizer(stream) {
    await tick();

    if (!canvasEl) return;

    try {
      const AudioContextClass = window.AudioContext || window.webkitAudioContext;
      audioCtx = new AudioContextClass();

      if (audioCtx.state === 'suspended') {
        await audioCtx.resume();
      }

      analyserNode = audioCtx.createAnalyser();
      analyserNode.fftSize = 512;
      analyserNode.smoothingTimeConstant = 0.82; // Butter-smooth spring transition

      const source = audioCtx.createMediaStreamSource(stream);
      source.connect(analyserNode);

      const bufferLength = analyserNode.frequencyBinCount; // 256 bins
      const timeData = new Uint8Array(bufferLength);
      const freqData = new Uint8Array(bufferLength);

      const dpr = window.devicePixelRatio || 1;
      const ctx = canvasEl.getContext('2d');

      // Sync canvas pixel buffers to actual element bounding box
      function updateCanvasBounds() {
        if (!canvasEl) return { width: 340, height: 64 };
        const rect = canvasEl.getBoundingClientRect();
        const w = rect.width || 340;
        const h = rect.height || 64;
        if (canvasEl.width !== w * dpr || canvasEl.height !== h * dpr) {
          canvasEl.width = w * dpr;
          canvasEl.height = h * dpr;
          ctx.scale(dpr, dpr);
        }
        return { width: w, height: h };
      }

      const totalBars = 36;
      // Speech frequencies span bins ~1 to ~48 (approx 85Hz to 4200Hz at 44.1kHz)
      const maxSpeechBin = Math.min(52, bufferLength);
      const minSpeechBin = 2;

      function renderFrame() {
        if (!isRecording) return;
        animFrameId = requestAnimationFrame(renderFrame);

        const { width, height } = updateCanvasBounds();

        analyserNode.getByteTimeDomainData(timeData);
        analyserNode.getByteFrequencyData(freqData);

        ctx.clearRect(0, 0, width, height);

        // 1. Full-Width Vocal Spectrum Bars
        const gap = 2.5;
        const barWidth = (width - (totalBars - 1) * gap) / totalBars;

        for (let i = 0; i < totalBars; i++) {
          // Logarithmic power distribution: maps 0..35 into 2..52
          const factor = Math.pow(i / (totalBars - 1), 1.4);
          const binIndex = Math.floor(minSpeechBin + factor * (maxSpeechBin - minSpeechBin));
          
          // Boost higher vocal harmonics slightly so right side responds with equal energy
          const trebleBoost = 1.0 + (i / totalBars) * 1.6;
          const rawVal = freqData[binIndex] || 0;
          const normalized = Math.min(1.0, (rawVal / 255) * trebleBoost);

          const barHeight = Math.max(3, normalized * (height * 0.78));
          const x = i * (barWidth + gap);
          const y = height - barHeight;

          // Glowing rounded pill bars
          ctx.fillStyle = `color-mix(in srgb, ${accentColor} ${Math.round(25 + normalized * 65)}%, transparent)`;
          ctx.beginPath();
          ctx.roundRect(x, y, barWidth, barHeight, [2, 2, 0, 0]);
          ctx.fill();
        }

        // 2. Continuous Liquid Oscilloscope Ribbon
        ctx.lineWidth = 2.2;
        ctx.strokeStyle = accentColor;
        ctx.shadowColor = accentColor;
        ctx.shadowBlur = 8;
        ctx.beginPath();

        const sliceWidth = width / (bufferLength - 1);
        let curX = 0;

        for (let i = 0; i < bufferLength; i++) {
          const v = timeData[i] / 128.0; // 1.0 = neutral center
          const curY = (v * height) / 2;

          if (i === 0) {
            ctx.moveTo(curX, curY);
          } else {
            ctx.lineTo(curX, curY);
          }
          curX += sliceWidth;
        }

        ctx.stroke();
      }

      renderFrame();
    } catch (err) {
      console.warn('[AudioBar] Visualizer init failed:', err);
    }
  }

  function stopVisualizer() {
    if (animFrameId) {
      cancelAnimationFrame(animFrameId);
      animFrameId = null;
    }
    if (audioCtx && audioCtx.state !== 'closed') {
      audioCtx.close().catch(() => {});
      audioCtx = null;
    }
  }

  async function toggleRecord() {
    if (isRecording) {
      if (timerInterval) clearInterval(timerInterval);
      mediaRecorder?.stop();
      isRecording = false;
      stopVisualizer();
      return;
    }

    try {
      micStream = await navigator.mediaDevices.getUserMedia({ 
        audio: {
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: true
        }
      });
      recordedChunks = [];
      
      const mimeType = getSupportedAudioMime();
      const options = { audioBitsPerSecond: 32000 };
      if (mimeType) options.mimeType = mimeType;

      mediaRecorder = new MediaRecorder(micStream, options);

      mediaRecorder.ondataavailable = (e) => {
        if (e.data.size > 0) recordedChunks.push(e.data);
      };

      mediaRecorder.onstop = async () => {
        micStream?.getTracks().forEach((t) => t.stop());
        const blob = new Blob(recordedChunks, { type: mediaRecorder.mimeType || 'audio/webm' });
        const finalDuration = elapsedSec || 1;

        if (resolvedUrl && resolvedUrl.startsWith('blob:')) {
          URL.revokeObjectURL(resolvedUrl);
        }

        resolvedUrl = URL.createObjectURL(blob);
        recordedDuration = finalDuration;
        isPendingSync = true;

        persistDurationLocally(finalDuration);

        const wasUploaded = await saveAudioRecord({
          lang,
          date,
          category,
          index: item.word_index ?? item.item_index ?? item.id ?? index,
          blob,
          duration: finalDuration
        });

        if (wasUploaded) {
          isPendingSync = false;
        }
      };

      mediaRecorder.start();
      isRecording = true;
      elapsedSec = 0;
      timerInterval = setInterval(() => {
        elapsedSec += 1;
      }, 1000);

      // Start the canvas visualizer loop
      startVisualizer(micStream);
    } catch (err) {
      console.error('Mic access error:', err);
      alert('Microphone permission required for audio recordings.');
    }
  }

  async function togglePlayback() {
    if (isPlaying && audioEl) {
      audioEl.pause();
      isPlaying = false;
      if (playbackInterval) clearInterval(playbackInterval);
      return;
    }

    if (!resolvedUrl) {
      isLoadingAudio = true;
      try {
        const itemIdx = item.word_index ?? item.item_index ?? item.id ?? index;
        const res = await resolveAudioSource(lang, date, category, itemIdx, currentAudioDuration);
        resolvedUrl = res.url;
        isPendingSync = res.isPendingSync;
      } finally {
        isLoadingAudio = false;
      }
    }

    setTimeout(() => {
      if (!audioEl) return;
      audioEl.play().then(() => {
        isPlaying = true;
        playbackInterval = setInterval(() => {
          if (audioEl) {
            currentTimeDisplay = formatTime(audioEl.currentTime);
            playbackProgress = (audioEl.currentTime / (audioEl.duration || currentAudioDuration)) * 100;
          }
        }, 100);
      }).catch((err) => {
        console.error('Audio playback error:', err);
        isPlaying = false;
      });
    }, 0);
  }

  onDestroy(() => {
    if (timerInterval) clearInterval(timerInterval);
    if (playbackInterval) clearInterval(playbackInterval);
    if (audioEl) audioEl.pause();
    if (resolvedUrl && resolvedUrl.startsWith('blob:')) {
      URL.revokeObjectURL(resolvedUrl);
    }
    stopVisualizer();
    micStream?.getTracks().forEach((t) => t.stop());
  });
</script>

{#if resolvedUrl}
  <audio
    bind:this={audioEl}
    src={resolvedUrl}
    onended={() => { isPlaying = false; playbackProgress = 0; }}
    preload="none"
  ></audio>
{/if}

<div class="p-3.5 rounded-2xl bg-[var(--bg-base)]/80 border border-[var(--border-subtle)] space-y-3 shadow-inner relative overflow-hidden backdrop-blur-md">
  
  <div class="flex items-center justify-between gap-3 relative z-10">
    <div class="flex items-center gap-2">
      {#if isRecording}
        <div class="flex items-center gap-1.5 px-2.5 py-1 rounded-full bg-rose-500/10 border border-rose-500/20 shadow-xs">
          <span class="w-2 h-2 rounded-full bg-rose-500 animate-ping"></span>
          <span class="text-xs font-mono font-black text-rose-400">
            REC {formatTime(elapsedSec)}
          </span>
        </div>
      {:else if currentAudioDuration > 0}
        <button
          type="button"
          onclick={togglePlayback}
          disabled={isLoadingAudio}
          class="flex items-center justify-center w-8 h-8 rounded-xl bg-[var(--bg-surface)] hover:bg-[var(--bg-surface-elevated)] border border-[var(--border-subtle)] text-[var(--text-primary)] transition-transform active:scale-90 disabled:opacity-50 cursor-pointer shadow-xs"
        >
          {#if isLoadingAudio}
            <Sparkles size={14} class="animate-spin text-amber-400" />
          {:else if isPlaying}
            <Pause size={14} strokeWidth={2.8} />
          {:else}
            <Play size={14} strokeWidth={2.8} class="ml-0.5" />
          {/if}
        </button>

        <div class="space-y-0.5">
          <span class="text-xs font-mono font-bold text-[var(--text-primary)] block">
            {isPlaying ? currentTimeDisplay : formatTime(currentAudioDuration)}
          </span>
          {#if isPendingSync}
            <span class="text-[9px] font-mono text-amber-400 flex items-center gap-1">
              <CloudUpload size={10} /> Syncing
            </span>
          {/if}
        </div>
      {:else}
        <span class="text-xs font-mono text-[var(--text-muted)] italic flex items-center gap-1.5">
          <Activity size={12} class="opacity-60" />
          Ready to record
        </span>
      {/if}
    </div>

    <button
      type="button"
      onclick={toggleRecord}
      class="flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-xs font-bold transition-all active:scale-90 cursor-pointer shadow-md {isRecording 
        ? 'bg-rose-500 hover:bg-rose-600 text-white ring-2 ring-rose-400/30' 
        : 'bg-[var(--bg-surface)] hover:bg-[var(--bg-surface-elevated)] text-[var(--text-primary)] border border-[var(--border-subtle)]'}"
    >
      {#if isRecording}
        <Square size={12} fill="currentColor" />
        <span>Stop</span>
      {:else}
        <Mic size={13} style="color: {accentColor};" />
        <span>{currentAudioDuration > 0 ? 'Re-record' : 'Record'}</span>
      {/if}
    </button>
  </div>

  <!-- 🌟 LIVE AUDIOGRAPH CANVAS 🌟 -->
  {#if isRecording}
    <div class="relative w-full h-16 rounded-xl overflow-hidden bg-black/50 border border-white/10 flex items-center justify-center shadow-inner">
      <canvas
        bind:this={canvasEl}
        class="w-full h-full block"
      ></canvas>
      <div class="pointer-events-none absolute inset-x-0 top-1/2 h-px bg-white/10 border-b border-dashed border-white/20"></div>
    </div>
  {/if}

  {#if currentAudioDuration > 0 && !isRecording}
    <div class="w-full h-1.5 rounded-full bg-[var(--bg-surface)] overflow-hidden relative border border-[var(--border-subtle)]">
      <div 
        class="h-full rounded-full transition-all duration-150"
        style="width: {playbackProgress}%; background: linear-gradient(90deg, {accentColor}, {accentColorSub});"
      ></div>
    </div>
  {/if}

</div>