import { describe, test } from 'node:test';
import assert from 'node:assert/strict';
import { buildApp } from '../src/app.js';
import { ApiError } from '../src/lib/errors.js';
import { memoryAccountStore, type Tier } from '../src/services/accounts.js';
import { storeTierFrom, type Billing } from '../src/billing/revenuecat.js';
import { allowanceFor } from '../src/services/quota.js';
import type { TokenVerifier } from '../src/auth/verifier.js';
import { FakePusher } from '../src/push/pusher.js';
import { appOptions, FakeLLM } from './fakes.js';

const verifier: TokenVerifier = {
  async verify(token) {
    if (!token.startsWith('t:')) throw new ApiError('UNAUTHORIZED', 'bad token');
    return { uid: token.slice(2) };
  },
};
const as = (uid: string) => ({ authorization: `Bearer t:${uid}` });
const HOOK = 'Bearer hook-secret';

/** RevenueCat as the tests want it: each uid's current store plan. */
class FakeBilling implements Billing {
  readonly enabled = true;
  plans = new Map<string, Tier>();
  async storeTier(uid: string) {
    return this.plans.get(uid) ?? 'free';
  }
}

async function setup() {
  const store = memoryAccountStore();
  const billing = new FakeBilling();
  const pusher = new FakePusher();
  const app = buildApp({ ...appOptions(new FakeLLM({})), accounts: { store, verifier, cloudinary: null, pusher }, billing: { billing, webhookAuth: HOOK } });
  for (const uid of ['ana', 'granted']) await app.inject({ method: 'GET', url: '/v1/me', headers: as(uid) });
  await store.addPushDevice('ana', { token: `tok-ana-${'x'.repeat(20)}`, platform: 'android', lang: 'en', updatedAt: 0 });
  return { app, store, billing, pusher };
}
const hook = (uid: string, type = 'INITIAL_PURCHASE', auth = HOOK) => ({
  method: 'POST' as const,
  url: '/v1/billing/revenuecat',
  headers: { authorization: auth },
  payload: { event: { type, app_user_id: uid } },
});

describe('store plans (RevenueCat)', () => {
  test('entitlements to a plan: super over pro, lapsed ones ignored, grace periods kept', () => {
    const now = Date.parse('2026-09-27T00:00:00Z');
    const later = '2026-10-27T00:00:00Z';
    const earlier = '2026-09-01T00:00:00Z';
    assert.equal(storeTierFrom({ subscriber: { entitlements: { pro: { expires_date: later } } } }, now), 'pro');
    assert.equal(storeTierFrom({ subscriber: { entitlements: { pro: { expires_date: later }, super: { expires_date: later } } } }, now), 'super');
    assert.equal(storeTierFrom({ subscriber: { entitlements: { super: { expires_date: earlier } } } }, now), 'free');
    assert.equal(storeTierFrom({ subscriber: { entitlements: { pro: { expires_date: earlier, grace_period_expires_date: later } } } }, now), 'pro');
    assert.equal(storeTierFrom({ subscriber: { entitlements: { pro: { expires_date: null } } } }, now), 'pro', 'no end date: lifetime');
    assert.equal(storeTierFrom({}, now), 'free');
  });

  test('a purchase upgrades the reader and tells them; expiry takes it back', async () => {
    const { app, store, billing, pusher } = await setup();
    billing.plans.set('ana', 'pro');
    const r = await app.inject(hook('ana'));
    assert.equal(r.statusCode, 200);
    assert.equal((await store.findUser('ana'))!.tier, 'pro');
    await new Promise((res) => setTimeout(res, 10));
    assert.equal(pusher.sent.length, 1);

    billing.plans.set('ana', 'free');
    await app.inject(hook('ana', 'EXPIRATION'));
    assert.equal((await store.findUser('ana'))!.tier, 'free');
    await app.close();
  });

  test('a granted plan survives a lapsed or lower purchase', async () => {
    const { app, store, billing } = await setup();
    await store.updateUser('admin', { role: 'admin' });
    await app.inject({ method: 'GET', url: '/v1/me', headers: as('admin') });
    await store.updateUser('admin', { role: 'admin' });
    await app.inject({ method: 'PATCH', url: '/v1/admin/users/granted', headers: as('admin'), payload: { tier: 'super' } });
    billing.plans.set('granted', 'pro');
    await app.inject(hook('granted'));
    assert.equal((await store.findUser('granted'))!.tier, 'super', 'granted super beats bought pro');
    billing.plans.set('granted', 'free');
    await app.inject(hook('granted', 'EXPIRATION'));
    assert.equal((await store.findUser('granted'))!.tier, 'super', 'expiry leaves the grant');
    await app.close();
  });

  test('webhooks need the configured header; test events and strangers are acknowledged', async () => {
    const { app, store } = await setup();
    assert.equal((await app.inject(hook('ana', 'INITIAL_PURCHASE', 'Bearer wrong'))).statusCode, 401);
    assert.equal((await app.inject({ method: 'POST', url: '/v1/billing/revenuecat', payload: { event: { type: 'TEST', app_user_id: 'x' } } })).statusCode, 401);
    assert.deepEqual((await app.inject(hook('ana', 'TEST'))).json().data, { applied: false });
    assert.deepEqual((await app.inject(hook('nobody'))).json().data, { applied: false });
    assert.deepEqual((await app.inject(hook('$RCAnonymousID:abc'))).json().data, { applied: false });
    assert.equal((await store.findUser('ana'))!.tier, 'free');
    await app.close();
  });

  test('the app syncs right after buying, without waiting for the webhook', async () => {
    const { app, billing } = await setup();
    billing.plans.set('ana', 'super');
    const r = await app.inject({ method: 'POST', url: '/v1/billing/sync', headers: as('ana') });
    assert.deepEqual(r.json().data, { tier: 'super' });
    assert.equal((await app.inject({ method: 'POST', url: '/v1/billing/sync' })).statusCode, 401);
    const me = (await app.inject({ method: 'GET', url: '/v1/me', headers: as('ana') })).json().data;
    assert.equal(me.tier, 'super');
    assert.equal(me.storeTier, undefined, 'plan bookkeeping stays server-side');
    await app.close();
  });

  test('allowances: Pro 500 and Super 5,000 a month by default', () => {
    assert.deepEqual(allowanceFor('pro'), { period: 'month', max: 500 });
    assert.deepEqual(allowanceFor('super'), { period: 'month', max: 5000 });
  });
});
