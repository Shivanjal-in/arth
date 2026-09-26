import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { ApiError, messages } from '../lib/errors.js';
import { cacheStats } from '../cache/cache.js';
import { translate, type TranslateDeps, type TranslateEvent } from '../services/translate.js';

const Body = z.object({
  text: z.string().trim().min(1).max(2000),
  context: z.string().trim().max(2000).optional(),
});

function sse(ev: TranslateEvent): string {
  return `event: ${ev.event}\ndata: ${JSON.stringify(ev.data)}\n\n`;
}

import type { LlmSpend } from './context.js';
import { openGate, type AiGate } from '../auth/ai-gate.js';

export const translateRoutes: FastifyPluginAsync<{ deps: TranslateDeps; spend: LlmSpend; gate?: AiGate }> = async (app, { deps, spend, gate = openGate }) => {
  /**
   * Server-sent events: `hindi`, `simpleMeaning`, `difficultWords`, then `done`
   * with the full TranslationResult — or `error` with the envelope's error shape.
   * Validation errors still come back as a normal JSON 400 before the stream opens.
   */
  app.post('/translate', async (request, reply) => {
    const parsed = Body.safeParse(request.body);
    if (!parsed.success) throw new ApiError('BAD_REQUEST', messages.badRequest);
    const { text, context } = parsed.data;
    // Before the stream opens: signed out / out of allowance is a plain JSON error.
    const use = await gate(request, reply);

    reply.raw.writeHead(200, {
      // Usage headers the gate set (writeHead bypasses Fastify's reply headers).
      ...(reply.getHeaders() as Record<string, string>),
      'content-type': 'text/event-stream; charset=utf-8',
      'cache-control': 'no-store',
      connection: 'keep-alive',
      'x-accel-buffering': 'no',
    });
    reply.raw.flushHeaders?.();

    // IncomingMessage 'close' fires as soon as the request body is consumed on
    // modern Node, so listen on the response: it closes only if the client goes away.
    const abort = new AbortController();
    reply.raw.on('close', () => {
      if (!reply.raw.writableFinished) abort.abort();
    });

    try {
      const gen = translate(
        { ...deps, spend: () => spend(request) },
        text,
        context,
        (s) => {
          if (s.cache === 'hit') cacheStats.hits++;
          else cacheStats.misses++;
          request.meta.cache = s.cache;
          request.meta.tokens = s.usage;
          if (s.model) request.meta.model = s.model;
          request.meta.translate = { chars: text.length, retried: s.retried };
        },
        abort.signal,
      );
      for await (const ev of gen) {
        if (abort.signal.aborted) break;
        reply.raw.write(sse(ev));
      }
    } catch (err) {
      await use?.refund();
      const e = err instanceof ApiError ? err : new ApiError('UPSTREAM_FAILED', messages.upstreamFailed, {}, { cause: err });
      if (e.status >= 500) request.log.error({ err }, 'translate failed');
      if (!abort.signal.aborted) reply.raw.write(sse({ event: 'error', data: { code: e.code, message: e.message } }));
    }
    reply.raw.end();
    return reply;
  });
};
