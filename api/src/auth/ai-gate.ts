import type { FastifyReply, FastifyRequest } from 'fastify';
import { ApiError, messages } from '../lib/errors.js';
import { authenticate, type AccountDeps } from '../routes/account.js';
import { allowanceFor, hasRemaining, monthOf, usageOf, type Limits, type Usage } from '../services/quota.js';
import { maybeWarnLowAi } from '../push/notify.js';

/** A counted AI use; give it back if no AI answer was served. */
export type AiUse = { refund(): Promise<void> };

/**
 * Admits an AI request, or throws: UNAUTHORIZED when signed out,
 * QUOTA_EXCEEDED (with the usage) when the allowance is spent. Background
 * prefetch is admitted only while there's allowance left and is never
 * counted — the reader's tap on that word is what counts.
 *
 * Null when nothing was counted: prefetch, or accounts off (no Firebase
 * project configured: AI stays open, as before accounts existed).
 */
export type AiGate = (req: FastifyRequest, reply: FastifyReply) => Promise<AiUse | null>;

export const openGate: AiGate = async () => null;

export function aiGate(deps: AccountDeps, limits: Limits): AiGate {
  return async (req, reply) => {
    const user = await authenticate(req, deps);
    const now = Date.now();
    const exceeded = (usage: Usage) => new ApiError('QUOTA_EXCEEDED', messages.quotaExceeded, { usage });
    if (req.headers['x-prefetch'] === '1') {
      if (!hasRemaining(user, limits, now)) throw exceeded(usageOf(user, limits, now));
      return null;
    }
    const month = monthOf(now);
    const counted = await deps.store.consumeAi(user.uid, month, allowanceFor(user.tier, limits));
    if (!counted) throw exceeded(usageOf(user, limits, now));
    const usage = usageOf(counted, limits, now);
    // Off the request's path: a slow push never delays an answer.
    if (deps.pusher?.enabled) {
      void maybeWarnLowAi(deps.store, deps.pusher, counted, limits, now).catch((err: unknown) => req.log.warn({ err }, 'low-AI push failed'));
    }
    // The app keeps its "N left" current from these, without polling /me.
    reply.header('x-ai-used', String(usage.used));
    reply.header('x-ai-limit', usage.limit === null ? 'none' : String(usage.limit));
    reply.header('x-ai-period', usage.period);
    let refunded = false;
    return {
      async refund() {
        if (refunded) return;
        refunded = true;
        await deps.store.refundAi(user.uid, month);
      },
    };
  };
}
