/**
 * Text normalization — implements contracts/normalize.md.
 *
 * Any change here must keep contracts/normalize-vectors.json passing, and the
 * Dart and Python implementations must change in lockstep. Cache keys are
 * derived from this output.
 */
import { createHash } from 'node:crypto';

// S1
const INVISIBLE = /[\u00AD\u200B\uFEFF]/g;

// S2
const LIGATURES: Record<string, string> = {
  '\uFB00': 'ff',
  '\uFB01': 'fi',
  '\uFB02': 'fl',
  '\uFB03': 'ffi',
  '\uFB04': 'ffl',
  '\uFB05': 'st',
  '\uFB06': 'st',
};
const LIGATURE_RE = /[\uFB00-\uFB06]/g;

// S3
const SINGLE_QUOTES = /[\u2018\u2019\u201A\u201B\u02BC\u2032]/g;
const DOUBLE_QUOTES = /[\u201C\u201D\u201E\u201F\u2033]/g;

// S4
const HYPHENS = /[\u2010\u2011\u2212\uFE63\uFF0D]/g;
const DASHES = /[\u2013\u2014\u2015\u2E3A\u2E3B]/g;

// S5 — letter, hyphen, optional spaces/tabs, one line/page break, optional spaces/tabs, letter
const HYPHEN_BREAK = /(\p{L})-[ \t]*(?:\r\n|\n|\r|\f)[ \t]*(\p{L})/gu;

// S6 — the exact whitespace set from the spec, not \s (which differs across engines)
const WHITESPACE_RUN =
  /[\u0009-\u000D\u0020\u0085\u00A0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u3000]+/g;

// W1
const LEADING_NON_ALNUM = /^[^\p{L}\p{N}]+/u;
const TRAILING_NON_ALNUM = /[^\p{L}\p{N}]+$/u;

export function normalizeSentence(text: string): string {
  let s = text.replace(INVISIBLE, '');
  s = s.replace(LIGATURE_RE, (ch) => LIGATURES[ch] ?? ch);
  s = s.replace(SINGLE_QUOTES, "'").replace(DOUBLE_QUOTES, '"');
  s = s.replace(HYPHENS, '-').replace(DASHES, '\u2014');
  // S5 can chain ("un-", break, "be-", break, "lievable"): each match consumes
  // its trailing letter, so the next break may be missed in one pass. Loop
  // until stable.
  let prev: string;
  do {
    prev = s;
    s = s.replace(HYPHEN_BREAK, '$1$2');
  } while (s !== prev);
  s = s.replace(WHITESPACE_RUN, ' ');
  return s.trim();
}

export function normalizeWord(token: string): string {
  const s = normalizeSentence(token)
    .replace(LEADING_NON_ALNUM, '')
    .replace(TRAILING_NON_ALNUM, '');
  return s.toLowerCase();
}

function sha256Hex(s: string): string {
  return createHash('sha256').update(s, 'utf8').digest('hex');
}

export function contextKey(word: string, sentence: string): string {
  return sha256Hex(`context:${normalizeWord(word)}|${normalizeSentence(sentence)}`);
}

export function sentenceKey(text: string): string {
  return sha256Hex(`sentence:${normalizeSentence(text)}`);
}
