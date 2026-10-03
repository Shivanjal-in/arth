/**
 * Book covers from Open Library (free, no key). The phone sends a title (and
 * an author when the file has one); we find the best-matching edition that has
 * a cover and hand back its image URL. The phone downloads the image itself.
 *
 * Matches are scored on title words so a famous book isn't swapped for a
 * different one: below the bar, the answer is "no cover" and the app keeps
 * its own printed-cloth cover. Hits are cached for good; misses for a day.
 */
import { createHash } from 'node:crypto';
import type { CacheStore } from '../cache/cache.js';

export type CoverFetch = (url: string) => Promise<unknown>;

type OpenLibraryDoc = { title?: string; author_name?: string[]; cover_i?: number; edition_count?: number };

const USER_AGENT = 'Arth/1.0 (book cover lookup; contact: ekansha13@gmail.com)';
const MISS_TTL_MS = 24 * 60 * 60 * 1000;
/** How well the best result's title must match the query (0..1). */
const MIN_SCORE = 0.7;

const words = (s: string): string[] =>
  s
    .toLowerCase()
    .normalize('NFKD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/[^a-z0-9\s]/g, ' ')
    .split(/\s+/)
    .filter(Boolean);

/** Words that say nothing about which book it is. */
const NOISE = new Set(['the', 'a', 'an', 'of', 'and', 'by', 'pdf', 'epub', 'ebook', 'book', 'edition', 'copy', 'free', 'download', 'final', 'v1', 'v2']);

export const significant = (s: string): string[] => words(s).filter((w) => !NOISE.has(w));

/** Share of the query's words found in the candidate title, penalising a much longer title. */
export function titleScore(query: string, candidate: string): number {
  const q = significant(query);
  const c = significant(candidate);
  if (q.length === 0 || c.length === 0) return 0;
  const cs = new Set(c);
  const found = q.filter((w) => cs.has(w)).length;
  const recall = found / q.length;
  const precision = found / c.length;
  return recall * 0.75 + precision * 0.25;
}

export const defaultFetch: CoverFetch = async (url) => {
  const res = await fetch(url, { headers: { 'user-agent': USER_AGENT, accept: 'application/json' }, signal: AbortSignal.timeout(6000) });
  if (!res.ok) throw new Error(`open library ${res.status}`);
  return res.json();
};

export type CoverDeps = { cache: CacheStore; fetchJson?: CoverFetch; now?: () => number };

const misses = new Map<string, number>();

export async function findCover(deps: CoverDeps, title: string, author?: string): Promise<string | null> {
  const key = createHash('sha256').update(`cover:${significant(title).join(' ')}|${significant(author ?? '').join(' ')}`).digest('hex');
  const now = (deps.now ?? Date.now)();

  const cached = await deps.cache.get<{ url: string }>(key);
  if (cached) return cached.url;
  const missedAt = misses.get(key);
  if (missedAt !== undefined && now - missedAt < MISS_TTL_MS) return null;

  const fetchJson = deps.fetchJson ?? defaultFetch;
  const q = new URLSearchParams({ title: significant(title).join(' ') || title, limit: '8', fields: 'title,author_name,cover_i,edition_count' });
  if (author && significant(author).length > 0) q.set('author', significant(author).join(' '));

  let docs: OpenLibraryDoc[];
  try {
    const body = (await fetchJson(`https://openlibrary.org/search.json?${q}`)) as { docs?: OpenLibraryDoc[] };
    docs = body.docs ?? [];
  } catch {
    // Open Library is down or slow: say nothing is known, and don't remember it.
    return null;
  }

  let best: { doc: OpenLibraryDoc; score: number } | null = null;
  for (const doc of docs) {
    if (!doc.cover_i || !doc.title) continue;
    // A well-known edition (many editions) breaks ties between equal titles.
    const score = titleScore(title, doc.title) + Math.min(doc.edition_count ?? 0, 100) / 10_000;
    if (!best || score > best.score) best = { doc, score };
  }

  if (!best || best.score < MIN_SCORE) {
    misses.set(key, now);
    return null;
  }
  const url = `https://covers.openlibrary.org/b/id/${best.doc.cover_i}-M.jpg`;
  await deps.cache.set(key, 'cover', { url });
  return url;
}

/** Test hook. */
export const clearCoverMisses = () => misses.clear();
