#!/usr/bin/env python
"""Step 7 (Phase 3 experiment) — pre-written per-sense contrast notes.

Reads generated entries (their Hindi senses), asks the model for one note per
sense (contracts/schemas/sense-notes.json), validates the count/indexes, and
upserts `senseNotes { _id: word, notes: [..] }` into Mongo. The API's
CONTEXT_MODE=index path then only classifies the sense and attaches these.

Usage:  python 07_notes.py --words single,fortune,mind [--in data/generated.jsonl] [--model gpt-5.6-luna]
"""

from __future__ import annotations

import argparse
import json
import logging
import sys
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from pymongo import MongoClient, UpdateOne

from arth_pipeline.config import DATA_DIR, config, read_jsonl, read_wordlist
from arth_pipeline.contracts import prompt_text, schema
from arth_pipeline.generate import cost_usd
from arth_pipeline.llm.openai_provider import OpenAIProvider
from arth_pipeline.llm.provider import JsonRequest, Usage
from arth_pipeline.models.sense_notes import SenseNotes

logging.basicConfig(level=logging.WARNING)
log = logging.getLogger("07_notes")


def request(entry: dict[str, Any], model: str) -> JsonRequest:
    payload = {
        "word": entry["word"],
        "senses": [
            {
                "index": s["index"],
                "partOfSpeech": s["partOfSpeech"],
                "meaning": s["meaning"],
                "definition": s["definition"],
            }
            for s in entry["senses"]
        ],
    }
    return JsonRequest(
        custom_id=entry["word"],
        model=model,
        system=prompt_text("notes-system"),
        messages=[{"role": "user", "content": json.dumps(payload, ensure_ascii=False)}],
        schema_name="sense_notes",
        schema=schema("sense-notes"),
        temperature=config.temperature,
        max_output_tokens=1200,
    )


def parse(entry: dict[str, Any], content: str) -> list[str]:
    notes = SenseNotes.model_validate_json(content).notes
    if [n.index for n in notes] != [s["index"] for s in entry["senses"]]:
        raise ValueError(f"indexes {[n.index for n in notes]} != {[s['index'] for s in entry['senses']]}")
    return [n.note for n in notes]


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--in", dest="inp", type=Path, default=DATA_DIR / "generated.jsonl")
    ap.add_argument("--words", help="comma-separated")
    ap.add_argument("--words-file", type=Path)
    ap.add_argument("--model", default=config.model_tail)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    entries = {row["word"]: row["entry"] for row in read_jsonl(args.inp)}
    wanted = [w.strip() for w in (args.words or "").split(",") if w.strip()]
    if args.words_file:
        wanted += read_wordlist(args.words_file)
    targets = [entries[w] for w in wanted if w in entries and len(entries[w]["senses"]) > 1]
    missing = [w for w in wanted if w not in entries]
    if missing:
        print(f"not in {args.inp.name}: {missing}", file=sys.stderr)
    print(f"{len(targets)} words with >1 sense")
    if args.dry_run:
        return

    provider = OpenAIProvider(config.openai_api_key)
    ops: list[UpdateOne] = []
    total = Usage()
    for e in targets:
        req = request(e, args.model)
        res = provider.complete(req)
        total = total + res.usage
        try:
            notes = parse(e, res.content or "")
        except Exception as ex:  # noqa: BLE001
            log.warning("%s: %s — retrying once", e["word"], ex)
            retry = JsonRequest(
                **{
                    **req.__dict__,
                    "messages": [
                        *req.messages,
                        {"role": "assistant", "content": res.content or "{}"},
                        {
                            "role": "user",
                            "content": f"That failed validation: {ex}. One note per sense, same indexes.",
                        },
                    ],
                }
            )
            res = provider.complete(retry)
            total = total + res.usage
            try:
                notes = parse(e, res.content or "")
            except Exception as ex2:  # noqa: BLE001
                log.error("%s: skipped — %s", e["word"], ex2)
                continue
        print(f"  {e['word']}: {notes[0][:70]}…")
        ops.append(
            UpdateOne(
                {"_id": e["word"]},
                {"$set": {"notes": notes, "model": res.model, "updatedAt": datetime.now(UTC)}},
                upsert=True,
            )
        )
    if ops:
        db = MongoClient(config.mongodb_uri, serverSelectionTimeoutMS=5000).get_default_database()
        r = db["senseNotes"].bulk_write(ops, ordered=False)
        print(f"senseNotes: {r.upserted_count} inserted, {r.modified_count} updated")
    c = cost_usd(args.model, total, batch=False)
    print(
        f"tokens: input {total.input_tokens:,} output {total.output_tokens:,}" + (f" ≈ ${c:.4f}" if c else "")
    )


if __name__ == "__main__":
    main()
