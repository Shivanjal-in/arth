#!/usr/bin/env python
"""Step 4 — generate the Hindi layer with the LLM (Structured Outputs, validated, one retry).

Modes:
  live           synchronous calls, in order. For small runs, reviews and model comparisons.
  batch-submit   upload a Batch API job (half price, ≤24h); writes data/batches/<name>.json
  batch-status   print progress
  batch-fetch    download results, validate, retry failures live, write output

Routing: each headword's `tier` (from 02_select.py) picks LLM_MODEL_TOP or LLM_MODEL_TAIL
unless --model overrides for every word. Output is JSONL (one DictionaryEntry per line
plus provenance and token usage); repeated runs merge by word.

Examples:
  python 04_generate.py --mode live --limit 5
  python 04_generate.py --mode live --model gpt-5.6-sol --words-file data/compare50.txt \
      --out data/compare-sol.jsonl
  python 04_generate.py --mode batch-submit --name run500
  python 04_generate.py --mode batch-fetch  --name run500
"""

from __future__ import annotations

import argparse
import json
import logging
import sys
import time
from collections import defaultdict
from pathlib import Path
from typing import Any

from arth_pipeline.config import DATA_DIR, config, read_wordlist
from arth_pipeline.generate import Outcome, build_request, cost_usd, generate_live, settle_batch
from arth_pipeline.llm.openai_provider import OpenAIProvider
from arth_pipeline.llm.provider import Usage
from arth_pipeline.normalize import normalize_word

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s: %(message)s")
log = logging.getLogger("04_generate")

BATCH_DIR = DATA_DIR / "batches"


def load_extracts(path: Path, args: argparse.Namespace) -> list[dict[str, Any]]:
    entries = json.loads(path.read_text(encoding="utf-8"))["entries"]
    if args.tier:
        entries = [e for e in entries if e["tier"] == args.tier]
    if args.words_file:
        wanted = [normalize_word(w) for w in read_wordlist(args.words_file)]
        by = {e["word"]: e for e in entries}
        missing = [w for w in wanted if w not in by]
        if missing:
            log.warning("%d words from --words-file not in extract: %s", len(missing), missing[:10])
        entries = [by[w] for w in wanted if w in by]
    if args.words:
        wanted = {normalize_word(w) for w in args.words.split(",")}
        entries = [e for e in entries if e["word"] in wanted]
    if args.limit:
        entries = entries[: args.limit]
    return entries


