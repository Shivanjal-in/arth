import Fastify, { LogController, type FastifyInstance, type FastifyRequest } from 'fastify';
import { ApiError, messages } from './lib/errors.js';
import { fail } from './lib/envelope.js';
import { schemas } from './contracts.js';
import { contextRoutes } from './routes/context.js';
import { healthRoutes } from './routes/health.js';
import { lookupRoutes } from './routes/lookup.js';
import { phraseRoutes } from './routes/phrases.js';
import { seedRoutes } from './routes/seed.js';
import { translateRoutes } from './routes/translate.js';
import type { CacheStore } from './cache/cache.js';
import type { Config } from './config.js';
import rateLimit from '@fastify/rate-limit';
import { LlmBudget } from './lib/budget.js';
import type { LLMProvider } from './llm/provider.js';
import type { Store } from './services/mongo-store.js';

/** Per-request facts that end up on the one structured log line per request. */
export type RequestMeta = {
  lookup?: { word: string; lemma?: string; via: string };
  seed?: { since: string | undefined; entries: number; forms: number; phrases: number };
  cache?: 'hit' | 'miss' | 'bypass';
  tokens?: { input: number; output: number; cachedInput?: number };
  model?: string;
  phrase?: string;
  context?: { lemma: string; mode: string; senseIndex: number; clamped: boolean; llmMs: number };
  prefetch?: boolean;
  translate?: { chars: number; retried: boolean };
};

declare module 'fastify' {
  interface FastifyRequest {
    meta: RequestMeta;
  }
}

export type AppOptions = {
  logLevel?: string;
  store: Store;
  cache: CacheStore;
  llm: LLMProvider;
  rateLimits?: { lookups: number; llm: number; prefetch: number };
  config: Pick<
    Config,
    | 'CONTEXT_MODE'
    | 'LLM_CONTEXT_MODEL'
    | 'LLM_CONTEXT_INDEX_MODEL'
    | 'LLM_TRANSLATE_MODEL'
    | 'LLM_TEMPERATURE'
    | 'LLM_CONTEXT_MAX_TOKENS'
    | 'LLM_TRANSLATE_MAX_TOKENS'
  >;
};

export function buildApp(opts: AppOptions): FastifyInstance {
  const app = Fastify({
    logger: { level: opts.logLevel ?? 'info' },
    trustProxy: true, // Render / any load balancer: req.ip must be the client for the IP fallback

    // We emit our own single line per request in onResponse.
    logController: new LogController({ disableRequestLogging: true }),
  });

  // Fastify forbids sharing one object across requests via decorateRequest,
  // so back the getter with a WeakMap keyed by the request.
  const metas = new WeakMap<FastifyRequest, RequestMeta>();
  app.decorateRequest('meta', {
    getter(this: FastifyRequest) {
      let m = metas.get(this);
      if (!m) {
        m = {};
        metas.set(this, m);
      }
      return m;
    },
  });

  app.addHook('onResponse', async (request, reply) => {
    request.log.info(
      {
        method: request.method,
        url: request.url,
        status: reply.statusCode,
        ms: Math.round(reply.elapsedTime),
        ...request.meta,
      },
      'request',
    );
  });

  // Register the contract schemas by $id so routes can $ref them in response
  // schemas (which also makes the serializer strip storage-only fields).
  for (const s of Object.values(schemas)) app.addSchema(s);

  app.setNotFoundHandler(async (_request, reply) => {
    return reply.status(404).send(fail('NOT_FOUND', messages.wordNotFound));
  });

  app.setErrorHandler(async (error, request, reply) => {
    if (error instanceof ApiError) {
      return reply.status(error.status).send(fail(error.code, error.message, error.extra));
    }
    // Fastify's own validation / serialization errors carry a statusCode.
    const status = typeof (error as { statusCode?: number }).statusCode === 'number'
      ? (error as { statusCode: number }).statusCode
      : 500;
    if (status >= 500) request.log.error({ err: error }, 'unhandled error');
    return reply.status(status).send(fail(status >= 500 ? 'INTERNAL' : 'BAD_REQUEST', status >= 500 ? messages.internal : messages.badRequest));
  });

  // Per-device limits (Section 6). The app sends X-Device-Id; without it we
  // fall back to the IP. Two buckets: cheap DB reads, and LLM calls.
  const limits = opts.rateLimits ?? { lookups: 60, llm: 20, prefetch: 40 };
  const deviceKey = (req: FastifyRequest) => (req.headers['x-device-id'] as string | undefined)?.slice(0, 64) || req.ip;
  const limited = (max: number, message: string, keyGenerator: (req: FastifyRequest) => string) => ({
    max,
    timeWindow: '1 minute',
    keyGenerator,
    errorResponseBuilder: () => new ApiError('RATE_LIMITED', message),
  });

  app.register(
    async (v1) => {
      await v1.register(rateLimit, { global: false });
      await v1.register(healthRoutes);
      await v1.register(async (dbRoutes) => {
        dbRoutes.addHook('preHandler', dbRoutes.rateLimit(limited(limits.lookups, messages.rateLimited, deviceKey)));
        await dbRoutes.register(lookupRoutes, { store: opts.store });
        await dbRoutes.register(phraseRoutes, { store: opts.store });
      });
      await v1.register(seedRoutes);
      const log = { warn: (obj: object, msg: string) => app.log.warn(obj, msg) };
      // Model calls are budgeted per device and spent only on a cache miss
      // (see services): cache hits and single-sense bypasses are free.
      // Interactive taps and background prefetch have separate budgets, so a
      // reader flipping pages never finds their own tap refused.
      const interactive = new LlmBudget(limits.llm);
      const prefetch = new LlmBudget(limits.prefetch);
      const spend = (req: { headers: Record<string, unknown>; ip: string }) => {
        const key = (req.headers['x-device-id'] as string | undefined)?.slice(0, 64) || req.ip;
        const budget = req.headers['x-prefetch'] === '1' ? prefetch : interactive;
        if (!budget.tryConsume(key)) throw new ApiError('RATE_LIMITED', messages.llmRateLimited);
      };
      await v1.register(contextRoutes, {
        deps: { config: opts.config, llm: opts.llm, cache: opts.cache, store: opts.store, log },
        spend,
      });
      await v1.register(translateRoutes, {
        deps: { config: opts.config, llm: opts.llm, cache: opts.cache, log },
        spend,
      });
    },
    { prefix: '/v1' },
  );

  return app;
}
