#!/usr/bin/env python
"""Step 5 — load generated entries into Mongo with idempotent bulkWrite upserts (batches of 1000).

Writes three collections, natural key as _id:
  entries   DictionaryEntry + freqRank, tier, updatedAt
  forms     inflected form → lemma (from Wiktionary, via 02_select/03_extract)
  phrases   multi-word lemma → firstToken, tokenCount (plus each phrase's inflected forms)

Usage:  python 05_load.py [--in data/generated.jsonl] [--extract data/extract.json] [--dry-run]
"""

from __future__ import annotations

import argparse
import json
import sys
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from pymongo import MongoClient, UpdateOne
from pymongo.collection import Collection

from arth_pipeline.config import DATA_DIR, config
from arth_pipeline.models.dictionary_entry import DictionaryEntry
from arth_pipeline.normalize import normalize_sentence, normalize_word

BATCH = 1000


def upsert(col: Collection, ops: list[UpdateOne], label: str, dry: bool) -> None:
    if dry or not ops:
        print(f"  {label}: {len(ops)} ops{' (dry run)' if dry else ''}")
        return
    upserted = modified = 0
    for i in range(0, len(ops), BATCH):
        r = col.bulk_write(ops[i : i + BATCH], ordered=False)
        upserted += r.upserted_count
        modified += r.modified_count
    print(f"  {label}: {len(ops)} ops → {upserted} inserted, {modified} updated")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--in", dest="inp", type=Path, default=DATA_DIR / "generated.jsonl")
    ap.add_argument("--extract", type=Path, default=DATA_DIR / "extract.json")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    extract = json.loads(args.extract.read_text(encoding="utf-8"))
    meta = {e["word"]: e for e in extract["entries"]}
    now = datetime.now(UTC)

    entry_ops: list[UpdateOne] = []
    form_ops: dict[str, UpdateOne] = {}
    phrase_ops: dict[str, UpdateOne] = {}
    bad = 0
    for line in args.inp.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        row = json.loads(line)
        try:
            entry = DictionaryEntry.model_validate(row["entry"])  # never load anything off-contract
        except Exception as e:  # noqa: BLE001
            bad += 1
            print(f"  invalid entry {row.get('word')!r}: {e}", file=sys.stderr)
            continue
        m = meta.get(entry.word, {})
        is_phrase = entry.isPhrase
        _id = normalize_sentence(entry.word).lower() if is_phrase else normalize_word(entry.word)
        doc: dict[str, Any] = {
            **entry.model_dump(),
            "word": _id,
            "freqRank": m.get("freqRank", row.get("freqRank", 10**6)),
            "tier": m.get("tier", "tail"),
            "model": row.get("model"),
            "updatedAt": now,
        }
        entry_ops.append(UpdateOne({"_id": _id}, {"$set": doc}, upsert=True))

        if is_phrase:
            toks = _id.split(" ")
            phrase_ops[_id] = UpdateOne(
                {"_id": _id},
                {"$set": {"lemma": _id, "firstToken": toks[0], "tokenCount": len(toks)}},
                upsert=True,
            )
            for f in entry.forms:  # "has to" → "have to"
                fid = normalize_sentence(f.en).lower()
                ft = fid.split(" ")
                if 2 <= len(ft) <= 4 and fid != _id:
                    phrase_ops[fid] = UpdateOne(
                        {"_id": fid},
                        {"$set": {"lemma": _id, "firstToken": ft[0], "tokenCount": len(ft)}},
                        upsert=True,
                    )
        else:
            for f in entry.forms:
                fid = normalize_word(f.en)
                if fid and " " not in fid and fid != _id:
                    form_ops.setdefault(fid, UpdateOne({"_id": fid}, {"$set": {"lemma": _id}}, upsert=True))

    # Inflections Wiktionary lists as separate form-of entries (went → go).
    loaded = {op._filter["_id"] for op in entry_ops}  # noqa: SLF001
    for lemma, forms in extract.get("forms", {}).items():
        if lemma not in loaded:
            continue
        for f in forms:
            fid = normalize_word(f)
            if fid and fid != lemma and fid not in loaded:
                form_ops.setdefault(fid, UpdateOne({"_id": fid}, {"$set": {"lemma": lemma}}, upsert=True))

    print(
        f"{len(entry_ops)} entries ({bad} invalid skipped), {len(form_ops)} forms, {len(phrase_ops)} phrases"
    )  # noqa: E501

    client = MongoClient(config.mongodb_uri, serverSelectionTimeoutMS=5000)
    db = client.get_default_database()
    upsert(db["entries"], entry_ops, "entries", args.dry_run)
    upsert(db["forms"], list(form_ops.values()), "forms", args.dry_run)
    upsert(db["phrases"], list(phrase_ops.values()), "phrases", args.dry_run)
    if not args.dry_run:
        db["entries"].create_index("freqRank")
        db["phrases"].create_index("firstToken")
        db["cache"].create_index("kind")
        print("  indexes ensured")


if __name__ == "__main__":
    main()
