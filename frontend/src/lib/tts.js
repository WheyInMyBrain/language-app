/**
 * frontend/src/lib/tts.js
 * Hardware-native TTS engine with iOS/WebKit audio context priming
 */

function cleanPronounceText(text) {
  if (!text) return '';
  return text
    .replace(/<[^>]*>/g, '')
    .replace(/[.,/#!$%\^&\*;:{}=\-_`~()…—·、，。！？／\s]/g, '')
    .trim();
}

/**
 * Resolves the best available local voice on the device
 */
function getBestVoice(langCode) {
  if (!('speechSynthesis' in window)) return null;
  const voices = window.speechSynthesis.getVoices();
  const prefix = langCode.split('-')[0].toLowerCase();

  // 1. Exact match (e.g. zh-CN)
  let voice = voices.find((v) => v.lang.toLowerCase() === langCode.toLowerCase());
  if (voice) return voice;

  // 2. Prefix match (e.g. zh)
  voice = voices.find((v) => v.lang.toLowerCase().startsWith(prefix));
  return voice || null;
}

export function playTTS(text, langCode) {
  const cleanWord = cleanPronounceText(text);
  if (!cleanWord || !('speechSynthesis' in window)) return;

  // 1. Immediately halt any active or queued speech
  window.speechSynthesis.cancel();

  const utterance = new SpeechSynthesisUtterance(cleanWord);
  utterance.lang = langCode;
  utterance.rate = 0.88; // Natural, clear teaching pace
  utterance.pitch = 1.0;

  const voice = getBestVoice(langCode);
  if (voice) {
    utterance.voice = voice;
  }

  // 2. WebKit / iOS unlock workaround:
  // If voices haven't loaded yet, ensure speech speaks when voices populate
  if (window.speechSynthesis.getVoices().length === 0) {
    window.speechSynthesis.onvoiceschanged = () => {
      const v = getBestVoice(langCode);
      if (v) utterance.voice = v;
      window.speechSynthesis.speak(utterance);
    };
    return;
  }

  // 3. Direct synchronous execution preserves user gesture token
  window.speechSynthesis.speak(utterance);
}