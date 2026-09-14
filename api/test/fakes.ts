import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import type { DictionaryEntry, WiktionaryExtract } from '../src/contracts.js';
import type { JsonRequest, JsonResult, LLMProvider, StreamChunk } from '../src/llm/provider.js';
import type { Store } from '../src/services/mongo-store.js';
import type { AppOptions } from '../src/app.js';
import { MemoryCache } from '../src/cache/cache.js';

type SeedFile = {
  entries: (DictionaryEntry & { freqRank: number })[];
  forms: { form: string; lemma: string }[];
  phrases: { phrase: string; lemma: string }[];
};

export const seed = JSON.parse(
  readFileSync(fileURLToPath(new URL('../seed/seed.json', import.meta.url)), 'utf8'),
) as SeedFile;

export function memStore(
  notes: Record<string, string[]> = {},
  staged: Record<string, WiktionaryExtract> = {},
): Store {
  const entries = new Map(seed.entries.map((e) => [e.word, e]));
  const forms = new Map(seed.forms.map((f) => [f.form, f.lemma]));
  const phrases = new Map(seed.phrases.map((p) => [p.phrase, p.lemma]));
  return {
    async findEntry(id) {
      const e = entries.get(id);
      if (!e) return null;
      const { freqRank: _r, ...wire } = e;
      return wire;
    },
    async findFormLemma(f) {
      return forms.get(f) ?? null;
    },
    async findPhraseLemma(p) {
      return phrases.get(p) ?? null;
    },
    async findSenseNotes(w) {
      return notes[w] ?? null;
    },
    async findStaged(lemma) {
      const x = staged[lemma];
      return x ? { extract: x, freqRank: 99_999 } : null;
    },
    async saveGenerated(entry) {
      entries.set(entry.word, { ...entry, freqRank: 99_999 });
      delete staged[entry.word];
    },
  };
}

/** Scripted provider: answers in order per schemaName; records requests. */
export class FakeLLM implements LLMProvider {
  readonly requests: JsonRequest[] = [];
  constructor(private readonly scripted: Record<string, string[]>) {}

  private next(req: JsonRequest): string {
    this.requests.push(req);
    const q = this.scripted[req.schemaName] ?? [];
    const c = q.shift();
    if (c === undefined) throw new Error(`no scripted answer for ${req.schemaName}`);
    return c;
  }

  async completeJson(req: JsonRequest): Promise<JsonResult> {
    return { content: this.next(req), usage: { input: 100, output: 50, cachedInput: 0 }, model: req.model };
  }

  async *streamJson(req: JsonRequest): AsyncIterable<StreamChunk> {
    const content = this.next(req);
    // Stream in small chunks so partial-field extraction actually gets exercised.
    for (let i = 0; i < content.length; i += 7) yield { type: 'delta', text: content.slice(i, i + 7) };
    yield { type: 'done', usage: { input: 100, output: 50, cachedInput: 0 }, model: req.model };
  }
}

export const testConfig: AppOptions['config'] = {
  CONTEXT_MODE: 'live',
  LLM_CONTEXT_MODEL: 'fake-live',
  LLM_CONTEXT_INDEX_MODEL: 'fake-index',
  LLM_ENTRY_MODEL: 'fake-entry',
  LLM_ENTRY_MAX_TOKENS: 4000,
  LLM_TRANSLATE_MODEL: 'fake-translate',
  LLM_TEMPERATURE: undefined,
  LLM_CONTEXT_MAX_TOKENS: 400,
  LLM_TRANSLATE_MAX_TOKENS: 1200,
};

export function appOptions(
  llm: LLMProvider,
  notes?: Record<string, string[]>,
  staged?: Record<string, WiktionaryExtract>,
): AppOptions {
  return { logLevel: 'silent', store: memStore(notes, staged), cache: new MemoryCache(), llm, config: testConfig };
}
