import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { ApiError, messages } from '../lib/errors.js';
import { ok } from '../lib/envelope.js';
import { schemas } from '../contracts.js';
import { resolveLemma, type LemmaStore } from '../services/lemma.js';

const Query = z.object({
  word: z.string().trim().min(1).max(64),
});

export type LookupOptions = { store: LemmaStore };

export const lookupRoutes: FastifyPluginAsync<LookupOptions> = async (app, { store }) => {
  app.get(
    '/lookup',
    {
      schema: {
        response: {
          200: {
            type: 'object',
            required: ['ok', 'data'],
            properties: { ok: { const: true }, data: { $ref: schemas.dictionaryEntry['$id'] as string } },
          },
        },
      },
    },
    async (request) => {
      const parsed = Query.safeParse(request.query);
      if (!parsed.success) throw new ApiError('BAD_REQUEST', messages.badRequest);

      const { word } = parsed.data;
      const resolved = await resolveLemma(store, word);
      if (!resolved) {
        request.meta.lookup = { word, via: 'miss' };
        // `suggestions` is always [] from the server: the app computes them locally by Levenshtein.
        throw new ApiError('NOT_FOUND', messages.wordNotFound, { suggestions: [] });
      }
      request.meta.lookup = { word, lemma: resolved.lemma, via: resolved.via };
      return ok(resolved.entry);
    },
  );
};
