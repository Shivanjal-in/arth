/** Windows of 2–4 tokens covering the tapped index, longest first then leftmost. Mirrors the app. */

export type PhraseWindow = { start: number; tokenCount: number; phrase: string };

export function phraseWindows(tokens: string[], index: number, minLen = 2, maxLen = 4): PhraseWindow[] {
  const out: PhraseWindow[] = [];
  for (let len = maxLen; len >= minLen; len--) {
    for (let start = index - len + 1; start <= index; start++) {
      if (start < 0 || start + len > tokens.length) continue;
      const slice = tokens.slice(start, start + len);
      if (slice.some((t) => t.length === 0)) continue;
      out.push({ start, tokenCount: len, phrase: slice.join(' ') });
    }
  }
  return out;
}

export interface PhraseStore {
  findPhraseLemma(phrase: string): Promise<string | null>;
}

export async function matchPhrase(
  store: PhraseStore,
  tokens: string[],
  index: number,
): Promise<{ phrase: string; lemma: string; start: number; tokenCount: number } | null> {
  for (const w of phraseWindows(tokens, index)) {
    const lemma = await store.findPhraseLemma(w.phrase);
    if (lemma) return { phrase: w.phrase, lemma, start: w.start, tokenCount: w.tokenCount };
  }
  return null;
}
