/**
 * On-demand generation: the Hindi layer for a lemma that is staged (Wiktionary
 * senses present, no entry yet), built the first time a reader taps it.
 *
 * Same prompt, gold examples, schema and cross-checks as pipeline/04_generate.py,
 * so an on-demand entry is indistinguishable from a batch one. The result is
 * upserted into `entries` for ever; a concurrent tap on the same lemma shares
 * the in-flight promise instead of paying twice.
 */
import type { Config } from '../config.js';
import {
  formatErrors,
  promptExamples,
  promptText,
  schemaForModel,
  validate,
  type DictionaryEntry,
  type EntryGeneration,
  type WiktionaryExtract,
} from '../contracts.js';
import type { ChatMessage, JsonRequest, LLMProvider, Usage } from '../llm/provider.js';
import { addUsage, zeroUsage } from '../llm/provider.js';

export interface StagingStore {
  findStaged(lemma: string): Promise<{ extract: WiktionaryExtract; freqRank: number } | null>;
  saveGenerated(entry: DictionaryEntry, meta: { freqRank: number; model: string }): Promise<void>;
}

export type OnDemandDeps = {
  config: Pick<Config, 'LLM_ENTRY_MODEL' | 'LLM_TEMPERATURE' | 'LLM_ENTRY_MAX_TOKENS'>;
  llm: LLMProvider;
  staging: StagingStore;
  log: { warn: (obj: object, msg: string) => void; info: (obj: object, msg: string) => void };
  /** Called just before a model call; throw to refuse (rate limit). */
  spend?: () => void;
};

export type OnDemandOutcome = { entry: DictionaryEntry; usage: Usage; model: string; attempts: number };

const DEVANAGARI = /[\u0900-\u097F]/; // Devanagari block
const ENGLISH_WORD = /[A-Za-z]{3,}/;

function userMessage(x: WiktionaryExtract): string {
  return JSON.stringify({
    word: x.word,
    ipa: x.ipa,
    isPhrase: x.isPhrase,
    senses: x.senses.map((s) => ({ index: s.index, partOfSpeech: s.partOfSpeech, gloss: s.gloss, examples: s.examples })),
    synonyms: x.synonyms,
    antonyms: x.antonyms,
    forms: x.forms.map((f) => ({ en: f.en, label: f.label })),
  });
}

function prefix(): ChatMessage[] {
  const msgs: ChatMessage[] = [{ role: 'system', content: promptText('entry-system') }];
  for (const ex of promptExamples().entry) {
    msgs.push({ role: 'user', content: JSON.stringify(ex.input) });
    msgs.push({ role: 'assistant', content: JSON.stringify(ex.output) });
  }
  return msgs;
}

function checkHindi(path: string, value: string, errors: string[], allowLatin = false): void {
  if (!value.trim()) errors.push(`${path}: empty`);
  else if (!DEVANAGARI.test(value)) errors.push(`${path}: no Devanagari`);
  else if (!allowLatin && ENGLISH_WORD.test(value)) errors.push(`${path}: English word in Hindi field`);
}

/** Port of pipeline/arth_pipeline/generate.py::parse_generation. */
export function parseGeneration(x: WiktionaryExtract, content: string): { ok: true; entry: DictionaryEntry } | { ok: false; error: string } {
  let raw: unknown;
  try {
    raw = JSON.parse(content);
  } catch (e) {
    return { ok: false, error: `not JSON: ${(e as Error).message}` };
  }
  if (!validate.entryGeneration(raw)) return { ok: false, error: `schema: ${formatErrors(validate.entryGeneration.errors)}` };
  const gen = raw as EntryGeneration;
  const errors: string[] = [];
  if (gen.senses.length !== x.senses.length) errors.push(`senses: expected ${x.senses.length}, got ${gen.senses.length}`);
  gen.senses.forEach((s, i) => {
    const exp = x.senses[i];
    if (!exp) return;
    if (s.index !== exp.index) errors.push(`senses[${i}].index: expected ${exp.index}, got ${s.index}`);
    s.partOfSpeech = exp.partOfSpeech; // our mapping, not the model's
    checkHindi(`senses[${i}].meaning`, s.meaning, errors);
    checkHindi(`senses[${i}].definition`, s.definition, errors);
    s.examples.forEach((ex, j) => {
      checkHindi(`senses[${i}].examples[${j}].hi`, ex.hi, errors, true);
      if (!ex.en.trim()) errors.push(`senses[${i}].examples[${j}].en: empty`);
    });
  });
  for (const key of ['synonyms', 'antonyms'] as const) {
    const got = gen[key].map((p) => p.en);
    if (JSON.stringify(got) !== JSON.stringify(x[key])) errors.push(`${key}: en list must be exactly ${JSON.stringify(x[key])}`);
    gen[key].forEach((p, j) => checkHindi(`${key}[${j}].hi`, p.hi, errors, true));
  }
  const gotForms = gen.forms.map((f) => [f.en, f.label]);
  const expForms = x.forms.map((f) => [f.en, f.label]);
  if (JSON.stringify(gotForms) !== JSON.stringify(expForms)) errors.push('forms: (en, label) pairs must match the input');
  gen.forms.forEach((f, j) => checkHindi(`forms[${j}].hi`, f.hi, errors, true));
  checkHindi('hindiPronunciation', gen.hindiPronunciation, errors);
  if (errors.length) return { ok: false, error: errors.slice(0, 8).join('; ') };

  const entry: DictionaryEntry = {
    word: x.word,
    ipa: x.ipa,
    hindiPronunciation: gen.hindiPronunciation,
    senses: gen.senses,
    synonyms: gen.synonyms,
    antonyms: gen.antonyms,
    forms: gen.forms,
    isPhrase: x.isPhrase,
  };
  if (!validate.dictionaryEntry(entry)) return { ok: false, error: `entry: ${formatErrors(validate.dictionaryEntry.errors)}` };
  return { ok: true, entry };
}

