"""Text normalization — implements contracts/normalize.md.

Any change here must keep contracts/normalize-vectors.json passing, and the
TypeScript and Dart implementations must change in lockstep. Cache keys are
derived from this output.

Character sets are built from code points rather than written as escapes so
the file reads the same as the spec tables.
"""

from __future__ import annotations

import hashlib
import re

# S1
_INVISIBLE = [0x00AD, 0x200B, 0xFEFF]
# S2
_LIGATURES = {
    0xFB00: "ff",
    0xFB01: "fi",
    0xFB02: "fl",
    0xFB03: "ffi",
    0xFB04: "ffl",
    0xFB05: "st",
    0xFB06: "st",
}
# S3
_SINGLE_QUOTES = [0x2018, 0x2019, 0x201A, 0x201B, 0x02BC, 0x2032]
_DOUBLE_QUOTES = [0x201C, 0x201D, 0x201E, 0x201F, 0x2033]
# S4
_HYPHENS = [0x2010, 0x2011, 0x2212, 0xFE63, 0xFF0D]
_DASHES = [0x2013, 0x2014, 0x2015, 0x2E3A, 0x2E3B]
_EM_DASH = chr(0x2014)

# S1–S4 are disjoint single-character substitutions, so one translate() pass is exact.
_TABLE = str.maketrans(
    {cp: None for cp in _INVISIBLE}
    | dict(_LIGATURES)
    | {cp: "'" for cp in _SINGLE_QUOTES}
    | {cp: '"' for cp in _DOUBLE_QUOTES}
    | {cp: "-" for cp in _HYPHENS}
    | {cp: _EM_DASH for cp in _DASHES}
)

# S5 — candidate break; the letter check happens in the callback because `re`
# has no \p{L}. DOTALL so "." can match the break characters on either side.
_BREAK = "(?:" + chr(13) + chr(10) + "|" + chr(10) + "|" + chr(13) + "|" + chr(12) + ")"
_HSPACE = "[ " + chr(9) + "]*"
_HYPHEN_BREAK = re.compile("(.)-" + _HSPACE + _BREAK + _HSPACE + "(.)", re.DOTALL)

# S6 — the exact whitespace set from the spec, not \s (which differs across engines).
_WS = (
    list(range(0x09, 0x0E))
    + [0x20, 0x85, 0xA0, 0x1680]
    + list(range(0x2000, 0x200B))
    + [0x2028, 0x2029, 0x202F, 0x205F, 0x3000]
)
_WHITESPACE_RUN = re.compile("[" + "".join(re.escape(chr(cp)) for cp in _WS) + "]+")


def _join_if_letters(m: re.Match[str]) -> str:
    a, b = m.group(1), m.group(2)
    return a + b if a.isalpha() and b.isalpha() else m.group(0)


def normalize_sentence(text: str) -> str:
    s = text.translate(_TABLE)
    # S5 can chain (un-/be-/lievable across two breaks): each match consumes its
    # trailing letter, so loop until stable.
    while True:
        joined = _HYPHEN_BREAK.sub(_join_if_letters, s)
        if joined == s:
            break
        s = joined
    s = _WHITESPACE_RUN.sub(" ", s)
    return s.strip(" ")


def _is_word_char(ch: str) -> bool:
    # \p{L} or \p{N}
    return ch.isalpha() or ch.isnumeric()


def normalize_word(token: str) -> str:
    s = normalize_sentence(token)
    start, end = 0, len(s)
    while start < end and not _is_word_char(s[start]):
        start += 1
    while end > start and not _is_word_char(s[end - 1]):
        end -= 1
    return s[start:end].lower()


def _sha256_hex(s: str) -> str:
    return hashlib.sha256(s.encode("utf-8")).hexdigest()


def context_key(word: str, sentence: str) -> str:
    return _sha256_hex(f"context:{normalize_word(word)}|{normalize_sentence(sentence)}")


def sentence_key(text: str) -> str:
    return _sha256_hex(f"sentence:{normalize_sentence(text)}")
