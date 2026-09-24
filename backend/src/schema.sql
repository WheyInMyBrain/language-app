PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS languages (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  code TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS daily_logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  language_id INTEGER NOT NULL REFERENCES languages(id) ON DELETE CASCADE,
  log_date TEXT NOT NULL,
  due_date TEXT,
  ease REAL,
  interval INTEGER,
  UNIQUE(language_id, log_date)
);

CREATE TABLE IF NOT EXISTS log_revisions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  language_id INTEGER NOT NULL REFERENCES languages(id) ON DELETE CASCADE,
  log_id INTEGER NOT NULL REFERENCES daily_logs(id) ON DELETE CASCADE,
  revision_number INTEGER NOT NULL,
  revision_date TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS activities (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  language_id INTEGER NOT NULL REFERENCES languages(id) ON DELETE CASCADE,
  log_id INTEGER NOT NULL REFERENCES daily_logs(id) ON DELETE CASCADE,
  activity_type TEXT NOT NULL,
  item_index INTEGER DEFAULT 1,
  link TEXT,
  link_duration INTEGER,
  audio_duration INTEGER,
  metadata TEXT
);

CREATE TABLE IF NOT EXISTS words (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  language_id INTEGER NOT NULL REFERENCES languages(id) ON DELETE CASCADE,
  log_id INTEGER NOT NULL REFERENCES daily_logs(id) ON DELETE CASCADE,
  word_index INTEGER NOT NULL,
  native_script TEXT NOT NULL,
  pronunciation TEXT NOT NULL,
  link TEXT,
  audio_duration INTEGER
);

CREATE TABLE IF NOT EXISTS word_srs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  language_id INTEGER NOT NULL REFERENCES languages(id) ON DELETE CASCADE,
  log_id INTEGER NOT NULL REFERENCES daily_logs(id) ON DELETE CASCADE,
  word_id INTEGER NOT NULL REFERENCES words(id) ON DELETE CASCADE,
  card_type TEXT NOT NULL,
  due_date TEXT NOT NULL,
  interval INTEGER NOT NULL,
  ease REAL NOT NULL,
  UNIQUE(word_id, card_type)
);

CREATE INDEX IF NOT EXISTS idx_daily_logs_date ON daily_logs(log_date);
CREATE INDEX IF NOT EXISTS idx_activities_lookup ON activities(language_id, log_id, activity_type);
CREATE INDEX IF NOT EXISTS idx_words_lookup ON words(language_id, log_id);
CREATE INDEX IF NOT EXISTS idx_word_srs_due ON word_srs(due_date, card_type);