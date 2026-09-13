/**
 * /translate: full-sentence translation, streamed by field.
 *
 * The model streams one JSON object; `completedTopLevelFields` lets us emit
 * `hindi`, then `simpleMeaning`, then `difficultWords` the moment each closes.
 * The final object is validated against the contract; on failure we retry once
 * non-streaming (the client already has partial fields, so the retry only has
 * to produce the `done` event). Cache hits replay the same event sequence.
 */
import { createHash } from 'node:crypto';
import type { Config } from '../config.js';
import type { CacheStore } from '../cache/cache.js';
import { formatErrors, promptExamples, promptText, schemaForModel, validate, type TranslationResult } from '../contracts.js';
import { completedTopLevelFields } from '../llm/partial-json.js';
import type { ChatMessage, JsonRequest, LLMProvider, Usage } from '../llm/provider.js';
import { addUsage, zeroUsage } from '../llm/provider.js';
import { normalizeSentence } from '../normalize.js';

const sha = (s: string) => createHash('sha256').update(s, 'utf8').digest('hex');
export const sentenceKey = (text: string) => sha(`sentence:${normalizeSentence(text)}`);

export type TranslateEvent =
  | { event: 'hindi'; data: { hindi: string } }
  | { event: 'simpleMeaning'; data: { simpleMeaning: string } }
  | { event: 'difficultWords'; data: { difficultWords: TranslationResult['difficultWords'] } }
  | { event: 'done'; data: TranslationResult }
  | { event: 'error'; data: { code: string; message: string } };

export type TranslateSummary = { cache: 'hit' | 'miss'; usage: Usage; model?: string | undefined; retried: boolean };

export type TranslateDeps = {
  config: Pick<Config, 'LLM_TRANSLATE_MODEL' | 'LLM_TEMPERATURE' | 'LLM_TRANSLATE_MAX_TOKENS'>;
  llm: LLMProvider;
  cache: CacheStore;
  log: { warn: (obj: object, msg: string) => void };
};

const STREAMED = ['hindi', 'simpleMeaning', 'difficultWords'] as const;

function prefix(): ChatMessage[] {
  const msgs: ChatMessage[] = [{ role: 'system', content: promptText('translate-system') }];
  for (const ex of promptExamples().translate) {
    msgs.push({ role: 'user', content: JSON.stringify(ex.input) });
    msgs.push({ role: 'assistant', content: JSON.stringify(ex.output) });
  }
  return msgs;
}

function replay(result: TranslationResult): TranslateEvent[] {
  return [
    { event: 'hindi', data: { hindi: result.hindi } },
    { event: 'simpleMeaning', data: { simpleMeaning: result.simpleMeaning } },
    { event: 'difficultWords', data: { difficultWords: result.difficultWords } },
    { event: 'done', data: result },
  ];
}

/**
 * Yields events; the returned summary (via `onDone`) carries cache/usage for the log line.
 */
export async function* translate(
  deps: TranslateDeps,
  text: string,
  context: string | undefined,
  onDone: (s: TranslateSummary) => void,
  signal?: AbortSignal,
): AsyncGenerator<TranslateEvent> {
  const source = normalizeSentence(text);
  const key = sentenceKey(source);
  const cached = await deps.cache.get<TranslationResult>(key);
  if (cached) {
    yield* replay(cached);
    onDone({ cache: 'hit', usage: zeroUsage, retried: false });
    return;
  }

  const req: JsonRequest = {
    model: deps.config.LLM_TRANSLATE_MODEL,
    messages: [
      ...prefix(),
      { role: 'user', content: JSON.stringify({ text: source, context: context ? normalizeSentence(context) : null }) },
    ],
    schemaName: 'translation_result',
    schema: schemaForModel('translationResult'),
    maxOutputTokens: deps.config.LLM_TRANSLATE_MAX_TOKENS,
    ...(deps.config.LLM_TEMPERATURE === undefined ? {} : { temperature: deps.config.LLM_TEMPERATURE }),
  };

  let buffer = '';
  const sent = new Set<string>();
  let usage = zeroUsage;
  let model: string | undefined;
  for await (const chunk of deps.llm.streamJson(req, signal)) {
    if (chunk.type === 'done') {
      usage = addUsage(usage, chunk.usage);
      model = chunk.model;
      break;
    }
    buffer += chunk.text;
    const fields = completedTopLevelFields(buffer);
    for (const f of STREAMED) {
      if (sent.has(f) || !fields.has(f)) continue;
      sent.add(f);
      const v = fields.get(f);
      if (f === 'hindi') yield { event: 'hindi', data: { hindi: String(v) } };
      else if (f === 'simpleMeaning') yield { event: 'simpleMeaning', data: { simpleMeaning: String(v) } };
      else yield { event: 'difficultWords', data: { difficultWords: v as TranslationResult['difficultWords'] } };
    }
  }

  let result = parseResult(buffer, source);
  let retried = false;
  if (!result.ok) {
    deps.log.warn({ error: result.error }, 'translate: invalid model output, retrying once');
    retried = true;
    const retry = await deps.llm.completeJson(
      {
        ...req,
        messages: [
          ...req.messages,
          { role: 'assistant', content: buffer },
          { role: 'user', content: `That answer failed validation: ${result.error}. Return the corrected JSON.` },
        ],
      },
      signal,
    );
    usage = addUsage(usage, retry.usage);
    model = retry.model;
    result = parseResult(retry.content, source);
    if (!result.ok) {
      onDone({ cache: 'miss', usage, model, retried });
      throw new Error(`translate: model output invalid twice: ${result.error}`);
    }
    // The client may have partial fields from the bad stream; resend the good ones.
    for (const ev of replay(result.value).slice(0, 3)) yield ev;
  } else {
    for (const f of STREAMED) {
      if (!sent.has(f)) {
        const ev = replay(result.value).find((e) => e.event === f)!;
        yield ev;
      }
    }
  }
  await deps.cache.set(key, 'sentence', result.value);
  yield { event: 'done', data: result.value };
  onDone({ cache: 'miss', usage, model, retried });
}

function parseResult(
  content: string,
  source: string,
): { ok: true; value: TranslationResult } | { ok: false; error: string } {
  let value: unknown;
  try {
    value = JSON.parse(content);
  } catch (e) {
    return { ok: false, error: `not JSON: ${(e as Error).message}` };
  }
  if (!validate.translationResult(value)) return { ok: false, error: formatErrors(validate.translationResult.errors) };
  // `source` is ours, not the model's: pin it to the normalized input.
  return { ok: true, value: { ...value, source } };
}
