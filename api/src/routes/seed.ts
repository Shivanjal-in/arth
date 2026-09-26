import { createGzip } from 'node:zlib';
import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { ApiError, messages } from '../lib/errors.js';
import { EntryModel, FormModel, PhraseModel, toDictionaryEntry } from '../db/models/index.js';

/**
 * GET /v1/seed?since=<iso>&afterRank=<n>&limit=<n>
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
 * - no params: the whole slice (first launch).
 * - `since`: entries updated after that instant (the daily delta).
 * - `afterRank`: entries ranked after it, up to `maxRank`, and nothing else —
 *   how a phone seeded with a smaller slice catches up when SEED_LIMIT grows.
 *
 * Forms and phrases are small and sent in full, except with `afterRank`.
 */
const Query = z.object({
  since: z.coerce.date().optional(),
  afterRank: z.coerce.number().int().nonnegative().optional(),
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

export type SeedOptions = { defaultLimit?: number | undefined };

export const seedRoutes: FastifyPluginAsync<SeedOptions> = async (app, opts) => {
  app.get('/seed', async (request, reply) => {
    const parsed = Query.safeParse(request.query);
    if (!parsed.success) throw new ApiError('BAD_REQUEST', messages.badRequest);
    const { since, afterRank } = parsed.data;
    const limit = parsed.data.limit ?? opts.defaultLimit ?? 20_000;

    // Where the slice ends: the rank of its last entry (null when the
    // dictionary is smaller than the slice).
    const last = await EntryModel.find({}, { freqRank: 1 }).sort({ freqRank: 1 }).skip(limit - 1).limit(1).lean();
    const maxRank = last[0]?.freqRank ?? null;
    const entryFilter = seedEntryFilter({ since, afterRank, maxRank });
    const withExtras = afterRank === undefined;

    const [entries, forms, phrases] = await Promise.all([
      EntryModel.countDocuments(entryFilter),
      withExtras ? FormModel.countDocuments({ staged: { $ne: true } }) : 0,
      withExtras ? PhraseModel.countDocuments() : 0,
    ]);
    request.meta.seed = { since: since?.toISOString(), entries, forms, phrases };

    // ~55 MB raw for the 20k slice, ~12 MB gzipped. Streamed through zlib so
    // the first lines still arrive immediately; the phone's HTTP client
    // decompresses transparently.
    const gzip = (request.headers['accept-encoding'] ?? '').toString().includes('gzip');
    reply.raw.writeHead(200, {
      'content-type': 'application/x-ndjson; charset=utf-8',
      'cache-control': 'no-store',
      ...(gzip ? { 'content-encoding': 'gzip' } : {}),
    });
    const out = gzip ? createGzip({ level: 6 }) : reply.raw;
    if (gzip) (out as import('node:stream').Transform).pipe(reply.raw);
    const write = (obj: unknown) => out.write(JSON.stringify(obj) + '\n');

    // `maxRank` when the whole dictionary fits: the last entry's rank.
    const topRank = maxRank ?? (await EntryModel.findOne({}, { freqRank: 1 }).sort({ freqRank: -1 }).lean())?.freqRank ?? 0;
    write({ t: 'meta', asOf: new Date().toISOString(), entries, forms, phrases, limit, maxRank: topRank });

    const entryCursor = EntryModel.find(entryFilter).sort({ freqRank: 1 }).lean().cursor();
    for await (const doc of entryCursor) {
      write({ t: 'entry', word: doc._id, freqRank: doc.freqRank, entry: toDictionaryEntry(doc) });
    }
    if (withExtras) {
      for await (const doc of FormModel.find({ staged: { $ne: true } }).lean().cursor()) {
        write({ t: 'form', form: doc._id, lemma: doc.lemma });
      }
      for await (const doc of PhraseModel.find().lean().cursor()) {
        write({ t: 'phrase', phrase: doc._id, lemma: doc.lemma, firstToken: doc.firstToken, tokenCount: doc.tokenCount });
      }
    }
    write({ t: 'end' });
    out.end();
    return reply;
  });
};
