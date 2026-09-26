import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { ApiError, messages } from '../lib/errors.js';
import { ok } from '../lib/envelope.js';
import { schemas } from '../contracts.js';
import { cacheStats } from '../cache/cache.js';
import { resolveContext, type ContextDeps } from '../services/context.js';
import { openGate, type AiGate } from '../auth/ai-gate.js';

const Body = z.object({
  word: z.string().trim().min(1).max(64),
  sentence: z.string().trim().min(1).max(2000),
  /** Experiment only: force a path regardless of CONTEXT_MODE. */
  mode: z.enum(['live', 'index']).optional(),
});

export type LlmSpend = (request: { headers: Record<string, unknown>; ip: string }) => void;

export const contextRoutes: FastifyPluginAsync<{ deps: ContextDeps; spend: LlmSpend; gate?: AiGate }> = async (app, { deps, spend, gate = openGate }) => {
  app.post(
    '/context',
    {
      schema: {
        response: {
          200: {
            type: 'object',
            required: ['ok', 'data'],
            properties: { ok: { const: true }, data: { $ref: schemas.contextResult['$id'] as string } },
          },
        },
      },
    },
    async (request, reply) => {
      const parsed = Body.safeParse(request.body);
      if (!parsed.success) throw new ApiError('BAD_REQUEST', messages.badRequest);
      const { word, sentence, mode } = parsed.data;
      const use = await gate(request, reply);
      const started = performance.now();
      let outcome;
      try {
        outcome = await resolveContext({ ...deps, spend: () => spend(request) }, word, sentence, mode);
      } catch (err) {
        await use?.refund();
        if (err instanceof ApiError) throw err;
        request.log.error({ err }, 'context failed');
        throw new ApiError('UPSTREAM_FAILED', messages.upstreamFailed, {}, { cause: err });
      }
      // A single-sense word is answered from the dictionary, no AI: free.
      if (!outcome || outcome.cache === 'bypass') await use?.refund();
      if (!outcome) throw new ApiError('NOT_FOUND', messages.wordNotFound, { suggestions: [] });
      if (outcome.cache === 'hit') cacheStats.hits++;
      else if (outcome.cache === 'miss') cacheStats.misses++;
      request.meta.cache = outcome.cache;
      if (request.headers['x-prefetch'] === '1') request.meta.prefetch = true;
      request.meta.tokens = outcome.usage;
      request.meta.context = {
        lemma: outcome.lemma,
        mode: outcome.mode,
        senseIndex: outcome.result.senseIndex,
        clamped: outcome.clamped ?? false,
        llmMs: Math.round(performance.now() - started),
      };
      if (outcome.model) request.meta.model = outcome.model;
      return ok(outcome.result);
    },
  );
};
