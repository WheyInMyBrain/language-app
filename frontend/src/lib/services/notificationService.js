import { srsStore } from '../stores/srs.svelte.js';
import { metadataStore } from '../stores/metadata.svelte.js';
import { activeLanguage } from '../stores/activeLanguage.svelte.js';
import { TEMPLATES } from './notificationTemplates.js';

/**
 * Pure bitwise Base64 / Base64URL decoder.
 * Avoids WebKit/Safari strict padding exceptions thrown by window.atob.
 */
function base64UrlToUint8Array(base64String) {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  const clean = base64String.trim().replace(/-/g, '+').replace(/_/g, '/').replace(/=/g, '');
  let validBits = 0;
  let bitBuffer = 0;
  const bytes = [];

  for (let i = 0; i < clean.length; i++) {
    const idx = chars.indexOf(clean.charAt(i));
    if (idx === -1) continue;
    bitBuffer = (bitBuffer << 6) | idx;
    validBits += 6;
    if (validBits >= 8) {
      validBits -= 8;
      bytes.push((bitBuffer >>> validBits) & 0xff);
    }
  }
  return new Uint8Array(bytes);
}

class NotificationService {
  constructor() {
    this.swRegistration = null;
    this.checkIntervalId = null;
  }

  get isSupported() {
    return (
      typeof window !== 'undefined' &&
      'Notification' in window &&
      'serviceWorker' in navigator
    );
  }

  get permission() {
    if (!this.isSupported) return 'denied';
    return Notification.permission;
  }

  get isEnabled() {
    if (!this.isSupported) return false;
    return (
      Notification.permission === 'granted' &&
      localStorage.getItem('push_enabled') === 'true'
    );
  }

  /**
   * Initializes Service Worker registration
   */
  async init() {
    if (!this.isSupported) return;

    try {
      this.swRegistration = await navigator.serviceWorker.register('/sw.js', {
        scope: '/'
      });
      await navigator.serviceWorker.ready;
    } catch (err) {
      console.warn('[NOTIFS] Service worker registration failed:', err);
    }
  }

  /**
   * Subscribes device to VAPID Web Push on backend (for closed-app alerts).
   * Relies on clean root path `/api` proxied to backend:3000.
   */
  async subscribeToWebPush() {
    if (!this.isSupported || !('PushManager' in window)) {
      return { ok: false, error: 'PushManager is not supported in this browser' };
    }

    try {
      const reg = await navigator.serviceWorker.ready;

      // 1. Fetch public key from Axum backend (via Vite proxy)
      const keyRes = await fetch('/api/notifications/vapid-key');
      if (!keyRes.ok) {
        throw new Error(`Failed to fetch VAPID key (Status: ${keyRes.status})`);
      }

      const { publicKey } = await keyRes.json();
      if (!publicKey) {
        throw new Error('VAPID public key is empty on the server');
      }

      const serverKey = base64UrlToUint8Array(publicKey);

      // 2. Clear any stale or mismatched subscription
      const existing = await reg.pushManager.getSubscription();
      if (existing) {
        await existing.unsubscribe();
      }

      // 3. Register fresh subscription with browser vendor push server
      const sub = await reg.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: serverKey
      });

      // 4. Extract token fields matching Rust's SubscribeRequest struct
      const subJson = sub.toJSON();
      const payload = {
        endpoint: subJson.endpoint,
        keys: {
          p256dh: subJson.keys?.p256dh || '',
          auth: subJson.keys?.auth || ''
        }
      };

      if (!payload.endpoint || !payload.keys.p256dh || !payload.keys.auth) {
        throw new Error('PushSubscription returned incomplete credentials');
      }

