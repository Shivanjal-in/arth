# Arth

A mobile PDF/EPUB reader for Hindi-speaking readers of English books. Tap a word or select
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

# Simulator smoke test: import a PDF (or .epub) automatically and drive the reader over the VM service.
# The iOS simulator can't link ML Kit; use an Android emulator (host is 10.0.2.2 there).
flutter run -d <emulator-id> --dart-define=ARTH_API_URL=http://10.0.2.2:3000 \
  --dart-define=ARTH_DEV_PDF_URL=http://10.0.2.2:8765/book.pdf
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

## EPUBs

Library → **+** → *Add a PDF or EPUB*. An EPUB is opened in place from the zip
(`app/lib/core/epub/epub_book.dart`: container → OPF spine → EPUB 3 nav or NCX table of
contents), and each chapter's XHTML is parsed off the main isolate into text blocks
(`epub_html.dart`: paragraphs, headings, quotes, lists, `pre`; emphasis kept, images dropped).
`EpubReaderScreen` lays the blocks out as a scrolling column, one chapter per swipe, painting
each block with its own `TextPainter` (`epub_paragraph.dart`) so the word rects handed to the
tooltip are exactly where the glyphs are; a block is the unit for `PageTextIndex`, so sentences
never cross a paragraph. The Contents sheet jumps by title; `lastPage` is the chapter and the
scroll offset is kept in the kv table. Same tooltip layer, `/context` and `/translate` as the PDF
reader; no drag selection (the word card's translate action handles the sentence) and no prefetch.

## Highlighter

Four colours, saved per book in the `highlights` table (`app/lib/data/local_store.dart`, schema
v3) as `(page, block?, startWord, endWord)` — word indices in the page's (PDF) or block's (EPUB)
`PageTextIndex`, which are deterministic for a given file — plus the text for the list. Shared
pieces live in `app/lib/features/reader/highlights/`: the palette, the colour bar, and the
per-book Highlights sheet (reader ⋮ menu → Highlights: jump to a highlight, remove one).

- **EPUB**: press and hold a word and drag to extend within the paragraph; release for the
  colour bar (translate is there too). Long-press an existing highlight to recolour or remove
  it. Bands are painted by the block's render object under the text.
- **PDF**: select text (pdfrx's long-press selection); the translation card gets a *Highlight*
  colour row. The selection is mapped to word indices by matching its first and last tokens
  near pdfrx's character offsets; bands are drawn in the viewer overlay from rects resolved
  for pages near the current one.
- The word card's translate action also offers the colour row for that sentence.
- Not on scans: OCR word positions aren't stable enough to anchor to.

## Photographed pages (scan reader)

Library → **+** → *Take a photo of a page* / *Choose a photo from gallery*. The photo is OCR'd on
the device with Google ML Kit (Latin script, offline; `app/lib/data/ocr_service.dart`, result
cached beside the image), indexed with `PageTextIndex.fromLines`, and shown in
`ScanReaderScreen` with the same tooltip layer as the PDF reader
(`app/lib/features/reader/tooltip/tooltip_layer.dart`). Tap a word; the word card's translate
action handles the sentence. A scan is a book of pages under `Documents/scans/<id>/`; *Add a
page* from the reader's app bar. iOS deployment target is 15.5 (ML Kit). ML Kit's iOS pods have
no Apple-Silicon simulator slice — test scans on a device.

## Expanding the dictionary on demand

`pipeline/08_stage.py` stages Wiktionary senses (English only) for ~90k lemmas beyond the
generated 23k — the whole `wordfreq` list plus every attested Wiktionary headword — into the
`wiktionary` collection. When `/v1/lookup` misses `entries` but the lemma is staged, the API
generates its Hindi layer live with the pipeline's prompt and validation, stores it in
`entries` for good and returns it (3–7 s the first time, instant after). A word that isn't
staged either gets a 404 whose `suggestions` are morphological bases (`brimlessness` →
`brimless`, `brim`). Generation spends the per-device LLM budget like any model call.

## Flashcards, bookmarks, progress

Cards are made while reading — *Make card* on the word card (word + its meaning in this
sentence) or the translation card (quote + translation), or ⋮ → *Add a note card* for the
reader's own idea — and remember where in the book they came from. The **Cards** tab has a deck
per book; a deck is a **recap**: its cards as a timeline in reading order, grouped by chapter,
with *Replay the book* (every card, in order) and *Practice* (due first, flip, rate; Leitner
boxes in `app/lib/features/cards/review_schedule.dart`). Finishing a book (97%) offers its recap.

The reader's ribbon bookmarks the current page (EPUB: the first paragraph on screen, which
survives font-size changes); ⋮ → *Bookmarks* lists them. `books.progress` is a 0–1 fraction —
for EPUBs it counts the scroll position within the chapter — and drives the library's
*Continue reading* card and per-book percentages. Tables: `flashcards`, `bookmarks` (schema v4+).

## Accounts and sync

Sign in (You tab) with Google or a phone number + SMS code, via Firebase Auth. The API accepts
the Firebase ID token as `Authorization: Bearer …`, creates the user on first sight (`users`
collection: profile, `role` user/admin, `tier` free/pro/super) and serves `GET/PATCH /v1/me`,
`POST /v1/me/avatar` (a signed Cloudinary upload ticket — the photo goes straight from the phone
to Cloudinary, the secret stays on the server) and `POST /v1/sync`.

Sync covers flashcards and bookmarks: rows carry UUIDs, `updatedAt` and tombstones; the newer
`updatedAt` wins; every accepted write takes the user's next sequence number and a device pulls
"everything after the sequence I last saw" (`api/src/services/accounts.ts`). A book is
identified across devices by a content key — SHA-256 of its size and first MiB
(`app/lib/core/book_key.dart`) — so a synced card attaches to the same book on another phone, even
one imported later. The app syncs on sign-in, on resume, a few seconds after an edit, and from
*Sync now*. On first sign-in, what's already on the phone joins the account.

Setup (accounts stay hidden until this is done):

1. Firebase console → create a project; enable **Authentication → Google** and **Phone**.
   Add an Android app (`com.zethyst.arth`, with the debug and release SHA-1/SHA-256 —
   `cd app/android && ./gradlew signingReport`) and an iOS app (`com.zethyst.arth`).
2. API: set `FIREBASE_PROJECT_ID` (and `CLOUDINARY_URL` for photos) in `api/.env` / Render.
3. App: pass the Firebase values as dart-defines (see `app/lib/app/firebase_setup.dart`), e.g.
   `flutter run --dart-define-from-file=firebase.json` (copy `app/firebase.json.example`) with the project's API keys, sender id,
   Android/iOS app ids, the iOS OAuth client id and the **Web** OAuth client id (Android's
   Google sign-in needs it to get an ID token).
4. iOS: copy `app/ios/Flutter/Firebase.xcconfig.example` to `Firebase.xcconfig` and fill in the
   reversed client id and encoded app id (URL schemes for the sign-in callbacks). Phone sign-in
   on a real iPhone also wants an APNs key uploaded to Firebase (else it falls back to reCAPTCHA).

## Tiers, AI allowance, ads

| Tier  | AI answers                     | Ads                  |
|-------|--------------------------------|----------------------|
| Free  | 100, lifetime                  | banners outside the reader |
| Pro   | 1,000 per calendar month (UTC) | none                 |
| Super | unlimited                      | none                 |

Only AI answers count: `/context` (meaning in this sentence), `/translate`, and a dictionary
entry generated live by `/lookup`. The on-device dictionary is always free. When accounts are on
(`FIREBASE_PROJECT_ID` set), those routes need sign-in; a use is reserved atomically before the
work and refunded when no AI answer was served (single-sense words, failures). Background
prefetch is free but only while allowance remains. Responses carry `x-ai-used` / `x-ai-limit` /
`x-ai-period`; `402 QUOTA_EXCEEDED` includes the usage. Limits: `AI_FREE_LIMIT`,
`AI_PRO_MONTHLY` (`api/src/services/quota.ts`). Without a Firebase project nothing is enforced.

Tiers are set by hand until there are payments and an admin screen:

```sh
cd api && npm run set-tier -- reader@example.com pro      # or a uid / phone; add --admin for the admin role
```

In the app, a signed-out or out-of-allowance reader sees *Sign in* / *See plans* where the AI
answer would be (`app/lib/features/plans/`); the You tab shows what's left. **Plans** compares
the tiers; *Ask for an upgrade* emails `ARTH_SUPPORT_EMAIL` (dart-define).

Ads (`app/lib/features/ads/ads.dart`): Google Mobile Ads, a banner above the tab bar on Library,
Dictionary and Cards for free/signed-out readers, never in a reader. Google's UMP consent form
runs first where the law requires it; content is capped at PG. Without configuration Google's
**test** units serve (safe to tap). For real ads:

- Full-screen interstitials (`app/lib/features/ads/interstitials.dart`), free tier only, at natural
  breaks: leaving a book read for 2+ minutes, finishing a Replay/Practice session. Never in the
  first 2 minutes after launch, at most one per 6 minutes (`AdPacing`); one is kept preloaded.
- Ad units: `--dart-define=ADMOB_BANNER_ANDROID=…` / `ADMOB_BANNER_IOS=…`,
  `ADMOB_INTERSTITIAL_ANDROID=…` / `ADMOB_INTERSTITIAL_IOS=…`
- App id: Android `ADMOB_APP_ID=…` in `android/key.properties`; iOS `ADMOB_APP_ID = …` in
  `ios/Flutter/Firebase.xcconfig` (overrides the test id in `AdMob.xcconfig`).
- Play Console: declare that the app contains ads; App Store: the privacy label.

## Analytics

Mixpanel (`app/lib/data/analytics.dart`). Never book titles, words or sentences. Events:

| Event | Properties |
|---|---|
| `Screen Viewed` | `screen` (route pattern, e.g. `/word/:lemma`) |
| `Book Added` / `Book Opened` | `format` (pdf, epub, scan) |
| `Word Looked Up` | `from` (reader, dictionary), `found`, `source` (local, api), `phrase` |
| `AI Lookup` | `kind` (word, sentence) |
| `AI Blocked` | `kind`, `reason` (UNAUTHORIZED, QUOTA_EXCEEDED, QUOTA_PHONE) |
| `Card Created` | `kind`, `from_book` |
| `Deck Saved` | `cards` |
| `Plan Purchase` | `plan`, `yearly`, `outcome` |

Every event carries `plan` and `language`. Signed-in readers are identified by Firebase uid.
Readers can opt out in Settings → Share usage stats. The project token is built in; debug builds
send nothing unless `--dart-define=MIXPANEL_DEBUG=true`. Data residency:
`--dart-define=MIXPANEL_SERVER_URL=https://api-eu.mixpanel.com` (or `api-in`).

- Play Console → Data safety, for **Analytics** (collected, not shared, optional, not ephemeral):
  *Personal info → User IDs*, *Financial info → Purchase history*, *App activity → App
  interactions*, *Device or other IDs*. Where a type is already declared (e.g. User IDs for
  accounts), add the Analytics purpose to it.

## Push notifications

Firebase Cloud Messaging. What sends one (`api/src/push/notify.ts`), each in the phone's own
interface language, to every phone the reader is signed in on:

| When | Message | Opens |
|---|---|---|
| Cards are due (daily cron, at most once a day) | "5 cards are ready — most from “Emma”" | Cards |
| An admin changes their plan (`npm run set-tier`) | "You're on Pro now ✨" | Plans |
| 10 free AI answers left (or 50 of a Pro month), once | "10 AI answers left" | Plans |
| The reader taps *Send a test notification* (Profile) | "Notifications are working" | You |

The app registers its token only after sign-in is restored (`app/lib/data/push_service.dart`),
again when FCM rotates it or the language changes, and removes it on sign-out; the API keeps up
to ten phones per user and drops tokens FCM reports dead. While the app is open Android shows
the banner itself (a local notification), iOS presents its own. *Review reminders* can be turned
off in Profile.

Setup: `FIREBASE_SERVICE_ACCOUNT` (Firebase → Project settings → Service accounts → Generate new
private key; the JSON, or base64 of it) in `api/.env`, on Render's `arth-api`, and on the
`arth-review-reminders` cron job (in `render.yaml`, 13:00 UTC daily). iOS also needs the APNs key
uploaded to Firebase (setup guide §4) and a real device: the simulator can't receive pushes.

```sh
cd api && npm run review-reminders          # send today's reminders now
```

## Android release builds

Signing uses `app/android/key.properties` and `app/android/upload-keystore.jks` — both
gitignored, **back them up**: an app signed with a different key cannot update an
installed one. Without them the release build silently signs with the debug key.

```sh
cd app
flutter build apk --release --split-per-abi --dart-define=ARTH_API_URL=https://arth-api-epja.onrender.com   # sideload: app-arm64-v8a-release.apk
flutter build appbundle --release        --dart-define=ARTH_API_URL=https://arth-api-epja.onrender.com   # Play Store
```

R8 shrinking is on; keep rules live in `app/android/app/proguard-rules.pro`.

## Deploying the API (Render)

`render.yaml` at the repo root is a Blueprint: New → Blueprint in the Render dashboard, pick
this repo, set `MONGODB_URI` and `OPENAI_API_KEY` when prompted. Build is
`cd api && npm ci && npm run build`, start is `cd api && npm start`, health check `/v1/health`.
Production instance: `https://arth-api-epja.onrender.com`. Point the app at it with
`--dart-define=ARTH_API_URL=https://arth-api-epja.onrender.com`
or **You → API server** in the app.

## Conventions

- Secrets only in `.env`; `.env.example` is checked in. The app never holds the OpenAI key.
- Every LLM call goes through one `LLMProvider` interface; model names live in config.
- Conventional commits, one scope per phase.
- API: TypeScript strict, Zod on every route, one structured log line per request.

## Attribution

Dictionary data derives from the English Wiktionary via [kaikki.org](https://kaikki.org),
licensed CC BY-SA. Headword frequencies from [`wordfreq`](https://github.com/rspeer/wordfreq) (MIT).
