PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
PRAGMA busy_timeout = 5000;
PRAGMA mmap_size = 268435456;

-- 1. Languages (Includes colors and tones so UI styling persists across devices)
CREATE TABLE IF NOT EXISTS languages (
  code TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  goals_json TEXT NOT NULL DEFAULT '{}',
  milestones_json TEXT NOT NULL DEFAULT '{}',
  momentum_json TEXT NOT NULL DEFAULT '{}',
  colors_json TEXT NOT NULL DEFAULT '{}',
  tones_json TEXT NOT NULL DEFAULT '{}',
  current_streak INTEGER NOT NULL DEFAULT 0,
  longest_streak INTEGER NOT NULL DEFAULT 0,
  total_days INTEGER NOT NULL DEFAULT 0,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER DEFAULT NULL
);

-- 2. Daily Logs (Clean single primary key; removed duplicate B-Tree index)
CREATE TABLE IF NOT EXISTS daily_logs (
  id TEXT PRIMARY KEY,             -- `${lang_code}:${log_date}`
  lang_code TEXT NOT NULL,
  log_date TEXT NOT NULL,          -- 'YYYY-MM-DD'
  due_date TEXT,
  ease REAL NOT NULL DEFAULT 2.50,
  interval INTEGER NOT NULL DEFAULT 0,
  revision INTEGER NOT NULL DEFAULT 0,

  -- Explicit metric aggregates
  word INTEGER NOT NULL DEFAULT 0,
  ci INTEGER NOT NULL DEFAULT 0,
  grammar INTEGER NOT NULL DEFAULT 0,
  listening INTEGER NOT NULL DEFAULT 0,
  speaking_time REAL NOT NULL DEFAULT 0.0,
  listening_time REAL NOT NULL DEFAULT 0.0,

  -- Goal threshold completion flags (1 = complete, 0 = pending)
  vocab_done INTEGER NOT NULL DEFAULT 0,
  ci_done INTEGER NOT NULL DEFAULT 0,
  listening_done INTEGER NOT NULL DEFAULT 0,
  speaking_done INTEGER NOT NULL DEFAULT 0,
  grammar_done INTEGER NOT NULL DEFAULT 0,

  -- Review & recall milestone completion counts
  srs_vision_done INTEGER NOT NULL DEFAULT 0,
  srs_listen_done INTEGER NOT NULL DEFAULT 0,
  srs_write_done INTEGER NOT NULL DEFAULT 0,
  revisions_done INTEGER NOT NULL DEFAULT 0,

  -- Audio deficit telemetry
  unvoiced_words_json TEXT NOT NULL DEFAULT '[]',
  unvoiced_ci_json TEXT NOT NULL DEFAULT '[]',
  unvoiced_listening_json TEXT NOT NULL DEFAULT '[]',
  unvoiced_grammar_json TEXT NOT NULL DEFAULT '[]',

  updated_at INTEGER NOT NULL,
  deleted_at INTEGER DEFAULT NULL
);

-- 3. Words (Individual logged vocabulary entries)
CREATE TABLE IF NOT EXISTS words (
  id TEXT PRIMARY KEY,             -- UUIDv7 generated on client
  lang_code TEXT NOT NULL,
  log_date TEXT NOT NULL,          -- 'YYYY-MM-DD'
  word_index INTEGER NOT NULL,
  native_script TEXT NOT NULL,
  pronunciation TEXT NOT NULL,
  link TEXT,
  audio_duration REAL NOT NULL DEFAULT 0.0,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER DEFAULT NULL
);

-- 4. Activities (CI videos, audio immersion, grammar patterns)
CREATE TABLE IF NOT EXISTS activities (
  id TEXT PRIMARY KEY,             -- UUIDv7 generated on client
  lang_code TEXT NOT NULL,
  log_date TEXT NOT NULL,          -- 'YYYY-MM-DD'
  activity_type TEXT NOT NULL,     -- 'ci' | 'listening' | 'grammar'
  item_index INTEGER NOT NULL DEFAULT 1,
  link TEXT,
  link_duration REAL NOT NULL DEFAULT 0.0,
  audio_duration REAL NOT NULL DEFAULT 0.0,
  metadata_json TEXT NOT NULL DEFAULT '{}',
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER DEFAULT NULL
);

-- 5. Word SRS (Granular spaced-repetition card state)
CREATE TABLE IF NOT EXISTS word_srs (
  card_key TEXT PRIMARY KEY,       -- `${lang_code}:${word_id}:${card_type}`
  lang_code TEXT NOT NULL,
  word_id TEXT NOT NULL,
  card_type TEXT NOT NULL,         -- 'visual' | 'listening' | 'writing'
  native_script TEXT NOT NULL,
  pronunciation TEXT,
  due_date TEXT NOT NULL,          -- 'YYYY-MM-DD'
  interval INTEGER NOT NULL DEFAULT 0,
  ease REAL NOT NULL DEFAULT 2.50,
  reps INTEGER NOT NULL DEFAULT 0,
  lapses INTEGER NOT NULL DEFAULT 0,
  last_reviewed TEXT,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER DEFAULT NULL
);

-- 6. Push Subscriptions (Web Push Notification device targets)
CREATE TABLE IF NOT EXISTS push_subscriptions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  endpoint TEXT NOT NULL UNIQUE,
  p256dh TEXT NOT NULL,
  auth TEXT NOT NULL,
  created_at TEXT DEFAULT (datetime('now'))
);

-- Performance & Sync Delta Indexes
-- Global delta sync index (used when lang parameter is omitted)
CREATE INDEX IF NOT EXISTS idx_languages_sync ON languages(updated_at);
CREATE INDEX IF NOT EXISTS idx_daily_logs_updated ON daily_logs(updated_at);
CREATE INDEX IF NOT EXISTS idx_words_updated ON words(updated_at);
CREATE INDEX IF NOT EXISTS idx_activities_updated ON activities(updated_at);
CREATE INDEX IF NOT EXISTS idx_word_srs_updated ON word_srs(updated_at);

-- Scoped query indexes (used during per-language day and history queries)
CREATE INDEX IF NOT EXISTS idx_daily_logs_lookup ON daily_logs(lang_code, log_date);
CREATE INDEX IF NOT EXISTS idx_words_lookup ON words(lang_code, log_date);
CREATE INDEX IF NOT EXISTS idx_activities_lookup ON activities(lang_code, log_date, activity_type);
CREATE INDEX IF NOT EXISTS idx_word_srs_due ON word_srs(lang_code, due_date, card_type);