const inFlight = new Map<string, Promise<OnDemandOutcome | null>>();

/** Generate, validate (one retry), store. Null when the lemma isn't staged. */
export function generateOnDemand(deps: OnDemandDeps, lemma: string): Promise<OnDemandOutcome | null> {
  const existing = inFlight.get(lemma);
  if (existing) return existing;
  const p = run(deps, lemma).finally(() => inFlight.delete(lemma));
  inFlight.set(lemma, p);
  return p;
}

async function run(deps: OnDemandDeps, lemma: string): Promise<OnDemandOutcome | null> {
  const staged = await deps.staging.findStaged(lemma);
  if (!staged) return null;
  const x = staged.extract;
  deps.spend?.();
  const model = deps.config.LLM_ENTRY_MODEL;
  const base: JsonRequest = {
    model,
    messages: [...prefix(), { role: 'user', content: userMessage(x) }],
    schemaName: 'entry_generation',
    schema: schemaForModel('entryGeneration'),
    maxOutputTokens: deps.config.LLM_ENTRY_MAX_TOKENS,
    ...(deps.config.LLM_TEMPERATURE === undefined ? {} : { temperature: deps.config.LLM_TEMPERATURE }),
  };
  const started = Date.now();
  let usage = zeroUsage;
  const first = await deps.llm.completeJson(base);
  usage = addUsage(usage, first.usage);
  let parsed = parseGeneration(x, first.content);
  let attempts = 1;
  if (!parsed.ok) {
    deps.log.warn({ lemma, error: parsed.error }, 'ondemand: invalid output, retrying once');
    attempts = 2;
    const second = await deps.llm.completeJson({
      ...base,
      messages: [
        ...base.messages,
        { role: 'assistant', content: first.content },
        {
          role: 'user',
          content: `That answer failed validation: ${parsed.error}. Return the corrected JSON for the same word. Keep every sense, in order, with the same index and partOfSpeech; keep every en value exactly as given.`,
        },
      ],
    });
    usage = addUsage(usage, second.usage);
    parsed = parseGeneration(x, second.content);
    if (!parsed.ok) throw new Error(`ondemand: invalid twice for ${lemma}: ${parsed.error}`);
  }
  await deps.staging.saveGenerated(parsed.entry, { freqRank: staged.freqRank, model: first.model });
  deps.log.info({ lemma, ms: Date.now() - started, usage, attempts }, 'ondemand: generated');
  return { entry: parsed.entry, usage, model: first.model, attempts };
}

/**
 * Morphology fallback for the "Did you mean" list: strip common affixes and
 * keep the bases that resolve. brimless → brim, bespattered → bespatter (via
 * forms), tremulously → tremulous.
 */
const SUFFIXES = ['ly', 'ness', 'less', 'ful', 'ish', 'ment', 'able', 'ible', 'ously', 'ing', 'ed', 'es', 's', 'er', 'est', 'ish'];
const PREFIXES = ['be', 'un', 're', 'dis', 'mis', 'over', 'under'];

function stems(word: string): string[] {
  const out: string[] = [];
  for (const sfx of SUFFIXES) {
    if (word.endsWith(sfx) && word.length - sfx.length >= 3) {
      const stem = word.slice(0, -sfx.length);
      out.push(stem, `${stem}e`); // tremul-ous-ly → tremulous; bak-ing → bake
      if (stem.length > 3 && stem[stem.length - 1] === stem[stem.length - 2]) out.push(stem.slice(0, -1)); // stopp-ed → stop
      if (stem.endsWith('i')) out.push(`${stem.slice(0, -1)}y`); // happi-ly → happy
    }
  }
  for (const pfx of PREFIXES) {
    if (word.startsWith(pfx) && word.length - pfx.length >= 3) out.push(word.slice(pfx.length));
  }
  return out;
}

export async function morphologySuggestions(
  word: string,
  exists: (candidate: string) => Promise<boolean>,
  limit = 3,
): Promise<string[]> {
  const out: string[] = [];
  const seen = new Set<string>([word]);
  // Two affixes deep at most: un-kind-ness → kind.
  const first = stems(word);
  const queue = [...first, ...first.flatMap(stems)];
  for (const c of queue) {
    if (out.length >= limit) break;
    if (c.length < 3 || seen.has(c)) continue;
    seen.add(c);
    if (await exists(c)) out.push(c);
  }
  return out;
}