def write_outcomes(out_path: Path, outcomes: list[Outcome], mode: str) -> None:
    existing: dict[str, dict[str, Any]] = {}
    if out_path.exists():
        for line in out_path.read_text(encoding="utf-8").splitlines():
            if line.strip():
                row = json.loads(line)
                existing[row["word"]] = row
    failed_path = out_path.with_suffix(".failed.jsonl")
    failed: list[dict[str, Any]] = []
    for o in outcomes:
        row = {
            "word": o.word,
            "model": o.model,
            "mode": mode,
            "attempts": o.attempts,
            "usage": {
                "input": o.usage.input_tokens,
                "cachedInput": o.usage.cached_input_tokens,
                "output": o.usage.output_tokens,
            },
            "generatedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        }
        if o.entry is None:
            failed.append({**row, "error": o.error})
            continue
        existing[o.word] = {**row, "entry": o.entry.model_dump()}
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", encoding="utf-8") as f:
        for row in existing.values():
            f.write(json.dumps(row, ensure_ascii=False) + "\n")
    if failed:
        with failed_path.open("a", encoding="utf-8") as f:
            for row in failed:
                f.write(json.dumps(row, ensure_ascii=False) + "\n")
    print(f"wrote {out_path}: {len(existing)} entries total; {len(failed)} failed → {failed_path.name}")


def report(outcomes: list[Outcome], extracts: list[dict[str, Any]], *, batch: bool) -> None:
    by_model: dict[str, Usage] = defaultdict(Usage)
    n_ok = sum(1 for o in outcomes if o.entry)
    retried = sum(1 for o in outcomes if o.attempts > 1)
    for o in outcomes:
        by_model[o.model] = by_model[o.model] + o.usage
    senses = sum(len(x["senses"]) for x in extracts)
    print("\n=== token usage (real, from API) ===")
    total_cost = 0.0
    priced = True
    for model, u in by_model.items():
        c = cost_usd(model, u, batch=batch)
        priced = priced and c is not None
        total_cost += c or 0.0
        print(
            f"  {model}: input {u.input_tokens:,} (cached {u.cached_input_tokens:,}), "
            f"output {u.output_tokens:,}" + (f", ≈ ${c:.4f}" if c is not None else " (no PRICE_* in .env)")
        )
    n = max(1, len(outcomes))
    tot = sum(by_model.values(), Usage())
    print(f"  entries ok {n_ok}/{len(outcomes)}, retried {retried}; senses {senses} ({senses / n:.1f}/entry)")
    print(f"  per entry: input {tot.input_tokens / n:,.0f}, output {tot.output_tokens / n:,.0f} tokens")
    if priced and outcomes:
        print(
            f"  cost ≈ ${total_cost:.4f} total, ${1000 * total_cost / n:.2f} per 1000 entries "
            f"({'batch' if batch else 'live'} rates)"
        )
    else:
        print("  set PRICE_INPUT_<model> / PRICE_OUTPUT_<model> in .env for a cost estimate")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--mode", choices=["live", "batch-submit", "batch-status", "batch-fetch"], required=True)
    ap.add_argument("--in", dest="inp", type=Path, default=DATA_DIR / "extract.json")
    ap.add_argument("--out", type=Path, default=DATA_DIR / "generated.jsonl")
    ap.add_argument("--name", default="run", help="batch job name (state in data/batches/<name>.json)")
    ap.add_argument("--model", help="override routing: use this model for every word")
    ap.add_argument("--tier", choices=["top", "tail"])
    ap.add_argument("--limit", type=int)
    ap.add_argument("--words", help="comma-separated words to include")
    ap.add_argument("--words-file", type=Path, help="one word per line, in this order")
    ap.add_argument("--dry-run", action="store_true", help="build requests, print one, make no calls")
    args = ap.parse_args()

    extracts = load_extracts(args.inp, args)

    def model_for(x: dict[str, Any]) -> str:
        return args.model or config.model_for_tier(x["tier"])

    if args.dry_run:
        req = build_request(extracts[0], model_for(extracts[0]))
        print(f"{len(extracts)} requests; first:")
        print(
            json.dumps(
                {"model": req.model, "system": req.system[:200] + "…", "messages": req.messages[-1]},
                ensure_ascii=False,
                indent=1,
            )
        )
        prefix_chars = len(req.system) + sum(len(m["content"]) for m in req.messages[:-1])
        print(f"fixed prefix ≈ {prefix_chars:,} chars; schema keys {list(req.schema['properties'])}")
        return

    provider = OpenAIProvider(config.openai_api_key)
    state_path = BATCH_DIR / f"{args.name}.json"

    if args.mode == "live":
        print(f"live: {len(extracts)} entries", file=sys.stderr)
        t = time.time()
        outcomes = generate_live(provider, extracts, model_for)
        print(f"done in {time.time() - t:.0f}s", file=sys.stderr)
        write_outcomes(args.out, outcomes, "live")
        report(outcomes, extracts, batch=False)

    elif args.mode == "batch-submit":
        reqs = [build_request(x, model_for(x)) for x in extracts]
        models = sorted({r.model for r in reqs})
        batch_id = provider.submit_batch(reqs, description=f"arth {args.name}: {len(reqs)} entries")
        BATCH_DIR.mkdir(parents=True, exist_ok=True)
        state_path.write_text(
            json.dumps(
                {
                    "batchId": batch_id,
                    "submittedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                    "models": models,
                    "override": args.model,
                    "words": [x["word"] for x in extracts],
                    "input": str(args.inp),
                    "out": str(args.out),
                },
                indent=1,
            )
        )
        print(f"submitted batch {batch_id} with {len(reqs)} requests on {models}; state → {state_path}")

    elif args.mode == "batch-status":
        st = provider.batch_status(json.loads(state_path.read_text())["batchId"])
        print(f"{st.id}: {st.status} — {st.completed}/{st.total} done, {st.failed} failed")

    elif args.mode == "batch-fetch":
        state = json.loads(state_path.read_text())
        st = provider.batch_status(state["batchId"])
        if not st.done:
            print(f"batch {st.id} is {st.status} ({st.completed}/{st.total}); try later")
            return
        words = set(state["words"])
        all_entries = json.loads(args.inp.read_text(encoding="utf-8"))["entries"]
        extracts = [x for x in all_entries if x["word"] in words]
        override = state.get("override")

        def model_for_state(x: dict[str, Any]) -> str:
            return override or config.model_for_tier(x["tier"])

        results = provider.fetch_batch(state["batchId"])
        print(f"fetched {len(results)} results for {len(extracts)} entries", file=sys.stderr)
        outcomes = settle_batch(provider, extracts, results, model_for_state)
        write_outcomes(Path(state.get("out", args.out)), outcomes, "batch")
        report(outcomes, extracts, batch=True)


if __name__ == "__main__":
    main()
