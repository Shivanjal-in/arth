import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { ApiError, messages } from '../lib/errors.js';
import { ok } from '../lib/envelope.js';
import { findCover, type CoverDeps } from '../services/cover.js';

const Query = z.object({
  title: z.string().trim().min(2).max(160),
  author: z.string().trim().max(120).optional(),
});

/** GET /v1/cover?title=…&author=… → { url: string | null }. Never an error for "no match". */
export const coverRoutes: FastifyPluginAsync<CoverDeps> = async (app, deps) => {
  app.get('/cover', async (request) => {
    const parsed = Query.safeParse(request.query);
    if (!parsed.success) throw new ApiError('BAD_REQUEST', messages.badRequest);
    const url = await findCover(deps, parsed.data.title, parsed.data.author);
    request.meta.cover = { found: url !== null };
    return ok({ url });
  });
};
