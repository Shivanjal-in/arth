import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { ApiError, messages } from '../lib/errors.js';
import { ok } from '../lib/envelope.js';
import { normalizeWord } from '../normalize.js';
import { matchPhrase, type PhraseStore } from '../services/phrases.js';

const Body = z.object({
  tokens: z.array(z.string().max(64)).min(1).max(32),
  index: z.number().int().min(0),
});

export const phraseRoutes: FastifyPluginAsync<{ store: PhraseStore }> = async (app, { store }) => {
  /** Pure DB, no LLM. Runs before /lookup on every tap. */
  app.post('/phrases/match', async (request) => {
    const parsed = Body.safeParse(request.body);
    if (!parsed.success || parsed.data.index >= parsed.data.tokens.length) {
      throw new ApiError('BAD_REQUEST', messages.badRequest);
    }
    const tokens = parsed.data.tokens.map(normalizeWord);
    const match = await matchPhrase(store, tokens, parsed.data.index);
    request.meta.phrase = match ? match.phrase : 'none';
    return ok(match);
  });
};
