# Text normalization spec

Three implementations exist — `api/src/normalize.ts`, `pipeline/arth_pipeline/normalize.py`,
`app/lib/core/normalize.dart` — and all three must pass `normalize-vectors.json`.
Cache keys are derived from normalized text, so any drift between them silently
breaks cache hits. Change this file and the vectors together, then fix all three.

Two entry points:

- `normalizeSentence(text)` — for sentence/selection text. Case is preserved.
- `normalizeWord(token)` — for a single tapped token. Applies the sentence rules,
  then strips edge punctuation and lowercases.

Plus one derived helper, `cacheKey(kind, ...)`, defined at the end.

Inputs are English text extracted from a PDF text layer. The rules are written to be
implementable with plain string ops and regexes in Dart, TypeScript and Python 3
without any Unicode-normalization library. Rules apply **in this order**.

## S1. Remove invisible characters

Delete every occurrence of:

| Code point | Name |
|---|---|
| U+00AD | soft hyphen |
| U+200B | zero-width space |
| U+FEFF | byte-order mark / zero-width no-break space |

U+200C / U+200D (ZWNJ / ZWJ) are **kept** — they are meaningful in Devanagari, and the
same function is used on Hindi strings in tests.

## S2. Expand typographic ligatures

| From | To |
|---|---|
| U+FB00 ﬀ | `ff` |
| U+FB01 ﬁ | `fi` |
| U+FB02 ﬂ | `fl` |
| U+FB03 ﬃ | `ffi` |
| U+FB04 ﬄ | `ffl` |
| U+FB05 ﬅ | `st` |
| U+FB06 ﬆ | `st` |

## S3. Straighten quotes

| From | To |
|---|---|
| U+2018 ‘ U+2019 ’ U+201A ‚ U+201B ‛ U+02BC ʼ U+2032 ′ | `'` (U+0027) |
| U+201C “ U+201D ” U+201E „ U+201F ‟ U+2033 ″ | `"` (U+0022) |

Guillemets (« ») are left alone.

## S4. Normalize dashes

Two classes, deliberately kept distinct. A hyphen joins parts of a word; a dash
separates clauses. Collapsing both to `-` would create false compounds
(`left—quickly` → `left-quickly`) and break word lookups.

| From | To |
|---|---|
| U+2010 ‐ hyphen, U+2011 ‑ non-breaking hyphen, U+2212 − minus, U+FE63 ﹣, U+FF0D － | `-` (U+002D) |
| U+2013 – en dash, U+2014 — em dash, U+2015 ― horizontal bar, U+2E3A ⸺, U+2E3B ⸻ | `—` (U+2014) |

Spacing around dashes is not changed by this rule (S6 collapses runs).

## S5. Join words hyphenated across a line or page break

After S4, a `-` at the end of a line that sits between two letters is a
typesetting break, not a real hyphen. Remove the hyphen and the break:

    pattern:  (letter) "-" [ \t]* (\r\n | \n | \r | \f) [ \t]* (letter)
    replace:  $1$2

where *letter* is any Unicode letter (category L*). Form feed U+000C is treated as
a line break because PDF extractors emit it at page boundaries, which is what
"stitch across page boundaries" means for this function.

Known limitation: a genuinely hyphenated compound broken at a line end
(`well-\nknown`) also joins to `wellknown`. Accepting this; the alternative needs
a dictionary in the hot path.

The rule fires only when both sides are letters. `2-\n3`, `-\n`, and `— \n` are
untouched (and then collapse under S6).

## S6. Collapse whitespace and trim

Every run of one or more Unicode whitespace characters becomes a single ASCII
space U+0020, then leading and trailing spaces are removed. "Whitespace" is:

U+0009–U+000D (tab, LF, VT, FF, CR), U+0020, U+0085, U+00A0, U+1680,
U+2000–U+200A, U+2028, U+2029, U+202F, U+205F, U+3000.

This is also what stitches a sentence that continues on the next page: after S5,
the form feed is just whitespace. Running headers, footers and page numbers are
**not** handled here — the app's extractor drops those before calling normalize.

Result of S1–S6 is the output of `normalizeSentence`.

## W1. Word keys: strip edge punctuation

Applied after S1–S6 to a single token. Remove characters from both ends until the
first and last character are each a Unicode letter (L*) or digit (N*). Internal
apostrophes and hyphens stay: `don't`, `well-known`, `fortune's`.

If nothing remains, the result is the empty string (the caller treats that as
"nothing to look up").

## W2. Word keys: lowercase

Full Unicode lowercase as provided by the language runtime (`toLowerCase()`,
`.lower()`). Runtimes disagree only on scripts we never see here (Turkish İ,
Greek final sigma); vectors stay within ASCII + Latin-1.

Trailing `'s` is **not** stripped — that is a lemma-resolution step on the server
and in the on-device lookup, not a normalization step, so the key still carries
the information.

Result of S1–S6 + W1–W2 is the output of `normalizeWord`.

## Cache keys

    contextKey(word, sentence)  = sha256_hex( "context:" + normalizeWord(word) + "|" + normalizeSentence(sentence) )
    sentenceKey(text)           = sha256_hex( "sentence:" + normalizeSentence(text) )

The string is encoded as UTF-8 before hashing. The hex digest is lowercase.
`normalize-vectors.json` includes `key` vectors so all three languages prove they
hash identically.

## Vector file format

```json
{
  "version": 1,
  "vectors": [
    { "id": "lig-fi",      "kind": "sentence", "input": "ﬁne", "expected": "fine" },
    { "id": "word-quote",  "kind": "word",     "input": "\"Fortune,\"", "expected": "fortune" },
    { "id": "key-ctx-1",   "kind": "key", "keyKind": "context", "word": "single", "sentence": "...", "expected": "<sha256 hex>" },
    { "id": "key-sent-1",  "kind": "key", "keyKind": "sentence", "text": "...", "expected": "<sha256 hex>" }
  ]
}
```

Every implementation's test suite loads this file and asserts every vector.
Adding a vector needs no code change in the tests.
