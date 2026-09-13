/**
 * Phase 3 experiment: live context call (index + meaning + note in one call)
 * versus index-only call with pre-written notes (senseNotes collection).
 *
 * Runs both paths on the same (word, sentence) pairs with a fresh in-memory
 * cache (so every call is a miss), against the real store and model. Prints
 * latency, tokens, agreement, and cost per 1000 calls from PRICE_* env vars
 * (USD per 1M tokens; defaults are the Section 8 luna list prices).
 *
 *   npm run bench:context
 */
import { loadConfig } from '../src/config.js';
import { connectMongo, disconnectMongo } from '../src/db/connect.js';
import { mongoStore } from '../src/services/mongo-store.js';
import { MemoryCache } from '../src/cache/cache.js';
import { OpenAIProvider } from '../src/llm/openai.js';
import { resolveContext, type ContextOutcome } from '../src/services/context.js';

const S1 = 'It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife.';
const S2 = 'However little known the feelings or views of such a man may be on his first entering a neighbourhood, this truth is so well fixed in the minds of the surrounding families, that he is considered the rightful property of some one or other of their daughters.';
const S3 = '"My dear Mr. Bennet," said his lady to him one day, "have you heard that Netherfield Park is let at last?"';
const S4 = 'Mrs. Long says that Netherfield is taken by a young man of large fortune from the north of England; that he came down on Monday in a chaise and four to see the place, and was so much delighted with it, that he agreed with Mr. Morris immediately; that he is to take possession before Michaelmas, and some of his servants are to be in the house by the end of next week.';
const S5 = 'Time and again she set the table for the whole house, long before the men came in from the fields.';
const S6 = 'The old man wanted nothing but a good long sleep, and would not let anyone take the light away.';

const PAIRS: [string, string][] = [
  ['single', S1], ['fortune', S1], ['want', S1], ['possession', S1], ['good', S1], ['man', S1],
  ['minds', S2], ['property', S2], ['fixed', S2], ['man', S2],
  ['let', S3], ['long', S3],
  ['taken', S4], ['large', S4], ['place', S4], ['delighted', S4], ['possession', S4], ['house', S4], ['long', S4],
  ['time', S5], ['set', S5], ['house', S5], ['long', S5],
  ['man', S6], ['good', S6], ['long', S6], ['let', S6], ['take', S6],
];

const price = (model: string, kind: 'INPUT' | 'OUTPUT', fallback: number) =>
  Number(process.env[`PRICE_${kind}_${model}`] ?? fallback);

async function main() {
  const config = loadConfig();
  await connectMongo(config.MONGODB_URI);
  const llm = new OpenAIProvider(config.OPENAI_API_KEY);
  const log = { warn: (o: object, m: string) => console.warn(m, o) };

  const rows: { word: string; live: ContextOutcome; index: ContextOutcome; liveMs: number; indexMs: number }[] = [];
  for (const [word, sentence] of PAIRS) {
    const deps = { config, llm, cache: new MemoryCache(), store: mongoStore, log };
    let live: ContextOutcome | null, index: ContextOutcome | null;
    const t0 = performance.now();
    let t1 = t0, t2 = t0;
    try {
      live = await resolveContext(deps, word, sentence, 'live');
      t1 = performance.now();
      index = await resolveContext(deps, word, sentence, 'index');
      t2 = performance.now();
    } catch (e) {
      console.log(`  ${word.padEnd(11)} FAILED: ${(e as Error).message} ${JSON.stringify((e as { extra?: unknown }).extra ?? '')}`);
      continue;
    }
    if (!live || !index) {
      console.log(`  ${word.padEnd(11)} not found`);
      continue;
    }
    rows.push({ word, live, index, liveMs: t1 - t0, indexMs: t2 - t1 });
    const agree = live.result.senseIndex === index.result.senseIndex ? '=' : '≠';
    console.log(
      `  ${word.padEnd(11)} live #${live.result.senseIndex} ${Math.round(t1 - t0)}ms | index #${index.result.senseIndex} ${Math.round(t2 - t1)}ms ${agree}  ${live.result.meaning} / ${index.result.meaning}`,
    );
    if (live.result.senseIndex !== index.result.senseIndex) {
      console.log(`      live note:  ${live.result.note}`);
      console.log(`      index note: ${index.result.note || '(no pre-written note)'}`);
    }
  }

  const n = rows.length;
  const sum = (f: (r: (typeof rows)[number]) => number) => rows.reduce((a, r) => a + f(r), 0);
  const agree = rows.filter((r) => r.live.result.senseIndex === r.index.result.senseIndex).length;
  const noNote = rows.filter((r) => r.index.mode === 'index' && !r.index.result.note).length;
  const med = (xs: number[]) => xs.sort((a, b) => a - b)[Math.floor(xs.length / 2)] ?? 0;
  const liveIn = sum((r) => r.live.usage.input), liveOut = sum((r) => r.live.usage.output);
  const idxIn = sum((r) => r.index.usage.input), idxOut = sum((r) => r.index.usage.output);
  const liveModel = config.LLM_CONTEXT_MODEL, idxModel = config.LLM_CONTEXT_INDEX_MODEL;
  const cost = (inTok: number, outTok: number, model: string) =>
    ((inTok * price(model, 'INPUT', 0.2) + outTok * price(model, 'OUTPUT', 1.2)) / 1e6) * (1000 / n);

  console.log(`\n=== ${n} calls per path (all cache misses) ===`);
  console.log(`agreement on senseIndex: ${agree}/${n}; index path lacked a pre-written note: ${noNote}/${n}`);
  console.log(`live  [${liveModel}]: median ${Math.round(med(rows.map((r) => r.liveMs)))}ms, mean ${Math.round(sum((r) => r.liveMs) / n)}ms, tokens/call in ${Math.round(liveIn / n)} out ${Math.round(liveOut / n)}, ≈ $${cost(liveIn, liveOut, liveModel).toFixed(3)} per 1000`);
  console.log(`index [${idxModel}]: median ${Math.round(med(rows.map((r) => r.indexMs)))}ms, mean ${Math.round(sum((r) => r.indexMs) / n)}ms, tokens/call in ${Math.round(idxIn / n)} out ${Math.round(idxOut / n)}, ≈ $${cost(idxIn, idxOut, idxModel).toFixed(3)} per 1000`);
  await disconnectMongo();
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
