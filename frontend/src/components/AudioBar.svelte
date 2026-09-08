<!-- frontend/src/components/AudioBar.svelte -->
<script>
  import { onDestroy } from 'svelte';
  import { getDocHandle, createSyncedDoc } from '../lib/yjs.js';
  import { resolveAudioSource, saveAudioRecord } from '../lib/audioSync.js';
  import { metadataStore } from '../lib/stores/metadata.svelte.js';

  let {
    lang = 'zh-CN',
    date = '',
    category = 'vocab',
    index = 1,
    audioDuration = 0,
    accentColor = '#2e7d32',
    buttonLabel = 'Voice Note'
  } = $props();

  let isRecording = $state(false);
  let isPlaying = $state(false);
  let isPendingSync = $state(false);
  let isLoadingAudio = $state(false);
  let elapsedSec = $state(0);
  
  // Local session override for freshly recorded audio
  let recordedDuration = $state(null);
  let currentDuration = $derived(recordedDuration ?? audioDuration);

  // resolvedUrl stays null until recording finishes or user clicks Play
  let resolvedUrl = $state(null);

  let audioEl = $state(null);
  let timerInterval = null;
  let mediaRecorder = null;
  let recordedChunks = [];

  onDestroy(() => {
    if (timerInterval) clearInterval(timerInterval);
    if (audioEl) audioEl.pause();
  });

  function formatTime(s) {
    const mins = Math.floor(s / 60);
    const secs = Math.floor(s % 60);
    return `${mins}:${secs < 10 ? '0' : ''}${secs}`;
  }

  function persistDurationLocally(seconds) {
    const roomName = `${lang}:${date}`;
    const handle = getDocHandle(roomName) || createSyncedDoc(roomName);
    if (!handle?.doc) return;

    if (category === 'vocab' || category === 'words') {
      const wordsArr = handle.doc.getArray('words');
      const list = wordsArr.toArray().flat();
      const targetIdx = list.findIndex((w) => Number(w.word_index ?? w.id) === Number(index));

      if (targetIdx !== -1) {
        handle.doc.transact(() => {
          const item = { ...list[targetIdx], audio_duration: seconds };
          wordsArr.delete(targetIdx, 1);
          wordsArr.insert(targetIdx, [item]);
        });
      }
    } else {
      const actsArr = handle.doc.getArray('activities');
      const list = actsArr.toArray().flat();
      const targetIdx = list.findIndex(
        (a) => a.activity_type === category && Number(a.item_index) === Number(index)
      );

      if (targetIdx !== -1) {
        handle.doc.transact(() => {
          const item = { ...list[targetIdx], audio_duration: seconds };
          actsArr.delete(targetIdx, 1);
          actsArr.insert(targetIdx, [item]);
        });
      }
    }

    metadataStore.refreshDayTotals(lang, date);
  }

  async function toggleRecord() {
    if (isRecording) {
      if (timerInterval) clearInterval(timerInterval);
      mediaRecorder?.stop();
      isRecording = false;
      return;
    }

    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      recordedChunks = [];
      mediaRecorder = new MediaRecorder(stream, { mimeType: 'audio/webm' });

      mediaRecorder.ondataavailable = (e) => {
        if (e.data.size > 0) recordedChunks.push(e.data);
      };

      mediaRecorder.onstop = async () => {
        stream.getTracks().forEach((t) => t.stop());
        const blob = new Blob(recordedChunks, { type: 'audio/webm' });
        const finalDuration = elapsedSec || 1;

        // Instant local preview
        resolvedUrl = URL.createObjectURL(blob);
        recordedDuration = finalDuration;
        isPendingSync = true;

        persistDurationLocally(finalDuration);

        const wasUploaded = await saveAudioRecord({
          lang,
          date,
          category,
          index,
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
    } catch (err) {
      console.error('Mic access error:', err);
      alert('Microphone permission required for voice notes.');
    }
  }

  async function togglePlayback() {
    if (isPlaying && audioEl) {
      audioEl.pause();
      isPlaying = false;
      return;
    }

    // Lazy load audio source on demand
    if (!resolvedUrl) {
      isLoadingAudio = true;
      try {
        const res = await resolveAudioSource(lang, date, category, index, currentDuration);
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
      }).catch((err) => {
        console.error('Audio playback error:', err);
        isPlaying = false;
      });
    }, 0);
  }
</script>

<div class="flex items-center justify-between gap-3 pt-3 border-t border-[var(--border-card)] w-full select-none">
  <!-- Left Side: Player / Status -->
  <div class="flex items-center gap-2 min-w-0">
    {#if currentDuration > 0}
      {#if resolvedUrl}
        <audio
          bind:this={audioEl}
          src={resolvedUrl}
          onended={() => (isPlaying = false)}
          onerror={(e) => console.warn('[Audio Playback Error]', e)}
          preload="none"
        ></audio>
      {/if}

      <button
        type="button"
        onclick={togglePlayback}
        disabled={isLoadingAudio}
        class="flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-xs font-bold border border-[var(--border-card)] bg-[var(--bg-surface)] hover:border-[var(--border-hover)] text-[var(--text-primary)] cursor-pointer transition-colors active:scale-95 disabled:opacity-50"
      >
        <span>{isLoadingAudio ? '⏳' : isPlaying ? '⏸️' : '▶️'}</span>
        <span>{isLoadingAudio ? 'Loading...' : isPlaying ? 'Pause' : 'Play Note'}</span>
      </button>

      <span class="text-[11px] font-mono text-[var(--text-muted)]">
        {formatTime(currentDuration)}
      </span>

      {#if isPendingSync}
        <span
          class="text-[10px] font-mono font-bold text-amber-500 bg-amber-500/10 px-1.5 py-0.5 rounded border border-amber-500/30"
          title="Cached locally, syncing to server..."
        >
          ☁️ Syncing
        </span>
      {/if}
    {:else}
      <span class="text-xs text-[var(--text-muted)] italic">
        No {buttonLabel.toLowerCase()} recorded.
      </span>
    {/if}
  </div>

  <!-- Right Side: Record Trigger -->
  <button
    type="button"
    onclick={toggleRecord}
    class="flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-xs font-bold text-white transition-transform duration-75 active:scale-95 cursor-pointer shrink-0 border-none"
    style="background-color: {isRecording ? '#ef4444' : accentColor};"
  >
    <span>{isRecording ? '🔴' : '🎙️'}</span>
    <span>
      {isRecording
        ? `${formatTime(elapsedSec)} (Stop)`
        : currentDuration > 0
          ? 'Re-record'
          : buttonLabel}
    </span>
  </button>
</div>