import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { ApiError, messages } from '../lib/errors.js';
import { ok } from '../lib/envelope.js';
import { schemas } from '../contracts.js';
import { resolveLemma, resolveLemmaKey } from '../services/lemma.js';
import { generateOnDemand, morphologySuggestions, type OnDemandDeps } from '../services/ondemand.js';
import type { Store } from '../services/mongo-store.js';
import { cacheStats } from '../cache/cache.js';
import { openGate, type AiGate } from '../auth/ai-gate.js';

const Query = z.object({
  word: z.string().trim().min(1).max(64),
});

export type LookupOptions = {
  store: Store;
  /** Absent in tests that don't exercise generation. */
  ondemand?: Omit<OnDemandDeps, 'staging' | 'spend'> & {
    spend: (request: { headers: Record<string, unknown>; ip: string }) => void;
  };
  /** Generating an entry is an AI use; looking up an existing one isn't. */
  gate?: AiGate;
};

export const lookupRoutes: FastifyPluginAsync<LookupOptions> = async (app, { store, ondemand, gate = openGate }) => {
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
    async (request, reply) => {
      const parsed = Query.safeParse(request.query);
      if (!parsed.success) throw new ApiError('BAD_REQUEST', messages.badRequest);

      const { word } = parsed.data;
      const resolved = await resolveLemma(store, word);
      if (resolved) {
        request.meta.lookup = { word, lemma: resolved.lemma, via: resolved.via };
        return ok(resolved.entry);
      }

      // Not generated yet: a staged Wiktionary lemma gets its Hindi layer now.
      if (ondemand) {
        const stagedLemma = await resolveLemmaKey(
          async (k) => (await store.findStaged(k)) !== null,
          (f) => store.findFormLemma(f),
          word,
        );
        if (stagedLemma) {
          const use = await gate(request, reply);
          try {
            const out = await generateOnDemand({ ...ondemand, staging: store, spend: () => ondemand.spend(request) }, stagedLemma);
            if (!out) await use?.refund();
            if (out) {
              cacheStats.misses++;
              request.meta.lookup = { word, lemma: stagedLemma, via: 'generated' };
              request.meta.tokens = out.usage;
              request.meta.model = out.model;
              return ok(out.entry);
            }
          } catch (err) {
            await use?.refund();
            if (err instanceof ApiError) throw err;
            request.log.error({ err, lemma: stagedLemma }, 'ondemand generation failed');
          }
        }
      }

      // Genuinely unknown (or generation failed): offer bases the reader can open.
      const key = word.toLowerCase();
      const exists = async (c: string) =>
        (await resolveLemma(store, c)) !== null || (await store.findStaged(c)) !== null;
      const suggestions = await morphologySuggestions(key, exists);
      request.meta.lookup = { word, via: 'miss' };
      throw new ApiError('NOT_FOUND', messages.wordNotFound, { suggestions });
    },
  );
};
