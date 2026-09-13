"""Reading the kaikki.org English Wiktionary JSONL.

One line per (word, POS, etymology). A single word like "set" spans several lines.
Scans are streaming; a full pass over the 3 GB file takes a few seconds when the
file is in page cache and a minute or two cold.
"""

from __future__ import annotations

import json
import re
from collections.abc import Callable, Iterator
from pathlib import Path
from typing import Any

from .config import DATA_DIR

WIKTIONARY_PATH = DATA_DIR / "wiktionary-en.jsonl"

# POS values we turn into dictionary entries. Everything else (name, prefix,
# suffix, symbol, character, proverb, ...) is skipped.
CONTENT_POS: frozenset[str] = frozenset(
    {
        "noun",
        "verb",
        "adj",
        "adv",
        "pron",
        "prep",
        "conj",
        "intj",
        "det",
        "num",
        "particle",
        "article",
        "contraction",
        "phrase",
        "prep_phrase",
    }
)

POS_HINDI: dict[str, str] = {
    "noun": "संज्ञा",
    "verb": "क्रिया",
    "adj": "विशेषण",
    "adv": "क्रियाविशेषण",
    "pron": "सर्वनाम",
    "prep": "पूर्वसर्ग",
    "conj": "समुच्चयबोधक",
    "intj": "विस्मयादिबोधक",
    "det": "निर्धारक",
    "num": "संख्या",
    "particle": "अव्यय",
    "article": "आर्टिकल",
    "contraction": "संक्षिप्त रूप",
    "phrase": "मुहावरा",
    "prep_phrase": "मुहावरा",
}

# Sense tags that mean "this is a pointer to another entry, not a meaning".
POINTER_TAGS: frozenset[str] = frozenset({"form-of", "alt-of"})
# Senses we drop outright. Archaic/dated stay — 19th-century novels need them.
DROP_SENSE_TAGS: frozenset[str] = frozenset(
    {"obsolete", "misspelling", "vulgar", "offensive", "derogatory", "rare", "nonstandard", "humorous"}
)
# Stricter set for deciding whether a multi-word entry deserves to be a phrase at all,
# and whether an inflection entry is trustworthy enough to feed lemma resolution.
RESTRICTED_TAGS: frozenset[str] = DROP_SENSE_TAGS | frozenset(
    {"slang", "dialectal", "informal", "pronunciation-spelling", "eye-dialect", "abbreviation", "ellipsis"}
)
DROP_GLOSS_PREFIXES: tuple[str, ...] = (
    "Alternative form of",
    "Alternative spelling of",
    "Misspelling of",
    "Obsolete form of",
    "Obsolete spelling of",
    "Archaic form of",
    "Archaic spelling of",
    "Eye dialect spelling of",
    "Pronunciation spelling of",
    "Abbreviation of",
    "Initialism of",
    "Acronym of",
    "Clipping of",
    "Ellipsis of",
)

# Form tags → Hindi label. A form is kept only if every tag is known here or
# harmless (see FORM_IGNORED_TAGS), so table rows and templates never leak.
FORM_LABELS: list[tuple[frozenset[str], str]] = [
    (frozenset({"plural"}), "बहुवचन"),
    (frozenset({"past"}), "भूतकाल"),
    (frozenset({"participle", "past"}), "भूतकालिक कृदंत"),
    (frozenset({"participle", "present"}), "क्रिया-रूप"),
    (frozenset({"present", "singular", "third-person"}), "वर्तमान (वह)"),
    (frozenset({"comparative"}), "तुलनात्मक"),
    (frozenset({"superlative"}), "उत्तमता"),
    (frozenset({"US"}), "अमेरिकी वर्तनी"),
    (frozenset({"alternative", "US"}), "अमेरिकी वर्तनी"),
    (frozenset({"UK"}), "ब्रिटिश वर्तनी"),
    (frozenset({"alternative", "UK"}), "ब्रिटिश वर्तनी"),
]
FORM_IGNORED_TAGS: frozenset[str] = frozenset({"standard", "uncommon"})

# The top-level "word" key is immediately followed by "lang": "English"; nested
# objects (descendants, translations) also carry "word" keys, so anchor on that.
_WORD_RE = re.compile(rb'"word": "((?:[^"\\]|\\.)*)", "lang": "English"')
_POS_RE = re.compile(rb'"pos": "([^"]*)"')


