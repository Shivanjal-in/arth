#!/usr/bin/env python
"""Step 8 — stage Wiktionary senses (English only, no Hindi) for lemmas beyond the
generated set, so the API can generate their Hindi layer on demand the first time
a reader taps them.

Writes two Mongo collections:
  wiktionary  { _id: lemma, freqRank, extract: {…03_extract shape…} }
  forms       { _id: form, lemma, staged: true }   (seed skips staged rows)

Usage:  python 08_stage.py --n 120000 [--skip data/generated-full.jsonl] [--dry-run]
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import sys
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from pymongo import MongoClient, UpdateOne
from wordfreq import top_n_list

from arth_pipeline.config import DATA_DIR, PIPELINE_DIR, config, read_jsonl
from arth_pipeline.normalize import normalize_word
from arth_pipeline.wiktionary import CONTENT_POS, iter_entries


def _load(name: str) -> Any:
    spec = importlib.util.spec_from_file_location(name.replace(".py", ""), PIPELINE_DIR / name)
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader
    spec.loader.exec_module(mod)
    return mod


def _attested(sense: dict[str, Any]) -> bool:
    """Evidence a sense is real usage: a couple of translations or a plain example
    (not a quotation). Domain labels don't disqualify here — a rare word a reader
    tapped is worth a $0.001 generation."""
    if len(sense.get("translations") or ()) >= 2:
        return True
    return any(ex.get("type") != "quotation" and not ex.get("ref") for ex in sense.get("examples") or ())


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--n", type=int, default=120_000, help="frequency rank to stage up to")
    ap.add_argument("--skip", type=Path, default=DATA_DIR / "generated-full.jsonl", help="already generated")
    ap.add_argument("--out", type=Path, default=DATA_DIR / "staged.jsonl")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    select = _load("02_select.py")
    extract = _load("03_extract.py")

    done = {row["word"] for row in read_jsonl(args.skip)} if args.skip.exists() else set()
    headwords, form_to_lemma, _phrases = select.scan_wiktionary()
    print(f"wiktionary: {len(headwords):,} headwords, {len(form_to_lemma):,} forms; generated {len(done):,}")

    ranked = top_n_list("en", 300_000)
    wanted: dict[str, int] = {}
    for rank, tok in enumerate(ranked[: args.n], start=1):
        if not select.token_ok(tok):
            continue
        key = normalize_word(tok)
        lemma = key if key in headwords else form_to_lemma.get(key)
        if lemma is None or lemma not in headwords or " " in lemma:
            continue
        if lemma in done or lemma in wanted:
            continue
        wanted[lemma] = rank
    print(f"staging {len(wanted):,} lemmas (ranks up to {args.n:,})")

    # Second net: headwords wordfreq never saw (bespatter, brimless) but that
    # Wiktionary attests with translations or examples. They get a nominal rank.
    grouped: dict[str, list[dict[str, Any]]] = {}
    attested = 0
    for e in iter_entries(lambda w, p: p in CONTENT_POS and " " not in w and select.token_ok(w)):
        w = e["word"]
        if w in done or (w not in wanted and w not in headwords):
            continue
        if w not in wanted:
            if not any(_attested(s) for s in e.get("senses") or ()):
                continue
            wanted[w] = 400_000
            attested += 1
        grouped.setdefault(w, []).append(e)
    print(f"plus {attested:,} attested lemmas outside the frequency list")

    rows: list[dict[str, Any]] = []
    for lemma, rank in wanted.items():
        x = extract.extract_word(lemma, grouped.get(lemma, []), False)
        if x is None:
            continue
        # Keep the staging compact: one example per sense is enough for the prompt.
        for s in x["senses"]:
            s["examples"] = s["examples"][:1]
        rows.append({"word": lemma, "freqRank": rank, "extract": x})
    with args.out.open("w", encoding="utf-8") as f:
        for r in rows:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    size_mb = args.out.stat().st_size / 1e6
    print(f"wrote {args.out}: {len(rows):,} staged lemmas, {size_mb:.0f} MB")

    staged_lemmas = {r["word"] for r in rows}
    form_ops = [
        UpdateOne({"_id": normalize_word(f)}, {"$set": {"lemma": lemma, "staged": True}}, upsert=True)
        for f, lemma in form_to_lemma.items()
        if lemma in staged_lemmas and normalize_word(f) and normalize_word(f) != lemma
    ]
    print(f"{len(form_ops):,} staged forms")
    if args.dry_run:
        return

    db = MongoClient(config.mongodb_uri, serverSelectionTimeoutMS=5000).get_default_database()
    now = datetime.now(UTC)
    ops = [
        UpdateOne(
            {"_id": r["word"]},
            {"$set": {"freqRank": r["freqRank"], "extract": r["extract"], "updatedAt": now}},
            upsert=True,
        )
        for r in rows
    ]
    for i in range(0, len(ops), 1000):
        db["wiktionary"].bulk_write(ops[i : i + 1000], ordered=False)
    print(f"wiktionary: {len(ops):,} upserted")
    # Never overwrite a form that already points at a generated entry.
    existing = {d["_id"] for d in db["forms"].find({"staged": {"$ne": True}}, {"_id": 1})}
    form_ops = [op for op in form_ops if op._filter["_id"] not in existing]  # noqa: SLF001
    for i in range(0, len(form_ops), 1000):
        db["forms"].bulk_write(form_ops[i : i + 1000], ordered=False)
    print(f"forms: {len(form_ops):,} staged upserted")
    db["wiktionary"].create_index("freqRank")
    print("done", file=sys.stderr)


if __name__ == "__main__":
    main()
