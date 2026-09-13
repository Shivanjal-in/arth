/**
 * /context: which sense of a word applies in this sentence.
 *
 * Two paths behind CONTEXT_MODE (Phase 3 experiment):
 *   live   — one call returns the index, the meaning and the Hindi contrast note.
 *   index  — the model only returns the index (a classification a small model
 *            can do); the note comes pre-written per sense from the pipeline.
 * Both are cached forever by content hash. They use distinct key prefixes so
 * both paths can be measured on the same sentences without cross-talk.
 */
import { createHash } from 'node:crypto';
import type { Config } from '../config.js';
import { formatErrors, promptExamples, promptText, schemaForModel, validate, type ContextResult, type DictionaryEntry } from '../contracts.js';
import type { CacheStore } from '../cache/cache.js';
import type { ChatMessage, JsonRequest, JsonResult, LLMProvider, Usage } from '../llm/provider.js';
import { ApiError } from '../lib/errors.js';
import { addUsage, zeroUsage } from '../llm/provider.js';
import { normalizeSentence, normalizeWord } from '../normalize.js';
import { resolveLemma, type LemmaStore } from './lemma.js';

export interface SenseNotesStore {
  findSenseNotes(word: string): Promise<string[] | null>;
}

export type ContextOutcome = {
  result: ContextResult;
  lemma: string;
  cache: 'hit' | 'miss' | 'bypass';
  usage: Usage;
  model?: string;
  mode: 'live' | 'index' | 'single-sense';
  /** True when the model returned an out-of-range index and we fell back to 0. */
  clamped?: boolean;
};

const DEVANAGARI = /[\u0900-\u097F]/;
const sha = (s: string) => createHash('sha256').update(s, 'utf8').digest('hex');

export const contextKey = (word: string, sentence: string) =>
  sha(`context:${normalizeWord(word)}|${normalizeSentence(sentence)}`);
export const contextIndexKey = (word: string, sentence: string) =>
  sha(`context-index:${normalizeWord(word)}|${normalizeSentence(sentence)}`);

function userMessage(entry: DictionaryEntry, sentence: string): string {
  return JSON.stringify({
    word: entry.word,
    sentence,
    senses: entry.senses.map((s) => ({ index: s.index, partOfSpeech: s.partOfSpeech, meaning: s.meaning })),
  });
}

function prefix(mode: 'live' | 'index'): ChatMessage[] {
  const msgs: ChatMessage[] = [{ role: 'system', content: promptText('context-system') }];
  if (mode === 'index') {
    msgs[0]!.content +=
      '\n\nIn this mode return ONLY the senseIndex. Do not write a meaning or a note.';
  }
  for (const ex of promptExamples().context) {
    msgs.push({ role: 'user', content: JSON.stringify(ex.input) });
    msgs.push({
      role: 'assistant',
      content: JSON.stringify(mode === 'index' ? { senseIndex: ex.output.senseIndex } : ex.output),
    });
  }
  return msgs;
}

export type ContextDeps = {
  config: Pick<Config, 'CONTEXT_MODE' | 'LLM_CONTEXT_MODEL' | 'LLM_CONTEXT_INDEX_MODEL' | 'LLM_TEMPERATURE' | 'LLM_CONTEXT_MAX_TOKENS'>;
  llm: LLMProvider;
  cache: CacheStore;
  store: LemmaStore & SenseNotesStore;
  log: { warn: (obj: object, msg: string) => void };
};

