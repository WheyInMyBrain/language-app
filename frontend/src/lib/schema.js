// frontend/src/lib/schema.js

export const DB_CONFIG = {
  name: 'LanguageAppLocal',
  version: 1,
  stores: {
    languages: {
      keyPath: 'code',
      indexes: []
    },
    daily_logs: {
      keyPath: 'id', // Format: `${lang_code}:${log_date}`
      indexes: [
        { name: 'by_lang', keyPath: 'lang_code' },
        { name: 'by_date', keyPath: 'log_date' }
      ]
    },
    words: {
      keyPath: 'id', // UUIDv7
      indexes: [
        { name: 'by_lang_date', keyPath: ['lang_code', 'log_date'] }
      ]
    },
    activities: {
      keyPath: 'id', // UUIDv7
      indexes: [
        { name: 'by_lang_date', keyPath: ['lang_code', 'log_date'] },
        { name: 'by_type', keyPath: ['lang_code', 'activity_type'] }
      ]
    },
    word_srs: {
      keyPath: 'card_key', // Format: `${lang_code}:${word_id}:${card_type}`
      indexes: [
        { name: 'by_lang', keyPath: 'lang_code' },
        { name: 'by_due', keyPath: ['lang_code', 'due_date'] },
        { name: 'by_type_due', keyPath: ['lang_code', 'card_type', 'due_date'] }
      ]
    },
    outbox: {
      keyPath: 'mutation_id',
      indexes: [
        { name: 'by_timestamp', keyPath: 'created_at' }
      ]
    },
    sync_meta: {
      keyPath: 'key',
      indexes: []
    }
  }
};