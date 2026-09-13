import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { ApiError, messages } from '../lib/errors.js';
import { EntryModel, FormModel, PhraseModel, toDictionaryEntry } from '../db/models/index.js';

/**
 * GET /v1/seed?since=<iso>&limit=<n>
 *
 * Streams the on-device dictionary as NDJSON (one JSON object per line) so the
 * app can insert while downloading and show progress:
 *
 *   {"t":"meta","asOf":"…","entries":N,"forms":N,"phrases":N}
 *   {"t":"entry","word":"fortune","freqRank":1840,"entry":{…DictionaryEntry}}
 *   {"t":"form","form":"wives","lemma":"wife"}
 *   {"t":"phrase","phrase":"in want of","lemma":"in want of","firstToken":"in","tokenCount":3}
 *   {"t":"end"}
 *
 * `since` restricts entries to those updated after that instant (delta sync);
 * forms and phrases are always sent in full — they're small. `limit` caps the
 * number of entries by freqRank (default 20000, the on-device slice).
 */
const Query = z.object({
  since: z.coerce.date().optional(),
  limit: z.coerce.number().int().positive().max(100_000).default(20_000),
});

export const seedRoutes: FastifyPluginAsync = async (app) => {
  app.get('/seed', async (request, reply) => {
    const parsed = Query.safeParse(request.query);
    if (!parsed.success) throw new ApiError('BAD_REQUEST', messages.badRequest);
    const { since, limit } = parsed.data;

    const entryFilter = since ? { updatedAt: { $gt: since } } : {};
    const [entries, forms, phrases] = await Promise.all([
      EntryModel.countDocuments(entryFilter).then((n) => Math.min(n, limit)),
      FormModel.countDocuments(),
      PhraseModel.countDocuments(),
    ]);
    request.meta.seed = { since: since?.toISOString(), entries, forms, phrases };

    reply.raw.writeHead(200, {
      'content-type': 'application/x-ndjson; charset=utf-8',
      'cache-control': 'no-store',
    });
    const write = (obj: unknown) => reply.raw.write(JSON.stringify(obj) + '\n');

    write({ t: 'meta', asOf: new Date().toISOString(), entries, forms, phrases });

    const entryCursor = EntryModel.find(entryFilter).sort({ freqRank: 1 }).limit(limit).lean().cursor();
    for await (const doc of entryCursor) {
      write({ t: 'entry', word: doc._id, freqRank: doc.freqRank, entry: toDictionaryEntry(doc) });
    }
    for await (const doc of FormModel.find().lean().cursor()) {
      write({ t: 'form', form: doc._id, lemma: doc.lemma });
    }
    for await (const doc of PhraseModel.find().lean().cursor()) {
      write({ t: 'phrase', phrase: doc._id, lemma: doc.lemma, firstToken: doc.firstToken, tokenCount: doc.tokenCount });
    }
    write({ t: 'end' });
    reply.raw.end();
    return reply;
  });
};