export async function resolveContext(
  deps: ContextDeps,
  word: string,
  sentence: string,
  modeOverride?: 'live' | 'index',
): Promise<ContextOutcome | null> {
  const mode = modeOverride ?? deps.config.CONTEXT_MODE;
  const normSentence = normalizeSentence(sentence);
  const wordKey = normalizeWord(word);

  // Cache first, keyed on the tapped word (not the lemma), so a hit costs one
  // read and no entry lookup. The contract's key: sha256('context:' + word + '|' + normalize(sentence)).
  const key = mode === 'index' ? contextIndexKey(wordKey, normSentence) : contextKey(wordKey, normSentence);
  const cached = await deps.cache.get<ContextResult & { lemma?: string }>(key);
  if (cached) {
    const { lemma: cachedLemma, ...result } = cached;
    return { result, lemma: cachedLemma ?? wordKey, cache: 'hit', usage: zeroUsage, mode };
  }

  const resolved = await resolveLemma(deps.store, wordKey);
  if (!resolved) return null;
  const { entry, lemma } = resolved;

  if (entry.senses.length === 1) {
    const s = entry.senses[0]!;
    return {
      result: { senseIndex: 0, meaning: s.meaning, note: '' },
      lemma,
      cache: 'bypass',
      usage: zeroUsage,
      mode: 'single-sense',
    };
  }

  const req: JsonRequest = {
    model: mode === 'index' ? deps.config.LLM_CONTEXT_INDEX_MODEL : deps.config.LLM_CONTEXT_MODEL,
    messages: [...prefix(mode), { role: 'user', content: userMessage(entry, normSentence) }],
    schemaName: mode === 'index' ? 'context_index' : 'context_result',
    schema: schemaForModel(mode === 'index' ? 'contextIndex' : 'contextResult'),
    // max_completion_tokens includes any hidden reasoning tokens, so even an
    // index-only answer needs headroom.
    maxOutputTokens: mode === 'index' ? 256 : deps.config.LLM_CONTEXT_MAX_TOKENS,
    ...(deps.config.LLM_TEMPERATURE === undefined ? {} : { temperature: deps.config.LLM_TEMPERATURE }),
  };

  const { parsed, usage, model } = await completeValidated(deps, req, mode);
  let senseIndex = parsed.senseIndex;
  let clamped = false;
  if (!Number.isInteger(senseIndex) || senseIndex < 0 || senseIndex >= entry.senses.length) {
    deps.log.warn({ lemma, senseIndex, senses: entry.senses.length }, 'context: senseIndex out of range, using 0');
    senseIndex = 0;
    clamped = true;
  }
  let result: ContextResult;
  if (mode === 'index') {
    const notes = await deps.store.findSenseNotes(lemma);
    result = {
      senseIndex,
      meaning: entry.senses[senseIndex]!.meaning,
      note: notes?.[senseIndex] ?? '',
    };
  } else {
    const live = parsed as ContextResult;
    // A proper name ("Mrs. Long") can make the model answer with a dash or
    // English; the sense's own meaning is always a safe headline.
    const meaning = DEVANAGARI.test(live.meaning) ? live.meaning : entry.senses[senseIndex]!.meaning;
    result = { senseIndex, meaning, note: live.note };
  }
  await deps.cache.set(key, mode === 'index' ? 'context-index' : 'context', { ...result, lemma });
  return { result, lemma, cache: 'miss', usage, model, mode, clamped };
}

/** Structured Outputs + our own validation; one retry with the error appended. */
async function completeValidated(
  deps: ContextDeps,
  req: JsonRequest,
  mode: 'live' | 'index',
): Promise<{ parsed: { senseIndex: number } | ContextResult; usage: Usage; model: string }> {
  const check = mode === 'index' ? validate.contextIndex : validate.contextResult;
  let usage = zeroUsage;
  let first: JsonResult;
  try {
    first = await deps.llm.completeJson(req);
  } catch (err) {
    // Hidden reasoning tokens count against max_completion_tokens; a long
    // sentence with many senses can exhaust it before any JSON appears.
    if (!(err instanceof ApiError && err.extra['finish'] === 'length')) throw err;
    deps.log.warn({ maxOutputTokens: req.maxOutputTokens }, 'context: output budget exhausted, retrying with 2×');
    first = await deps.llm.completeJson({ ...req, maxOutputTokens: req.maxOutputTokens * 2 });
  }
  usage = addUsage(usage, first.usage);
  const p1 = tryParse<{ senseIndex: number } | ContextResult>(first.content, check);
  if (p1.ok) return { parsed: p1.value, usage, model: first.model };
  deps.log.warn({ error: p1.error }, 'context: invalid model output, retrying once');
  const retry: JsonRequest = {
    ...req,
    messages: [
      ...req.messages,
      { role: 'assistant', content: first.content },
      { role: 'user', content: `That answer failed validation: ${p1.error}. Return the corrected JSON.` },
    ],
  };
  const second = await deps.llm.completeJson(retry);
  usage = addUsage(usage, second.usage);
  const p2 = tryParse<{ senseIndex: number } | ContextResult>(second.content, check);
  if (p2.ok) return { parsed: p2.value, usage, model: second.model };
  throw new Error(`context: model output invalid twice: ${p2.error}`);
}

function tryParse<T>(
  content: string,
  check: (x: unknown) => boolean,
): { ok: true; value: T } | { ok: false; error: string } {
  let value: unknown;
  try {
    value = JSON.parse(content);
  } catch (e) {
    return { ok: false, error: `not JSON: ${(e as Error).message}` };
  }
  if (!check(value)) {
    return { ok: false, error: formatErrors((check as { errors?: import('ajv').ErrorObject[] }).errors) };
  }
  return { ok: true, value: value as T };
}
