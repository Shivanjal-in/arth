#!/usr/bin/env python
"""Step 3 — pull senses, IPA, examples, synonyms/antonyms and labelled forms for the
selected headwords out of Wiktionary into data/extract.json.

This is the model's input. Senses are Wiktionary's, capped at MAX_SENSES per word,
taken round-robin across the word's POS entries so a noun+verb word keeps both.
The model translates these senses and never invents its own (Section 8).

Usage:  python 03_extract.py [--in data/select.json] [--out data/extract.json]
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any

from arth_pipeline.config import DATA_DIR, config
from arth_pipeline.wiktionary import (
    CONTENT_POS,
    POS_HINDI,
    form_label,
    gloss_text,
    iter_entries,
    pick_ipa,
    sense_is_dropped,
    sense_is_pointer,
    sense_is_restricted,
)

MAX_EXAMPLE_CHARS = 160
MIN_QUOTATION_YEAR = 1800  # older quotations read as a foreign language to our reader
_YEAR_RE = re.compile(r"\b(1[0-9]{3}|20[0-9]{2})\b")
_YEAR_PREFIX_RE = re.compile(r"^(1[0-9]{3}|20[0-9]{2})\b")
# POS that rarely matter to a reader get at most one sense so they don't crowd out nouns/verbs.
MINOR_POS = {"intj", "particle", "det", "article", "contraction", "num"}
# A POS earns a guaranteed slot only if its best sense has real evidence of use:
# at least MIN_POS_SCORE, and at least MIN_POS_RATIO of the word's top score.
MIN_POS_SCORE = 5
MIN_POS_RATIO = 0.1


def clean_example(text: str) -> str | None:
    t = " ".join(text.split())
    if not t or len(t) > MAX_EXAMPLE_CHARS or "[…]" in t or "…" in t[:3]:
        return None
    if _YEAR_PREFIX_RE.match(t):
        return None  # a citation line that leaked into the example text
    # Old-spelling quotations (ſ, þ) confuse more than they help.
    if any(ch in t for ch in "ſþȝ"):
        return None
    return t


def sense_examples(sense: dict[str, Any], limit: int) -> list[str]:
    """Plain usage examples first; a post-1800 quotation only as a fallback. Shortest first."""
    plain: list[str] = []
    quotes: list[str] = []
    for ex in sense.get("examples") or ():
        t = clean_example(ex.get("text") or "")
        if not t:
            continue
        if ex.get("type") == "quotation" or ex.get("ref"):
            m = _YEAR_RE.search(ex.get("ref") or "")
            if m and int(m.group(1)) >= MIN_QUOTATION_YEAR and t not in quotes:
                quotes.append(t)
        elif t not in plain:
            plain.append(t)
    plain.sort(key=len)
    quotes.sort(key=len)
    return (plain + quotes)[:limit]


def sense_score(sense: dict[str, Any]) -> int:
    """Higher = more likely the meaning a reader meets.

    Wiktionary lists senses etymologically, not by commonness. The strongest
    commonness signal in kaikki is how many languages editors bothered to
    translate a sense into: for "fair", "Just." has 91 sense-level translations
    and "(shipbuilding) smooth" has 0. Examples and synonyms nudge; domain
    labels, archaic/dated and restricted registers push down without excluding.
    """
    score = len(sense.get("translations") or ())
    if any(ex.get("type") != "quotation" and not ex.get("ref") for ex in sense.get("examples") or ()):
        score += 3
    if sense.get("synonyms"):
        score += 1
    gloss = gloss_text(sense)
    if gloss.startswith("("):
        score -= 2
    tags = set(sense.get("tags") or ())
    if tags & {"archaic", "dated", "literary", "historical"}:
        score -= 4
    if sense_is_restricted(sense):
        score -= 8
    return score


def related(entry: dict[str, Any], senses: list[dict[str, Any]], key: str, limit: int) -> list[str]:
    """Entry-level plus sense-level synonyms/antonyms, direct ones only (no Thesaurus dumps)."""
    out: list[str] = []
    word = entry["word"]
    pools = [entry.get(key) or []] + [s.get(key) or [] for s in senses]
    for pool in pools:
        for item in pool:
            w = item.get("word")
            if not w or w == word or item.get("source") or " " in w and len(w.split()) > 3:
                continue
            if item.get("tags") and set(item["tags"]) & {"obsolete", "archaic", "rare"}:
                continue
            if w not in out:
                out.append(w)
            if len(out) >= limit:
                return out
    return out


def extract_word(word: str, entries: list[dict[str, Any]], is_phrase: bool) -> dict[str, Any] | None:
    # One bucket per POS (merging etymologies), each sorted by score, stable.
    buckets: dict[str, list[tuple[int, int, dict[str, Any]]]] = defaultdict(list)
    order = 0
    ipa = ""
    forms: list[dict[str, str]] = []
    seen_forms: set[str] = set()
    synonyms: list[str] = []
    antonyms: list[str] = []

    for e in entries:
        pos = e.get("pos", "")
        if pos not in CONTENT_POS:
            continue
        usable = [s for s in e.get("senses") or () if not sense_is_pointer(s) and not sense_is_dropped(s)]
        if not usable:
            continue
        pos_hi = "मुहावरा" if is_phrase and pos in ("phrase", "prep_phrase") else POS_HINDI.get(pos, pos)
        for s in usable:
            order += 1
            buckets[pos].append(
                (
                    -sense_score(s),
                    order,
                    {
                        "partOfSpeech": pos_hi,
                        "gloss": gloss_text(s),
                        "examples": sense_examples(s, config.max_examples_per_sense),
                    },
                )
            )
        ipa = ipa or pick_ipa(e)
        for f in e.get("forms") or ():
            label = form_label(f.get("tags") or [])
            form = (f.get("form") or "").strip()
            if label and form and form != word and form.lower() not in seen_forms:
                seen_forms.add(form.lower())
                forms.append({"en": form.lower(), "label": label})
        for w in related(e, usable, "synonyms", config.max_synonyms):
            if w not in synonyms and len(synonyms) < config.max_synonyms:
                synonyms.append(w)
        for w in related(e, usable, "antonyms", config.max_synonyms):
            if w not in antonyms and len(antonyms) < config.max_synonyms:
                antonyms.append(w)

    if not buckets:
        return None

    # Two passes. First, the best sense of every POS that is actually in use
    # (score >= MIN_POS_SCORE) so "set" keeps noun and verb. Then fill the
    # remaining slots by score across all POS, so a word's eight senses are its
    # eight commonest, not one obscure verb per POS.
    ranked = sorted(
        ((score, order, pos, sense) for pos, b in buckets.items() for (score, order, sense) in b),
        key=lambda x: (x[0], x[1]),
    )
    senses: list[dict[str, Any]] = []
    seen_pos: set[str] = set()
    top_score = -ranked[0][0] if ranked else 0
    floor = max(MIN_POS_SCORE, MIN_POS_RATIO * top_score)
    for score, _order, pos, sense in ranked:
        if pos in seen_pos or -score < floor:
            continue
        seen_pos.add(pos)
        senses.append(sense)
    minor_used = {pos for pos in seen_pos if pos in MINOR_POS}
    for _score, _order, pos, sense in ranked:
        if len(senses) >= config.max_senses_per_entry:
            break
        if any(sense is s for s in senses) or pos in minor_used:
            continue
        senses.append(sense)
    senses = senses[: config.max_senses_per_entry]
    senses = [{"index": i, **s} for i, s in enumerate(senses)]

    return {
        "word": word,
        "ipa": ipa,
        "isPhrase": is_phrase,
        "senses": senses,
        "synonyms": synonyms,
        "antonyms": antonyms,
        "forms": forms[:8],
    }


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--in", dest="inp", type=Path, default=DATA_DIR / "select.json")
    ap.add_argument("--out", type=Path, default=DATA_DIR / "extract.json")
    args = ap.parse_args()

    select = json.loads(args.inp.read_text(encoding="utf-8"))
    wanted = {h["word"]: h for h in select["headwords"]}
    print(f"extracting {len(wanted)} headwords", file=sys.stderr)

    grouped: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for e in iter_entries(lambda w, p: w in wanted and p in CONTENT_POS):
        grouped[e["word"]].append(e)

    out: list[dict[str, Any]] = []
    missing: list[str] = []
    sense_counts: dict[int, int] = defaultdict(int)
    for word, meta in wanted.items():
        x = extract_word(word, grouped.get(word, []), meta["isPhrase"])
        if x is None:
            missing.append(word)
            continue
        x["freqRank"] = meta["freqRank"]
        x["tier"] = meta["tier"]
        out.append(x)
        sense_counts[len(x["senses"])] += 1

    payload = {"forms": select["forms"], "entries": out}
    args.out.write_text(json.dumps(payload, ensure_ascii=False, indent=1), "utf-8")
    hist = dict(sorted(sense_counts.items()))
    print(f"wrote {args.out}: {len(out)} entries; senses/entry histogram {hist}")
    if missing:
        print(f"no usable senses for {len(missing)}: {missing[:20]}", file=sys.stderr)
    total_senses = sum(len(x["senses"]) for x in out)
    print(f"total senses {total_senses}, avg {total_senses / max(1, len(out)):.1f}")


if __name__ == "__main__":
    main()