def peek_word_pos(line: bytes) -> tuple[str, str] | None:
    """Cheap extraction of word and pos from a raw line without a full JSON parse."""
    mp = _POS_RE.search(line, 0, 64)
    if not mp:
        return None
    mw = _WORD_RE.search(line)
    if mw:
        word = json.loads(b'"' + mw.group(1) + b'"')
    else:
        word = json.loads(line).get("word", "")
    return word, mp.group(1).decode()


def iter_lines(path: Path = WIKTIONARY_PATH) -> Iterator[bytes]:
    with path.open("rb") as f:
        yield from f


def iter_entries(
    keep: Callable[[str, str], bool],
    path: Path = WIKTIONARY_PATH,
) -> Iterator[dict[str, Any]]:
    """Yield fully parsed entries for which keep(word, pos) is true."""
    for line in iter_lines(path):
        wp = peek_word_pos(line)
        if wp is None or not keep(*wp):
            continue
        yield json.loads(line)


def sense_is_pointer(sense: dict[str, Any]) -> bool:
    tags = set(sense.get("tags") or ())
    if tags & POINTER_TAGS:
        return True
    gloss = (sense.get("glosses") or [""])[-1]
    return gloss.startswith(DROP_GLOSS_PREFIXES)


def sense_is_dropped(sense: dict[str, Any]) -> bool:
    tags = set(sense.get("tags") or ())
    return bool(tags & DROP_SENSE_TAGS) or not sense.get("glosses")


def _is_regional(tag: str) -> bool:
    # kaikki writes place/community labels capitalised: Louisiana, Rastafari, Scotland, Egypt.
    return tag[:1].isupper() and tag not in ("US", "UK", "British", "American")


def sense_is_restricted(sense: dict[str, Any]) -> bool:
    tags = set(sense.get("tags") or ())
    return bool(tags & RESTRICTED_TAGS) or any(_is_regional(t) for t in tags)


def form_of_targets(entry: dict[str, Any], *, trusted_only: bool = False) -> list[str]:
    """Lemmas this entry says it is a form of (e.g. wives → wife).

    With trusted_only, skip pointers whose sense is slang/dialectal/regional
    ("geaux → go"), so lemma resolution never maps ordinary text to the wrong word.
    """
    out: list[str] = []
    for s in entry.get("senses") or ():
        if trusted_only and sense_is_restricted(s):
            continue
        for ref in s.get("form_of") or ():
            w = ref.get("word")
            if w and w not in out:
                out.append(w)
    return out


def has_usable_sense(entry: dict[str, Any], *, strict: bool = False) -> bool:
    """At least one real meaning (not a pointer, not dropped). strict also rejects restricted senses
    and Wiktionary's sum-of-parts marker, which is what a phrase needs to earn an entry."""
    for s in entry.get("senses") or ():
        if sense_is_pointer(s) or sense_is_dropped(s):
            continue
        if strict:
            if sense_is_restricted(s):
                continue
            if gloss_text(s).startswith("Used other than figuratively or idiomatically"):
                continue
        return True
    return False


def gloss_text(sense: dict[str, Any]) -> str:
    """Prefer raw_glosses (keeps the '(music)'-style labels), full nested path joined."""
    raw = sense.get("raw_glosses") or sense.get("glosses") or []
    parts = [g.strip() for g in raw if g and g.strip()]
    # raw_glosses sometimes splits the label into its own element: "(transitive)", "To ...".
    if len(parts) >= 2 and parts[0].startswith("(") and parts[0].endswith(")"):
        parts = [parts[0] + " " + parts[1], *parts[2:]]
    return " → ".join(parts)


def pick_ipa(entry: dict[str, Any]) -> str:
    """Prefer RP/UK, then General American, then anything complete. Strips slashes and brackets."""
    best: tuple[int, str] | None = None
    for s in entry.get("sounds") or ():
        ipa = s.get("ipa")
        if not ipa:
            continue
        cleaned = ipa.strip().strip("/[]")
        if not cleaned or cleaned.startswith("-") or cleaned.endswith("-"):
            continue  # partial pronunciation like "-tʃuːn"
        tags = set(s.get("tags") or ())
        if tags & {"Received-Pronunciation", "UK", "British"}:
            score = 0
        elif tags & {"General-American", "US"}:
            score = 1
        else:
            score = 2
        if best is None or score < best[0]:
            best = (score, cleaned)
    return best[1] if best else ""


def form_label(tags: list[str]) -> str | None:
    t = frozenset(tags) - FORM_IGNORED_TAGS
    for want, label in FORM_LABELS:
        if t == want:
            return label
    return None
