/**
 * POST /v1/billing/revenuecat  RevenueCat's webhook: a purchase, renewal,
 *                              cancellation, expiry… Authorised by the header
 *                              configured in RevenueCat (REVENUECAT_WEBHOOK_AUTH).
 * POST /v1/billing/sync        The app, right after a purchase or restore:
 *                              apply it now rather than when the webhook lands.
 *
 * Either way the reader's store plan is re-read from RevenueCat and their
 * plan becomes the higher of that and any plan an admin granted.
 */
import { timingSafeEqual } from 'node:crypto';
import type { FastifyPluginAsync } from 'fastify';
import { ok } from '../lib/envelope.js';
import { ApiError, messages } from '../lib/errors.js';
import { authenticate, type AccountDeps } from './account.js';
import { higherTier, type User } from '../services/accounts.js';
import type { Billing } from '../billing/revenuecat.js';
import { notifyUser, tierMessage } from '../push/notify.js';
import { disabledPusher } from '../push/pusher.js';

export type BillingDeps = AccountDeps & { billing: Billing; webhookAuth: string };

const sameSecret = (a: string, b: string) => {
  const x = Buffer.from(a);
  const y = Buffer.from(b);
  return x.length === y.length && timingSafeEqual(x, y);
};

export const billingRoutes: FastifyPluginAsync<BillingDeps> = async (app, deps) => {
  const pusher = deps.pusher ?? disabledPusher;

  /** Re-reads [user]'s store plan and applies it; tells them if their plan changed. */
  const apply = async (user: User, log: { warn: (o: object, m: string) => void }) => {
    const storeTier = await deps.billing.storeTier(user.uid);
    const tier = higherTier(user.grantTier, storeTier);
    if (storeTier === user.storeTier && tier === user.tier) return user;
    const after = (await deps.store.updateUser(user.uid, { storeTier, tier, updatedAt: Date.now() })) ?? user;
    if (after.tier !== user.tier) {
      void notifyUser(deps.store, pusher, after.uid, tierMessage(after.tier)).catch((err: unknown) => log.warn({ err }, 'plan push failed'));
    }
    return after;
  };

  app.post<{ Body: { event?: { type?: string; app_user_id?: string; original_app_user_id?: string } } }>('/billing/revenuecat', async (req, reply) => {
    const auth = (req.headers.authorization ?? '').toString();
    if (!deps.webhookAuth || !sameSecret(auth, deps.webhookAuth)) throw new ApiError('UNAUTHORIZED', messages.signInRequired);
    const event = req.body?.event;
    // RevenueCat's "Send test event" button, and anonymous buyers (the app
    // logs readers in before any purchase, so these shouldn't happen).
    const uid = event?.app_user_id ?? event?.original_app_user_id;
    if (!event || event.type === 'TEST' || !uid || uid.startsWith('$RCAnonymousID')) return ok({ applied: false });
    const user = await deps.store.findUser(uid);
    // Unknown uid: acknowledge, or RevenueCat retries for days.
    if (!user) return ok({ applied: false });
    if (!deps.billing.enabled) {
      req.log.warn({ uid, type: event.type }, 'RevenueCat webhook but REVENUECAT_SECRET_KEY is unset');
      return reply.status(503).send({ ok: false });
    }
    const after = await apply(user, req.log);
    req.log.info({ uid, type: event.type, tier: after.tier }, 'store plan applied');
    return ok({ applied: true, tier: after.tier });
  });

  app.post('/billing/sync', async (req) => {
    const user = await authenticate(req, deps);
    if (!deps.billing.enabled) throw new ApiError('UNAVAILABLE', messages.billingUnavailable);
    const after = await apply(user, req.log);
    return ok({ tier: after.tier });
  });
};
