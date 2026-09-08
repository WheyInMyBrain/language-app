import zhCN from './zh-CN.js';

const registry = {
  'zh-CN': zhCN
};

const DEFAULT_CONFIG = {
  goals: { vocab: 10, grammar: 1, ci: 1, listening_minutes: 30 },
  milestones: { vocab_total: 100, listening_hours: 24, speaking_hours: 6 },
  colors: {},
  tones: null
};

export function getLanguageConfig(code) {
  return registry[code] || { ...DEFAULT_CONFIG, code, name: code };
}