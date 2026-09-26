<!-- frontend/src/components/Mascot.svelte -->
<script>
  import { metadataStore } from '../lib/stores/metadata.svelte.js';
  import { activeLanguage } from '../lib/stores/activeLanguage.svelte.js';
  import { srsStore } from '../lib/stores/srs.svelte.js';
  import { uploadProgressStore } from '../lib/stores/uploadProgress.svelte.js';
  import { recordingStore } from '../lib/stores/recordingStore.svelte.js';

  let { activeRoute = 'dashboard' } = $props();

  let activeLangCode = $derived(metadataStore.activeLanguage);
  let activeLangConfig = $derived(activeLanguage.current);
  let streak = $derived(activeLangConfig?.current_streak || 0);

  let totalDue = $derived.by(() => {
    if (!srsStore.getDueCounts) return 0;
    const counts = srsStore.getDueCounts();
    return (counts.audio || 0) + (counts.visual || 0);
  });

  let isRecording = $derived(recordingStore.isRecording);
  let pendingAudios = $derived(uploadProgressStore.pendingCount);
  let isUploading = $derived(uploadProgressStore.isUploading);

  function getTodayString() {
    const d = new Date();
    const year = d.getFullYear();
    const month = String(d.getMonth() + 1).padStart(2, '0');
    const day = String(d.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
  }
  const todayStr = getTodayString();

  let todayStat = $derived.by(() => {
    const cal = metadataStore.calendarIndex;
    if (!cal || !activeLangCode) return { word: 0, ci: 0, listening: 0 };
    const val = cal instanceof Map 
      ? cal.get(`${activeLangCode}:${todayStr}`) 
      : cal[`${activeLangCode}:${todayStr}`];
    return val || { word: 0, ci: 0, listening: 0 };
  });

  let todayItemsCount = $derived((todayStat.word || 0) + (todayStat.ci || 0) + (todayStat.listening || 0));

  // 🌟 REACTIVE KAOMOJI BEHAVIOR MATRIX (Zero Text, 100% Expressive) 🌟
  let mascot = $derived.by(() => {
    // 1. Actively Speaking / Recording into the Mic
    if (isRecording) {
      return {
        face: '(ง •̀_•́)ง',
        acc: '🎙️',
        anim: 'anim-soundwave',
        bg: 'bg-rose-500/25 dark:bg-rose-500/30',
        border: 'border-rose-400',
        glow: 'shadow-[0_0_24px_rgba(244,63,94,0.6)]',
        color: 'text-rose-500 dark:text-rose-300'
      };
    }

    // 2. Transmitting / Syncing Audio Packets to Server
    if (isUploading || pendingAudios > 0) {
      return {
        face: '(っ•̀-•́)っ',
        acc: '📦📡',
        anim: 'anim-packet-transmit',
        bg: 'bg-amber-500/20 dark:bg-amber-500/25',
        border: 'border-amber-400',
        glow: 'shadow-[0_0_22px_rgba(245,158,11,0.5)]',
        color: 'text-amber-500 dark:text-amber-300'
      };
    }

    // 3. Spaced Repetition / Flashcard Arena
    if (activeRoute === 'quiz') {
      return {
        face: '( •̀ ᴗ •́ )و',
        acc: '⚡',
        anim: 'anim-flash-hop',
        bg: 'bg-indigo-500/20 dark:bg-indigo-500/25',
        border: 'border-indigo-400',
        glow: 'shadow-[0_0_20px_rgba(99,102,241,0.5)]',
        color: 'text-indigo-500 dark:text-indigo-300'
      };
    }

    // 4. Video / Media Immersion Library
    if (activeRoute === 'library') {
      return {
        face: '( ˶ˆᗜˆ˵ )',
        acc: '🍿',
        anim: 'anim-sway',
        bg: 'bg-purple-500/20 dark:bg-purple-500/25',
        border: 'border-purple-400',
        glow: 'shadow-[0_0_20px_rgba(168,85,247,0.45)]',
        color: 'text-purple-500 dark:text-purple-300'
      };
    }

    // 5. Daily Logging Canvas
    if (activeRoute === 'day') {
      return {
        face: '(๑•̀ㅂ•́)و',
        acc: '✍️',
        anim: 'anim-scribble',
        bg: 'bg-sky-500/20 dark:bg-sky-500/25',
        border: 'border-sky-400',
        glow: 'shadow-[0_0_20px_rgba(14,165,233,0.45)]',
        color: 'text-sky-500 dark:text-sky-300'
      };
    }

    // 6. Overdrive / God Mode: Streak >= 3 + Queue Cleared + Active Progress
    if (streak >= 3 && totalDue === 0 && todayItemsCount >= 5) {
      return {
        face: '(ง🔥ᗜ🔥)ง',
        acc: '👑',
        anim: 'anim-hyper',
        bg: 'bg-gradient-to-r from-amber-500/30 to-rose-500/30',
        border: 'border-amber-400',
        glow: 'shadow-[0_0_30px_rgba(245,158,11,0.7)]',
        color: 'text-amber-400'
      };
    }

    // 7. High SRS Debt Backlog & 0 Progress Today
    if (totalDue > 25 && todayItemsCount === 0) {
      return {
        face: '( ;´ - `; )',
        acc: '💦',
        anim: 'anim-sweat-drop',
        bg: 'bg-orange-500/15 dark:bg-orange-500/20',
        border: 'border-orange-400/50',
        glow: 'shadow-[0_0_12px_rgba(249,115,22,0.3)]',
        color: 'text-orange-500 dark:text-orange-300'
      };
    }

    // 8. Dormant / Lazy Start (0 words logged today)
    if (todayItemsCount === 0) {
      return {
        face: '(ᴗ_ ᴗ。)zzZ',
        acc: '☕',
        anim: 'anim-snooze',
        bg: 'bg-black/5 dark:bg-white/[0.04]',
        border: 'border-black/10 dark:border-white/10',
        glow: 'shadow-none',
        color: 'text-neutral-400 dark:text-neutral-500'
      };
    }

    // 9. Standard Warm Baseline
    return {
      face: '(˶ᵔ ᵕ ᵔ˶)',
      acc: '🌸',
      anim: 'anim-float-gentle',
      bg: 'bg-emerald-500/20 dark:bg-emerald-500/25',
      border: 'border-emerald-400',
      glow: 'shadow-[0_0_18px_rgba(16,185,129,0.4)]',
      color: 'text-emerald-500 dark:text-emerald-300'
    };
  });
</script>

<!-- 🌟 PURE EXPRESSIVE KAOMOJI COCKPIT POD 🌟 -->
<div 
  class="relative flex items-center justify-center px-3.5 py-1.5 rounded-2xl border backdrop-blur-2xl transition-all duration-300 select-none {mascot.bg} {mascot.border} {mascot.glow} cursor-pointer active:scale-95 hover:scale-105"
  title="Companion Status"
>
  <div class="font-mono text-sm sm:text-base font-black tracking-tight {mascot.color} flex items-center gap-1.5 whitespace-nowrap">
    <span class="inline-block {mascot.anim}">{mascot.face}</span>
    <span class="text-xs sm:text-sm drop-shadow-sm inline-block">{mascot.acc}</span>
  </div>

  <!-- Caustic top specular glass glint -->
  <div class="pointer-events-none absolute inset-x-0 top-0 h-[1.5px] rounded-t-2xl bg-gradient-to-r from-transparent via-white/50 to-transparent opacity-70"></div>
</div>

<style>
  /* 🌟 Dynamic Sound Wave Vibration (When Mic is active) 🌟 */
  @keyframes soundwave {
    0%, 100% { transform: scale(1) translateY(0); }
    25% { transform: scale(1.08) translateY(-1px); }
    75% { transform: scale(0.96) translateY(1px); }
  }

  /* 🌟 Packet Transmit Shove (When syncing to server) 🌟 */
  @keyframes packetTransmit {
    0%, 100% { transform: translateX(0); }
    40% { transform: translateX(3px); }
    60% { transform: translateX(-1px); }
  }

  /* 🌟 Flashcard Arena Pop 🌟 */
  @keyframes flashHop {
    0%, 100% { transform: translateY(0); }
    50% { transform: translateY(-3px) scale(1.03); }
  }

  /* 🌟 Media Immersion Sway 🌟 */
  @keyframes sway {
    0%, 100% { transform: rotate(0deg); }
    33% { transform: rotate(-4deg); }
    66% { transform: rotate(4deg); }
  }

  /* 🌟 Scribbling Rhythm 🌟 */
  @keyframes scribble {
    0%, 100% { transform: translate(0, 0); }
    25% { transform: translate(1px, -1.5px); }
    75% { transform: translate(-1px, 1px); }
  }

  /* 🌟 Overdrive Hyper Bounce 🌟 */
  @keyframes hyper {
    0%, 100% { transform: scale(1) rotate(0deg); }
    25% { transform: scale(1.08) rotate(-3deg); }
    75% { transform: scale(1.08) rotate(3deg); }
  }

  /* 🌟 Sweat Drops / Shiver 🌟 */
  @keyframes sweatDrop {
    0%, 100% { transform: translateX(0); }
    20% { transform: translateX(-1px); }
    40% { transform: translateX(1px); }
    60% { transform: translateX(-1px); }
    80% { transform: translateX(1px); }
  }

  /* 🌟 Snooze Respiration 🌟 */
  @keyframes snooze {
    0%, 100% { transform: scale(1); opacity: 0.75; }
    50% { transform: scale(1.03) translateY(1px); opacity: 1; }
  }

  /* 🌟 Gentle Idle Float 🌟 */
  @keyframes floatGentle {
    0%, 100% { transform: translateY(0); }
    50% { transform: translateY(-2px); }
  }

  .anim-soundwave { animation: soundwave 0.35s ease-in-out infinite; }
  .anim-packet-transmit { animation: packetTransmit 0.7s ease-in-out infinite; }
  .anim-flash-hop { animation: flashHop 1.6s ease-in-out infinite; }
  .anim-sway { animation: sway 2.8s ease-in-out infinite; }
  .anim-scribble { animation: scribble 0.8s ease-in-out infinite; }
  .anim-hyper { animation: hyper 0.5s ease-in-out infinite; }
  .anim-sweat-drop { animation: sweatDrop 1s ease-in-out infinite; }
  .anim-snooze { animation: snooze 3.6s ease-in-out infinite; }
  .anim-float-gentle { animation: floatGentle 2.2s ease-in-out infinite; }
</style>