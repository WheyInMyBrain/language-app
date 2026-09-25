/**
 * frontend/src/lib/services/videoTimerService.js
 * Dedicated controller for handling media timers, auto-detecting pasted timestamps,
 * and standardizing payloads across OmniBar and OmniCard.
 */
import { 
  canonicalizeVideoUrl, 
  parseTimerToSeconds, 
  formatSecondsToTimer,
  extractUrlTimestamp
} from '../mediaResolver.js';

export class VideoTimerService {
  /**
   * Called when a user inputs/pastes a URL into the link field.
   * If a duration is not yet entered, inspects the URL for timestamp params (?t=...).
   */
  static handleUrlInput(rawUrl, currentDurationStr) {
    const cleanUrl = canonicalizeVideoUrl(rawUrl);
    
    // If the user hasn't typed a duration yet, check for ?t= parameter
    if (!currentDurationStr || currentDurationStr.trim() === '') {
      const embeddedSec = extractUrlTimestamp(rawUrl);
      if (embeddedSec > 0) {
        return {
          cleanUrl,
          suggestedDuration: formatSecondsToTimer(embeddedSec),
          seconds: embeddedSec
        };
      }
    }

    return {
      cleanUrl,
      suggestedDuration: currentDurationStr,
      seconds: parseTimerToSeconds(currentDurationStr)
    };
  }

  /**
   * Sanitizes and parses duration input from the user.
   */
  static parseDuration(durationInput) {
    return parseTimerToSeconds(durationInput);
  }

  /**
   * Formats stored seconds into timer display string.
   */
  static formatDuration(seconds) {
    return formatSecondsToTimer(seconds);
  }

  /**
   * Creates a normalized activity payload with ALL expected duration keys.
   * Fixes the durationSec vs link_duration bug across Yjs and stores.
   */
  static createActivityPayload({ link, durationInput, extra = {} }) {
    const cleanUrl = canonicalizeVideoUrl(link);
    const durationSec = parseTimerToSeconds(durationInput);

    return {
      link: cleanUrl,
      link_duration: durationSec, // Standardized key for OmniCard, SRSBar, hudStats
      durationSec,                // Backward-compatibility key
      ...extra
    };
  }
}