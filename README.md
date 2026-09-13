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
- [ ] Phase 2 — pipeline, 500-word slice
- [ ] Phase 3 — `/context`, `/translate`, `/phrases/match`, cache
- [ ] Phase 4 — Flutter app
- [ ] Phase 5 — scale and harden

## Setup

Prereqs: Node ≥ 20.6, Docker (for a local Mongo 7), Flutter 3.x, Python 3.11+.

### API

```sh
cd api
cp .env.example .env          # defaults point at the docker-compose Mongo
docker compose up -d          # Mongo 7 on localhost:27017
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

For Atlas, set `MONGODB_URI` in `.env` to the connection string. Nothing else changes.

### Contracts

`contracts/` is the source of truth for wire types and text normalization. See
`contracts/README.md`. Every language's `normalize()` must pass
`contracts/normalize-vectors.json` — TypeScript does (`api/test/normalize.test.ts`);
Python and Dart are added in their phases.

## Conventions

- Secrets only in `.env`; `.env.example` is checked in. The app never holds the OpenAI key.
- Every LLM call goes through one `LLMProvider` interface; model names live in config.
- Conventional commits, one scope per phase.
- API: TypeScript strict, Zod on every route, one structured log line per request.

## Attribution

Dictionary data derives from the English Wiktionary via [kaikki.org](https://kaikki.org),
licensed CC BY-SA. Headword frequencies from [`wordfreq`](https://github.com/rspeer/wordfreq) (MIT).