      // 5. Persist to Rust backend SQLite
      const syncRes = await fetch('/api/notifications/subscribe', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
      });

      if (!syncRes.ok) {
        const errDetail = await syncRes.text();
        throw new Error(`Backend registration failed (${syncRes.status}): ${errDetail}`);
      }

      localStorage.setItem('push_enabled', 'true');
      console.info('[PUSH] Device subscription synchronized with SQLite.');
      return { ok: true };
    } catch (err) {
      console.error('[PUSH] WebPush subscription error:', err);
      return { ok: false, error: err.message || String(err) };
    }
  }

  /**
   * Unsubscribes device from PushManager and disables preference
   */
  async unsubscribeFromWebPush() {
    try {
      if ('serviceWorker' in navigator) {
        const reg = await navigator.serviceWorker.ready;
        const sub = await reg.pushManager.getSubscription();
        if (sub) {
          await sub.unsubscribe();
        }
      }
    } catch (err) {
      console.warn('[PUSH] Unsubscribe error:', err);
    }
    this.stopScheduler();
    localStorage.setItem('push_enabled', 'false');
  }

  /**
   * Requests notification permission and registers push
   */
  async requestPermission() {
    if (!this.isSupported) return false;
    const result = await Notification.requestPermission();
    if (result === 'granted') {
      await this.init();
      const subResult = await this.subscribeToWebPush();
      return subResult.ok;
    }
    return false;
  }

  /**
   * Dispatches local notification via SW or Notification constructor
   */
  async dispatch(title, options = {}) {
    if (this.permission !== 'granted') return null;

    const payload = {
      icon: '/favicon.ico',
      badge: '/favicon.ico',
      vibrate: [100, 50, 100],
      ...options
    };

    if (this.swRegistration && 'showNotification' in this.swRegistration) {
      return this.swRegistration.showNotification(title, payload);
    } else {
      const notif = new Notification(title, payload);
      notif.onclick = () => {
        window.focus();
        notif.close();
      };
      return notif;
    }
  }

  _isSentToday(key) {
    const today = new Date().toISOString().slice(0, 10);
    return localStorage.getItem(`notif_sent_${key}`) === today;
  }

  _markSentToday(key) {
    const today = new Date().toISOString().slice(0, 10);
    localStorage.setItem(`notif_sent_${key}`, today);
  }

  _dailySentCount() {
    const today = new Date().toISOString().slice(0, 10);
    const count = localStorage.getItem(`notif_count_${today}`);
    return count ? parseInt(count, 10) : 0;
  }

  _incrementDailyCount() {
    const today = new Date().toISOString().slice(0, 10);
    const next = this._dailySentCount() + 1;
    localStorage.setItem(`notif_count_${today}`, String(next));
  }

  /**
   * Evaluates all local notification rules (for open tabs / active sessions)
   */
  async evaluateReminders(nudgeHour = 19) {
    if (this.permission !== 'granted' || !this.isEnabled) return;
    if (this._dailySentCount() >= 2) return;

    const todayStr = new Date().toISOString().slice(0, 10);
    const currentHour = new Date().getHours();
    const lang = metadataStore.activeLanguage;
    if (!lang) return;

    const goals = activeLanguage.goals || { vocab: 10, listening_minutes: 45 };
    const todayEntry = metadataStore.calendarIndex?.[`${lang}:${todayStr}`] || {};
    const loggedWords = todayEntry.word || 0;
    const loggedListenSec = todayEntry.listening_time || 0;
    const loggedListenMins = Math.round(loggedListenSec / 60);

    const isAllCleared = loggedWords >= goals.vocab && loggedListenMins >= (goals.listening_minutes || 45);

    // 1. Victory Lap (Fires when daily goals are reached)
    if (isAllCleared && !this._isSentToday('victory_lap')) {
      const currentStreak = metadataStore.languages?.[lang]?.current_streak || 1;
      const t = TEMPLATES.all_goals_cleared({ lang, streak: currentStreak });
      await this.dispatch(t.title, { body: t.body, tag: 'victory-lap' });
      this._markSentToday('victory_lap');
      this._incrementDailyCount();
      return;
    }

    // 2. Pending Session Revision Check
    if (!this._isSentToday('session_revision')) {
      const cal = metadataStore.calendarIndex || {};
      const entries = cal instanceof Map ? Array.from(cal.entries()) : Object.entries(cal);
      const prefix = `${lang}:`;

      for (const [k, v] of entries) {
        if (typeof k === 'string' && k.startsWith(prefix) && v) {
          const dateStr = k.slice(prefix.length);
          if (dateStr < todayStr && v.due_date && v.due_date <= todayStr) {
            const nextRev = (v.revision || 0) + 1;
            const t = TEMPLATES.revision_due({ date: dateStr, rev: nextRev });
            await this.dispatch(t.title, { body: t.body, tag: `rev-due-${dateStr}` });
            this._markSentToday('session_revision');
            this._incrementDailyCount();
            return;
          }
        }
      }
    }

    // 3. SRS Due Cards Alert
    if (!this._isSentToday('srs_cards')) {
      const counts = srsStore.getDueCounts ? srsStore.getDueCounts() : { visual: 0, audio: 0 };
      const totalDue = (counts.visual || 0) + (counts.audio || 0);

      if (totalDue > 0) {
        const t = TEMPLATES.srs_due({
          totalDue,
          visualDue: counts.visual || 0,
          audioDue: counts.audio || 0,
          lang
        });
        await this.dispatch(t.title, { body: t.body, tag: 'srs-cards-due' });
        this._markSentToday('srs_cards');
        this._incrementDailyCount();
        return;
      }
    }

    // 4. Evening Nudge or Streak Warning
    if (currentHour >= nudgeHour) {
      if (loggedWords === 0 && loggedListenSec === 0 && !this._isSentToday('streak_warning')) {
        const streak = metadataStore.languages?.[lang]?.current_streak || 0;
        const t = TEMPLATES.streak_warning({ lang, currentStreak: streak });
        await this.dispatch(t.title, { body: t.body, tag: 'streak-warning' });
        this._markSentToday('streak_warning');
        this._incrementDailyCount();
      } else if (!isAllCleared && !this._isSentToday('partial_nudge')) {
        const wordsLeft = Math.max(0, goals.vocab - loggedWords);
        const listenLeft = Math.max(0, (goals.listening_minutes || 45) - loggedListenMins);
        const pct = Math.min(
          99,
          Math.round(
            ((loggedWords / (goals.vocab || 1) +
              loggedListenMins / ((goals.listening_minutes || 45) || 1)) /
              2) *
              100
          )
        );

        const t = TEMPLATES.partial_goal_nudge({
          loggedWords,
          goalWords: goals.vocab,
          loggedListen: loggedListenMins,
          goalListen: goals.listening_minutes || 45,
          wordsLeft,
          listenLeft,
          pct
        });
        await this.dispatch(t.title, { body: t.body, tag: 'partial-nudge' });
        this._markSentToday('partial_nudge');
        this._incrementDailyCount();
      }
    }
  }

  startScheduler(nudgeHour = 19) {
    if (this.checkIntervalId) return;

    this.evaluateReminders(nudgeHour);

    this.checkIntervalId = setInterval(() => {
      this.evaluateReminders(nudgeHour);
    }, 15 * 60 * 1000);
  }

  stopScheduler() {
    if (this.checkIntervalId) {
      clearInterval(this.checkIntervalId);
      this.checkIntervalId = null;
    }
  }
}

export const notificationService = new NotificationService();