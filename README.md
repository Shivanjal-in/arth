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
- [x] Phase 2 — pipeline; full 23k-entry build on luna loaded to Atlas ($8.10 real cost)
- [x] Phase 3 — `/context`, `/translate` (SSE), `/phrases/match`, content-hash cache, index-only experiment behind `CONTEXT_MODE`
- [x] Phase 4 — Flutter app (reader + tooltip verified on a real PDF; /context and /translate light up with Phase 3)
- [x] Phase 5 — full-size build, prefetch, per-device rate limits, gzip seed, bilingual UI, error/empty states, attribution

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
curl -X POST localhost:3000/v1/context -H 'content-type: application/json' \
  -d '{"word":"single","sentence":"It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife."}'
curl -N -X POST localhost:3000/v1/translate -H 'content-type: application/json' -d '{"text":"It is a truth universally acknowledged."}'   # SSE
curl -X POST localhost:3000/v1/phrases/match -H 'content-type: application/json' -d '{"tokens":["must","be","in","want","of"],"index":3}'
```

`/context` and `/translate` need `OPENAI_API_KEY` in `api/.env`. Every LLM call goes through
`src/llm/provider.ts`; results are cached forever in the `cache` collection by content hash
(`contracts/normalize.md`), with an in-process LRU in front. `/v1/health` reports the hit rate.
`CONTEXT_MODE=index` switches `/context` to the index-only path (model classifies, note comes
from `senseNotes` written by `pipeline/07_notes.py`); `npm run bench:context` compares both.

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

### App

```sh
cd app
flutter pub get
python3 tool/gen_models.py && dart run build_runner build -d   # only after a contracts/ change
flutter test && flutter analyze

# A phone can't reach localhost on the Mac: pass the LAN IP (or set it later in Settings → सर्वर).
flutter run --release -d <device-id> --dart-define=ARTH_API_URL=http://192.168.x.x:3000

# Simulator smoke test: import a PDF automatically and drive the reader over the VM service
flutter run -d <simulator-id> --dart-define=ARTH_API_URL=http://127.0.0.1:3000 \
  --dart-define=ARTH_DEV_PDF_URL=http://127.0.0.1:8765/book.pdf
```

The interface is English by default; **You → Interface language** switches to Hindi. Dictionary
content is always Hindi. Strings live in `app/lib/app/strings.dart`.

Debug builds expose `ext.arth.nav / tapWord / select / dismiss / state` VM-service
extensions (`app/lib/app/dev_hooks.dart`) so the tooltip can be exercised on a
simulator without touch automation. App icon: `python3 tool/make_icon.py`.

### Contracts

`contracts/` is the source of truth for wire types and text normalization. See
`contracts/README.md`. Every language's `normalize()` must pass
`contracts/normalize-vectors.json` — TypeScript (`api/test/normalize.test.ts`) and Python
(`pipeline/tests/test_normalize.py`) do; Dart is added in Phase 4.

## Deploying the API (Render)

`render.yaml` at the repo root is a Blueprint: New → Blueprint in the Render dashboard, pick
this repo, set `MONGODB_URI` and `OPENAI_API_KEY` when prompted. Build is
`cd api && npm ci && npm run build`, start is `cd api && npm start`, health check `/v1/health`.
Production instance: `https://arth-api-x8of.onrender.com`. Point the app at it with
`--dart-define=ARTH_API_URL=https://arth-api-x8of.onrender.com`
or **You → API server** in the app.

## Conventions

- Secrets only in `.env`; `.env.example` is checked in. The app never holds the OpenAI key.
- Every LLM call goes through one `LLMProvider` interface; model names live in config.
- Conventional commits, one scope per phase.
- API: TypeScript strict, Zod on every route, one structured log line per request.

## Attribution

Dictionary data derives from the English Wiktionary via [kaikki.org](https://kaikki.org),
licensed CC BY-SA. Headword frequencies from [`wordfreq`](https://github.com/rspeer/wordfreq) (MIT).
