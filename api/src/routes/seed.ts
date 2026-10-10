import { once } from 'node:events';
import type { Writable } from 'node:stream';
import { createGzip } from 'node:zlib';
import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { ApiError, messages } from '../lib/errors.js';
import { EntryModel, FormModel, PhraseModel, toDictionaryEntry } from '../db/models/index.js';
import { parseRange, type SeedFileCache, type SeedSource } from '../services/seed-file.js';

/**
 * GET /v1/seed?since=<iso>&afterRank=<n>&extras=1&limit=<n>
 *
 * Streams the on-device dictionary as NDJSON (one JSON object per line) so the
 * app can insert while downloading and show progress:
 *
 *   {"t":"meta","asOf":"…","entries":N,"forms":N,"phrases":N,"limit":N,"maxRank":N}
 *   {"t":"entry","word":"fortune","freqRank":1840,"entry":{…DictionaryEntry}}
 *   {"t":"form","form":"wives","lemma":"wife"}
 *   {"t":"phrase","phrase":"in want of","lemma":"in want of","firstToken":"in","tokenCount":3}
 *   {"t":"end"}
 *
 * The on-device slice is the `limit` most frequent entries (SEED_LIMIT,
 * 20000 by default); `maxRank` is the freqRank where it ends. Everything
 * sent stays inside that slice.
 *
 * - no params: the whole slice (first launch). Phones fetch this from
 *   /v1/seed/file instead when the server has one.
 * - `since`: entries updated after that instant (the daily delta).
 * - `afterRank`: entries ranked after it, up to `maxRank`, and nothing else —
 *   how a phone seeded with a smaller slice catches up when SEED_LIMIT grows,
 *   and how a dropped download resumes.
 * - `extras=1`: forms and phrases too, even with `afterRank` (a resumed
 *   download still needs them).
 *
 * Forms and phrases are small and sent in full, except with `afterRank`.
 *
 * GET /v1/seed/file
 *
 * The no-params stream, built ahead and served as a gzipped file
 * (application/gzip) with a length, an ETag and Range support, so a dropped
 * download resumes where it stopped (`Range` + `If-Range`). 404 when this
 * server has no file (tests); the phone then falls back to the stream.
 */
const Query = z.object({
  since: z.coerce.date().optional(),
  afterRank: z.coerce.number().int().nonnegative().optional(),
  extras: z.enum(['0', '1']).optional(),
  limit: z.coerce.number().int().positive().max(100_000).optional(),
});

/** The Mongo filter for the entries to send. */
export function seedEntryFilter(q: { since?: Date | undefined; afterRank?: number | undefined; maxRank: number | null }) {
  const rank: Record<string, number> = {};
  if (q.maxRank !== null) rank.$lte = q.maxRank;
  if (q.afterRank !== undefined) rank.$gt = q.afterRank;
  return {
    ...(q.since ? { updatedAt: { $gt: q.since } } : {}),
    ...(Object.keys(rank).length > 0 ? { freqRank: rank } : {}),
  };
}

/** Atlas round trips are the cost; the default (101 docs) makes ~650 of them. */
const BATCH = 1000;

/** Where the slice ends: the rank of its last entry (null when the dictionary is smaller than the slice). */
async function sliceEnd(limit: number): Promise<number | null> {
  const last = await EntryModel.find({}, { freqRank: 1 }).sort({ freqRank: 1 }).skip(limit - 1).limit(1).lean();
  return last[0]?.freqRank ?? null;
}

type SeedQuery = {
  since?: Date | undefined;
  afterRank?: number | undefined;
  extras?: boolean;
  limit: number;
  /** The meta line's asOf; now when omitted. */
  asOf?: Date;
};

/**
 * The newest change inside the slice, walked off the updatedAt index; while
 * that index is still being built, the plain query.
 */
async function newestChange(maxRank: number | null): Promise<Date | null> {
  const newest = () => EntryModel.findOne(seedEntryFilter({ maxRank }), { updatedAt: 1 }).sort({ updatedAt: -1 });
  const doc = await newest().hint({ updatedAt: -1 }).lean().catch(() => newest().lean());
  return doc?.updatedAt ?? null;
}

/**
 * Everything a /seed response holds, in order: the meta line, then entries,
 * forms and phrases. Ordered by unique keys, so the same data always makes
 * the same lines (and the same file).
 */
export async function* seedLines(q: SeedQuery, onMeta?: (meta: { entries: number; forms: number; phrases: number }) => void): AsyncGenerator<object> {
  const maxRank = await sliceEnd(q.limit);
  const entryFilter = seedEntryFilter({ since: q.since, afterRank: q.afterRank, maxRank });
  const withExtras = q.afterRank === undefined || q.extras === true;
  const formFilter = { staged: { $ne: true } };

  const [entries, forms, phrases] = await Promise.all([
    EntryModel.countDocuments(entryFilter),
    withExtras ? FormModel.countDocuments(formFilter) : 0,
    withExtras ? PhraseModel.countDocuments() : 0,
  ]);
  onMeta?.({ entries, forms, phrases });

  // `maxRank` when the whole dictionary fits: the last entry's rank.
  const topRank = maxRank ?? (await EntryModel.findOne({}, { freqRank: 1 }).sort({ freqRank: -1 }).lean())?.freqRank ?? 0;
  yield { t: 'meta', asOf: (q.asOf ?? new Date()).toISOString(), entries, forms, phrases, limit: q.limit, maxRank: topRank };

  for await (const doc of EntryModel.find(entryFilter).sort({ freqRank: 1, _id: 1 }).lean().batchSize(BATCH).cursor()) {
    yield { t: 'entry', word: doc._id, freqRank: doc.freqRank, entry: toDictionaryEntry(doc) };
  }
  if (withExtras) {
    for await (const doc of FormModel.find(formFilter).sort({ _id: 1 }).lean().batchSize(BATCH).cursor()) {
      yield { t: 'form', form: doc._id, lemma: doc.lemma };
    }
    for await (const doc of PhraseModel.find().sort({ _id: 1 }).lean().batchSize(BATCH).cursor()) {
      yield { t: 'phrase', phrase: doc._id, lemma: doc.lemma, firstToken: doc.firstToken, tokenCount: doc.tokenCount };
    }
  }
  yield { t: 'end' };
}

