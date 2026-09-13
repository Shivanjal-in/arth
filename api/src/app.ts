import Fastify, { type FastifyInstance, type FastifyRequest } from 'fastify';
import { ApiError, messages } from './lib/errors.js';
import { fail } from './lib/envelope.js';
import { schemas } from './contracts.js';
import { healthRoutes } from './routes/health.js';
import { lookupRoutes } from './routes/lookup.js';
import type { LemmaStore } from './services/lemma.js';

/** Per-request facts that end up on the one structured log line per request. */
export type RequestMeta = {
  lookup?: { word: string; lemma?: string; via: string };
  cache?: 'hit' | 'miss' | 'bypass';
  tokens?: { input: number; output: number; cachedInput?: number };
  model?: string;
};

declare module 'fastify' {
  interface FastifyRequest {
    meta: RequestMeta;
  }
}

export type AppOptions = {
  logLevel?: string;
  store: LemmaStore;
};

export function buildApp(opts: AppOptions): FastifyInstance {
  const app = Fastify({
    logger: { level: opts.logLevel ?? 'info' },
    disableRequestLogging: true, // we emit our own single line in onResponse
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

  app.register(
    async (v1) => {
      await v1.register(healthRoutes);
      await v1.register(lookupRoutes, { store: opts.store });
    },
    { prefix: '/v1' },
  );

  return app;
}
