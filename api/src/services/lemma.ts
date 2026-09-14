import type { DictionaryEntry } from '../contracts.js';

/** The two reads lemma resolution needs. Mongo in production, a Map in tests. */
export interface LemmaStore {
  findEntry(id: string): Promise<DictionaryEntry | null>;
  /** Returns the lemma for an inflected form, or null. */
  findFormLemma(form: string): Promise<string | null>;
}

export type ResolvedVia = 'exact' | 'form' | 'lowercase' | 'lowercase-form' | 'possessive' | 'possessive-form';

export type LemmaResolution = { entry: DictionaryEntry; lemma: string; via: ResolvedVia } | null;

async function tryKey(store: LemmaStore, key: string): Promise<{ entry: DictionaryEntry; lemma: string; viaForm: boolean } | null> {
  const direct = await store.findEntry(key);
  if (direct) return { entry: direct, lemma: key, viaForm: false };
  const lemma = await store.findFormLemma(key);
  if (lemma) {
    const entry = await store.findEntry(lemma);
    if (entry) return { entry, lemma, viaForm: true };
  }
  return null;
}

/**
 * Resolution order from the API contract: exact → forms → lowercase → strip trailing 's.
 * Each later step re-runs the exact+forms pair on the transformed key.
 */
/** Same exact → forms → lowercase → 's order, but only asks "is this a lemma?" — used for staged words. */
export async function resolveLemmaKey(
  isLemma: (key: string) => Promise<boolean>,
  formLemma: (form: string) => Promise<string | null>,
  word: string,
): Promise<string | null> {
  const w = word.trim();
  if (!w) return null;
  const candidates = [w];
  const lower = w.toLowerCase();
  if (lower !== w) candidates.push(lower);
  if (lower.endsWith("'s") && lower.length > 2) candidates.push(lower.slice(0, -2));
  for (const c of candidates) {
    if (await isLemma(c)) return c;
    const l = await formLemma(c);
    if (l && (await isLemma(l))) return l;
  }
  return null;
}

export async function resolveLemma(store: LemmaStore, word: string): Promise<LemmaResolution> {
  const w = word.trim();
  if (!w) return null;

  const exact = await tryKey(store, w);
  if (exact) return { ...exact, via: exact.viaForm ? 'form' : 'exact' };

  const lower = w.toLowerCase();
  if (lower !== w) {
    const hit = await tryKey(store, lower);
    if (hit) return { ...hit, via: hit.viaForm ? 'lowercase-form' : 'lowercase' };
  }

  if (lower.endsWith("'s") && lower.length > 2) {
    const base = lower.slice(0, -2);
    const hit = await tryKey(store, base);
    if (hit) return { ...hit, via: hit.viaForm ? 'possessive-form' : 'possessive' };
  }

  return null;
}
