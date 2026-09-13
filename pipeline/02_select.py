#!/usr/bin/env python
"""Step 2 — pick the headwords to build, by frequency.

Walks wordfreq's ranked English list; each token is either a Wiktionary headword
itself or an inflected form pointing at one (wives → wife). The first N distinct
lemmas win, each stamped with the rank of the token that brought it in. Then
multi-word Wiktionary entries whose every token is among those lemmas (or their
forms) are added as phrases.

Every headword gets a `tier`: "top" for freqRank <= LLM_TOP_TIER_SIZE, else "tail".
04_generate.py routes the model on it.

Usage:  python 02_select.py --n 500 [--max-phrases 200] [--out data/select.json]
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import defaultdict
from pathlib import Path

from wordfreq import top_n_list

from arth_pipeline.config import DATA_DIR, config, read_wordlist
from arth_pipeline.normalize import normalize_word
from arth_pipeline.wiktionary import (
    CONTENT_POS,
    form_label,
    form_of_targets,
    has_usable_sense,
    iter_lines,
    peek_word_pos,
)

# Phrases with a placeholder token can never be matched literally in running text.
PLACEHOLDER_TOKENS = {"one's", "one", "oneself", "someone", "someone's", "somebody", "something", "somewhere"}


def token_ok(tok: str) -> bool:
    if not tok or tok[0] in "'-" or tok[-1] == "-":
        return False
    core = tok.replace("'", "").replace("-", "")
    return core.isalpha() and core.islower()


def phrase_ok(word: str, entry: dict) -> bool:
    toks = word.split(" ")
    if not 2 <= len(toks) <= 4 or not all(token_ok(t) for t in toks):
        return False
    if set(toks) & PLACEHOLDER_TOKENS or len(set(toks)) == 1:
        return False
    return has_usable_sense(entry, strict=True)


def scan_wiktionary() -> tuple[set[str], dict[str, str], dict[str, list[str]]]:
    """One pass: headwords with real senses, form → lemma, and multi-word headwords → tokens."""
    headwords: set[str] = set()
    form_to_lemma: dict[str, str] = {}
    phrases: dict[str, list[str]] = {}
    n = 0
    for line in iter_lines():
        n += 1
        wp = peek_word_pos(line)
        if wp is None:
            continue
        word, pos = wp
        if pos not in CONTENT_POS:
            continue
        entry = json.loads(line)
        if has_usable_sense(entry):
            headwords.add(word)
            if " " in word and phrase_ok(word, entry):
                phrases[word] = word.split(" ")
            # Inflections listed on the headword itself (fortune → fortunes), only
            # rows with a tag set we can label; that excludes alt spellings and table noise.
            if " " not in word:
                for f in entry.get("forms") or ():
                    form = f.get("form")
                    if not form or form == word or " " in form or not token_ok(form):
                        continue
                    if form_label(f.get("tags") or []):
                        form_to_lemma.setdefault(form.lower(), word)
        if token_ok(word):
            for target in form_of_targets(entry, trusted_only=True):
                if target != word and " " not in target:
                    form_to_lemma.setdefault(word.lower(), target)
        if n % 200_000 == 0:
            print(f"\r  scanned {n:,} lines", end="", file=sys.stderr)
    print(file=sys.stderr)
    return headwords, form_to_lemma, phrases


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--n", type=int, default=500, help="number of single-word headwords")
    ap.add_argument("--max-phrases", type=int, default=200)
    ap.add_argument(
        "--extra-words",
        type=Path,
        default=None,
        help="text file, one word per line, always included with their true wordfreq rank (review runs)",
    )
    ap.add_argument("--out", type=Path, default=DATA_DIR / "select.json")
    args = ap.parse_args()

    headwords, form_to_lemma, phrases = scan_wiktionary()
    print(f"wiktionary: {len(headwords):,} headwords, {len(form_to_lemma):,} forms, {len(phrases):,} phrases")

    ranked = top_n_list("en", 300_000)
    selected: dict[str, dict] = {}
    via_form = 0
    for rank, tok in enumerate(ranked, start=1):
        if not token_ok(tok):
            continue
        key = normalize_word(tok)
        if key in headwords:
            lemma = key
        elif key in form_to_lemma and form_to_lemma[key] in headwords:
            lemma = form_to_lemma[key]
            via_form += 1
        else:
            continue
        if " " in lemma or lemma in selected:
            continue
        selected[lemma] = {
            "word": lemma,
            "freqRank": rank,
            "tier": "top" if rank <= config.top_tier_size else "tail",
            "isPhrase": False,
        }
        if len(selected) >= args.n:
            break
    print(f"selected {len(selected)} headwords ({via_form} tokens resolved via forms); last rank {rank}")

    if args.extra_words:
        rank_of = {tok: i for i, tok in enumerate(ranked, start=1)}
        added = 0
        for raw in read_wordlist(args.extra_words):
            w = normalize_word(raw)
            if not w or w in selected:
                continue
            lemma = w if w in headwords else form_to_lemma.get(w)
            if lemma is None or lemma not in headwords or lemma in selected:
                if lemma is None:
                    print(f"  extra word not in Wiktionary, skipped: {raw!r}", file=sys.stderr)
                continue
            r = rank_of.get(lemma, len(ranked) + 1)
            selected[lemma] = {
                "word": lemma,
                "freqRank": r,
                "tier": "top" if r <= config.top_tier_size else "tail",
                "isPhrase": " " in lemma,
            }
            added += 1
        print(f"extra words: {added} added from {args.extra_words}")

    # Phrases: every token must resolve to a selected lemma. Rank = rarest constituent.
    lemma_rank = {w: e["freqRank"] for w, e in selected.items()}
    chosen: list[dict] = []
    for phrase, toks in phrases.items():
        ranks = []
        for t in toks:
            k = normalize_word(t)
            lemma = k if k in lemma_rank else form_to_lemma.get(k)
            if lemma is None or lemma not in lemma_rank:
                break
            ranks.append(lemma_rank[lemma])
        else:
            r = max(ranks)
            tier = "top" if r <= config.top_tier_size else "tail"
            chosen.append({"word": phrase, "freqRank": r, "tier": tier, "isPhrase": True})
    chosen.sort(key=lambda e: (e["freqRank"], e["word"]))
    chosen = chosen[: args.max_phrases]
    print(f"phrases: {len(chosen)} kept (cap {args.max_phrases})")

    # Forms that point at selected lemmas — 05_load.py needs these for the `forms` collection.
    forms_out: dict[str, list[str]] = defaultdict(list)
    for form, lemma in form_to_lemma.items():
        if lemma in selected and form != lemma:
            forms_out[lemma].append(form)

    out = {
        "n": args.n,
        "topTierSize": config.top_tier_size,
        "headwords": [*selected.values(), *chosen],
        "forms": {lemma: sorted(fs) for lemma, fs in sorted(forms_out.items())},
    }
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(out, ensure_ascii=False, indent=1), encoding="utf-8")
    tiers = defaultdict(int)
    for h in out["headwords"]:
        tiers[h["tier"]] += 1
    n_forms = sum(len(v) for v in forms_out.values())
    print(f"wrote {args.out}: {len(out['headwords'])} headwords ({dict(tiers)}), {n_forms} forms")


if __name__ == "__main__":
    main()
