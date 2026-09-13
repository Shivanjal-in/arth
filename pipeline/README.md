# pipeline/

Builds the English→Hindi dictionary: Wiktionary → LLM batch → Mongo. Python 3.11,
standalone, run by hand. Not part of the API deploy.

```sh
python3.11 -m venv .venv && .venv/bin/pip install -e '.[dev]'
cp .env.example .env            # add OPENAI_API_KEY and MONGODB_URI (same Atlas cluster as api/)
.venv/bin/pytest                # normalize vectors + generation validation/retry
.venv/bin/ruff check .
```

## Steps

Each script is standalone and documents its flags in `--help`. Data lives in `data/` (gitignored).

| Step | What | Output |
|---|---|---|
| `01_download.py` | kaikki.org English Wiktionary JSONL (3.2 GB), resumable | `data/wiktionary-en.jsonl` |
| `02_select.py --n 500` | top-N lemmas by `wordfreq` (forms resolved: wives → wife), phrases whose tokens are all selected, `tier` per word | `data/select.json` |
| `03_extract.py` | senses (≤ 8, round-robin across POS, scored), IPA, examples, synonyms/antonyms, labelled forms | `data/extract.json` |
| `04_generate.py --mode …` | Structured Outputs on `contracts/schemas/entry-generation.json`, cross-checked against the input, one retry, real token cost printed | `data/generated.jsonl` |
| `05_load.py` | `bulkWrite` upserts in batches of 1000 into `entries`, `forms`, `phrases` | Mongo |
| `06_report.py sample \| compare` | Markdown for human review; side-by-side model comparison | `data/*.md` |

`--extra-words wordlists/compare50.txt` on step 2 forces specific words into a run with
their true frequency rank, for reviews.

## The 500-word slice (Phase 2 checkpoint)

```sh
.venv/bin/python 02_select.py --n 500 --extra-words wordlists/compare50.txt
.venv/bin/python 03_extract.py
.venv/bin/python 04_generate.py --mode batch-submit --name run500       # ~750 requests, ≤24h, half price
.venv/bin/python 04_generate.py --mode batch-status --name run500
.venv/bin/python 04_generate.py --mode batch-fetch  --name run500       # validates, retries failures live, prints cost
.venv/bin/python 06_report.py sample --n 20 --out data/review-20.md

# same 50 words on three models, live, side by side
for m in gpt-5.6-luna gpt-5.6-terra gpt-5.6-sol; do
  .venv/bin/python 04_generate.py --mode live --model $m --words-file wordlists/compare50.txt --out data/compare-$m.jsonl
done
.venv/bin/python 06_report.py compare data/compare-gpt-5.6-luna.jsonl data/compare-gpt-5.6-terra.jsonl data/compare-gpt-5.6-sol.jsonl

.venv/bin/python 05_load.py
```

## Rules baked in

- The model only ever sees Wiktionary's senses and must return exactly those, in order,
  with the same `index` and `partOfSpeech` (`arth_pipeline/generate.py::parse_generation`).
  Hindi fields must contain Devanagari and no Latin letters. `en` sides of
  synonyms/antonyms/forms must match the input exactly. Fail → one retry with the error
  appended → skip and log to `generated.failed.jsonl`.
- System prompt and gold examples come from `contracts/prompts/` and
  `contracts/prompt-examples.json` and form a fixed prefix (prompt caching).
- Model names and prices live in `.env`. Routing is `tier` → `LLM_MODEL_TOP` / `LLM_MODEL_TAIL`;
  `--model` overrides for comparisons.
- `arth_pipeline/models/` is generated from `contracts/schemas` by `./gen-models.sh`. Never hand-edit.

## Full build (what was actually run)

```sh
.venv/bin/python 02_select.py --n 20000 --max-phrases 3000 --extra-words wordlists/compare50.txt --out data/select-full.json
.venv/bin/python 03_extract.py --in data/select-full.json --out data/extract-full.json
.venv/bin/python 04_generate.py --mode batch-submit --name full20k --in data/extract-full.json --out data/generated-full.jsonl
.venv/bin/python 04_generate.py --mode batch-fetch  --name full20k --in data/extract-full.json
# entries the batch could not validate (content filter, truncation) → live with more headroom
.venv/bin/python 04_generate.py --mode live --max-output-tokens 7000 --in data/extract-full.json \
    --words-file data/failed-words.txt --out data/generated-full.jsonl
.venv/bin/python 05_load.py --in data/generated-full.jsonl --extract data/extract-full.json
```

23,001 entries (20,000 headwords + 3,000 phrases + review extras), 85k senses, on gpt-5.6-luna:
$8.03 batch + ~$0.10 live retries. Batch jobs are chunked at 4,000 requests (200 MB file limit).

## Known limitations (deliberate for now)

- Wiktionary phrases with placeholders (`make up one's mind`) are skipped: they can't be
  matched literally in text. A pattern matcher is a later improvement.
- Wiktionary orders senses etymologically; `03_extract.py` re-ranks with a light heuristic
  (plain examples, synonyms, no domain label, not slang/regional). Rare senses still slip
  into the 8 sometimes — the review sample will show how often.
- Regional/slang senses are dropped for phrase and form selection but kept (ranked low) in
  headword senses.