/** The full seed out of Mongo, for SeedFileCache. */
export function mongoSeedSource(limit: number): SeedSource {
  return {
    async version() {
      const maxRank = await sliceEnd(limit);
      const [latest, entries, forms, phrases] = await Promise.all([
        newestChange(maxRank),
        EntryModel.countDocuments(seedEntryFilter({ maxRank })),
        FormModel.countDocuments({ staged: { $ne: true } }),
        PhraseModel.countDocuments(),
      ]);
      return [limit, maxRank, entries, latest?.getTime() ?? 0, forms, phrases].join(':');
    },
    async *lines() {
      // asOf is the newest change rather than the build time, so the same
      // dictionary makes the same bytes (and ETag) after a restart or on
      // another instance, and a phone's resume survives a deploy. Anything
      // changed after it is newer, so the phone's next delta still finds it.
      const asOf = (await newestChange(await sliceEnd(limit))) ?? new Date(0);
      for await (const obj of seedLines({ limit, asOf })) yield JSON.stringify(obj);
    },
  };
}

export type SeedOptions = {
  defaultLimit?: number | undefined;
  /** The prebuilt full seed; without it /seed/file is a 404. */
  file?: SeedFileCache | undefined;
};

export const seedRoutes: FastifyPluginAsync<SeedOptions> = async (app, opts) => {
  app.get('/seed', async (request, reply) => {
    const parsed = Query.safeParse(request.query);
    if (!parsed.success) throw new ApiError('BAD_REQUEST', messages.badRequest);
    const { since, afterRank } = parsed.data;
    const limit = parsed.data.limit ?? opts.defaultLimit ?? 20_000;

    const lines = seedLines({ since, afterRank, extras: parsed.data.extras === '1', limit }, (counts) => {
      request.meta.seed = { since: since?.toISOString(), ...counts };
    });
    // Pull the meta line before the headers go out, so a Mongo failure is
    // still an ordinary error response.
    const first = await lines.next();

    // ~55 MB raw for the 20k slice, ~12 MB gzipped. Streamed through zlib so
    // the first lines still arrive immediately; the phone's HTTP client
    // decompresses transparently.
    const gzip = (request.headers['accept-encoding'] ?? '').toString().includes('gzip');
    reply.raw.writeHead(200, {
      'content-type': 'application/x-ndjson; charset=utf-8',
      'cache-control': 'no-store',
      ...(gzip ? { 'content-encoding': 'gzip' } : {}),
    });
    const out: Writable = gzip ? createGzip({ level: 6 }) : reply.raw;
    if (gzip) out.pipe(reply.raw);

    // A phone that hangs up stops the Mongo reads too.
    let gone = false;
    const hangUp = new AbortController();
    reply.raw.once('close', () => {
      gone = true;
      hangUp.abort();
      out.destroy();
    });
    // Waits when the phone reads slower than Mongo, instead of buffering the
    // whole seed in memory.
    const write = async (obj: unknown) => {
      if (!out.write(JSON.stringify(obj) + '\n')) await once(out, 'drain', { signal: hangUp.signal });
    };

    try {
      if (!first.done) await write(first.value);
      for await (const obj of lines) {
        if (gone) break;
        await write(obj);
      }
      if (!gone) out.end();
    } catch (err) {
      // Mid-stream: too late for an error response. Cut the stream short;
      // the phone sees no {"t":"end"} and resumes.
      if (!gone) request.log.warn({ err }, 'seed stream failed');
      reply.raw.destroy();
    }
    return reply;
  });

  app.get('/seed/file', async (request, reply) => {
    if (!opts.file) throw new ApiError('NOT_FOUND', messages.seedFileUnavailable);
    const file = await opts.file.current();
    const size = file.body.length;
    reply
      .header('content-type', 'application/gzip')
      .header('etag', file.etag)
      .header('accept-ranges', 'bytes')
      // Always ask: a rebuilt file has a new ETag.
      .header('cache-control', 'no-cache');

    // A resume only gets the rest of the file it started on.
    const ifRange = request.headers['if-range'];
    const range = ifRange === undefined || ifRange === file.etag ? parseRange(request.headers.range, size) : null;
    if (range === 'unsatisfiable') {
      return reply.status(416).header('content-range', `bytes */${size}`).send();
    }
    if (range) {
      return reply
        .status(206)
        .header('content-range', `bytes ${range.start}-${range.end}/${size}`)
        .send(file.body.subarray(range.start, range.end + 1));
    }
    return reply.send(file.body);
  });
};
