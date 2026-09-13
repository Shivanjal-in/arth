# Arth

A mobile PDF reader for Hindi-speaking readers of English books. Tap a word or select
a sentence and get the Hindi meaning — explained in plain Hindi, for *this* sentence.

```
app/        Flutter app (Phase 4)
api/        Fastify + Mongoose API — /v1/lookup, /v1/context, /v1/translate, /v1/phrases/match
pipeline/   Python dictionary build: Wiktionary → LLM batch → Mongo (Phase 2)
contracts/  JSON Schemas, normalization spec + test vectors shared by all three
```

## Status

- [x] Phase 1 — contracts + API skeleton (`/v1/lookup` on a 22-entry hand-written seed)
- [~] Phase 2 — pipeline built and tested; 500-word generation waits on an OpenAI key
- [ ] Phase 3 — `/context`, `/translate`, `/phrases/match`, cache
- [ ] Phase 4 — Flutter app
- [ ] Phase 5 — scale and harden

## Setup

Prereqs: Node ≥ 20.6, a MongoDB Atlas cluster, Flutter 3.x, Python 3.11.

### API

```sh
cd api
cp .env.example .env          # set MONGODB_URI to the Atlas connection string (database: arth)
npm install
npm run seed                  # loads seed/seed.json (idempotent upserts)
npm run dev                   # http://localhost:3000

curl 'localhost:3000/v1/lookup?word=fortune'
curl 'localhost:3000/v1/lookup?word=Wives'      # → wife, via lowercase + forms
curl 'localhost:3000/v1/lookup?word=in%20want%20of'
```

Tests (no Mongo needed — lemma resolution runs on an in-memory store):

```sh
npm test          # normalize vectors, lemma resolution, /lookup route, seed validation
npm run typecheck
```

Both `api/` and `pipeline/` read the same `MONGODB_URI`; the database name is the path segment of the URI and should be `arth`.

### Pipeline

```sh
cd pipeline
python3.11 -m venv .venv && .venv/bin/pip install -e '.[dev]'
cp .env.example .env          # add OPENAI_API_KEY and the same MONGODB_URI as api/
.venv/bin/pytest              # 69 tests: normalize vectors, generation validation + retry
.venv/bin/python 01_download.py && .venv/bin/python 02_select.py --n 500 && .venv/bin/python 03_extract.py
```

See `pipeline/README.md` for the generate → load steps and the review reports.

### Contracts

`contracts/` is the source of truth for wire types and text normalization. See
`contracts/README.md`. Every language's `normalize()` must pass
`contracts/normalize-vectors.json` — TypeScript (`api/test/normalize.test.ts`) and Python
(`pipeline/tests/test_normalize.py`) do; Dart is added in Phase 4.

## Conventions

- Secrets only in `.env`; `.env.example` is checked in. The app never holds the OpenAI key.
- Every LLM call goes through one `LLMProvider` interface; model names live in config.
- Conventional commits, one scope per phase.
- API: TypeScript strict, Zod on every route, one structured log line per request.

## Attribution

Dictionary data derives from the English Wiktionary via [kaikki.org](https://kaikki.org),
licensed CC BY-SA. Headword frequencies from [`wordfreq`](https://github.com/rspeer/wordfreq) (MIT).
