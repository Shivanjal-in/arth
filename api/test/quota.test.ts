import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { buildApp } from '../src/app.js';
import { ApiError } from '../src/lib/errors.js';
import { memoryAccountStore } from '../src/services/accounts.js';
import { allowanceFor, monthOf, nextMonthStart, usageOf } from '../src/services/quota.js';
import type { TokenVerifier } from '../src/auth/verifier.js';
import { appOptions, FakeLLM } from './fakes.js';

const verifier: TokenVerifier = {
  async verify(token) {
    if (!token.startsWith('t:')) throw new ApiError('UNAUTHORIZED', 'bad token');
    return { uid: token.slice(2) };
  },
};
// Each reader on their own phone unless a test says otherwise.
const as = (uid: string, extra: Record<string, string> = {}) => ({ authorization: `Bearer t:${uid}`, 'x-device-id': `phone-${uid}`, ...extra });

const PP = 'It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife.';
const answer = (i: number) => JSON.stringify({ senseIndex: 0, meaning: 'अविवाहित', note: `नोट ${i}` });
const translation = JSON.stringify({ source: 'x', hindi: 'यह सच है।', simpleMeaning: 'साफ़ बात।', difficultWords: [] });

/** Free: 2 uses; pro: 3 a month — small, so the limits are reachable. */
function setup(llm: FakeLLM) {
  const store = memoryAccountStore();
  const app = buildApp({
    ...appOptions(llm),
    accounts: { store, verifier, cloudinary: null },
    enforceQuota: true,
    limits: { free: 2, proMonthly: 3 },
  });
  return { app, store };
}

const contextBase = (uid: string | null, sentence: string, headers: Record<string, string> = {}) => ({
  method: 'POST' as const,
  url: '/v1/context',
  headers: uid ? as(uid, headers) : headers,
  payload: { word: 'single', sentence },
});

const context = contextBase;

describe('AI allowance', () => {
  test('AI routes need sign-in; the offline-dictionary lookup does not', async () => {
    const { app } = setup(new FakeLLM({}));
    assert.equal((await app.inject(context(null, PP))).statusCode, 401);
    assert.equal((await app.inject({ method: 'POST', url: '/v1/translate', payload: { text: 'Hello.' } })).statusCode, 401);
    assert.equal((await app.inject({ method: 'GET', url: '/v1/lookup?word=fortune' })).statusCode, 200);
    await app.close();
  });

  test('free: each answer counts, headers report it, then 402 with the usage', async () => {
    const llm = new FakeLLM({ context_result: [answer(1), answer(2)] });
    const { app } = setup(llm);
    const r1 = await app.inject(context('ana', `${PP} 1`));
    assert.equal(r1.statusCode, 200);
    assert.equal(r1.headers['x-ai-used'], '1');
    assert.equal(r1.headers['x-ai-limit'], '2');
    assert.equal(r1.headers['x-ai-period'], 'lifetime');
    // An answer the server already had cost no model call: it is not counted.
    assert.equal((await app.inject(context('ana', `${PP} 1`))).headers['x-ai-used'], '1');
    assert.equal(llm.requests.length, 1);
    assert.equal((await app.inject(context('ana', `${PP} 2`))).headers['x-ai-used'], '2');
    const over = await app.inject(context('ana', `${PP} 3`));
    assert.equal(over.statusCode, 402);
    assert.equal(over.json().error.code, 'QUOTA_EXCEEDED');
    assert.deepEqual(over.json().error.usage, { used: 2, limit: 2, period: 'lifetime', resetsAt: null });
    assert.equal(llm.requests.length, 2, 'no model call once the allowance is spent');

    const me = (await app.inject({ method: 'GET', url: '/v1/me', headers: as('ana') })).json().data;
    assert.deepEqual(me.usage, { used: 2, limit: 2, period: 'lifetime', resetsAt: null });
    assert.equal(me.aiTotal, undefined, 'counters stay server-side');
    await app.close();
  });

  test('single-sense words and failures are refunded', async () => {
    const llm = new FakeLLM({ context_result: ['not json', 'still not json'] });
    const { app, store } = setup(llm);
    const bypass = await app.inject({ method: 'POST', url: '/v1/context', headers: as('ben'), payload: { word: 'wives', sentence: 'His wives were many.' } });
    assert.equal(bypass.statusCode, 200);
    assert.equal(store.users.get('ben')!.aiTotal, 0, 'no AI was needed');
    const failed = await app.inject(context('ben', PP));
    assert.equal(failed.statusCode, 502);
    assert.equal(store.users.get('ben')!.aiTotal, 0, 'a failed answer is given back');
    await app.close();
  });

  test('prefetch is free while allowance remains, refused after', async () => {
    const llm = new FakeLLM({ context_result: [answer(1), answer(2), answer(3)] });
    const { app, store } = setup(llm);
    const pre = await app.inject(context('cy', `${PP} a`, { 'x-prefetch': '1' }));
    assert.equal(pre.statusCode, 200);
    assert.equal(store.users.get('cy')!.aiTotal, 0);
    await app.inject(context('cy', `${PP} b`));
    await app.inject(context('cy', `${PP} c`));
    assert.equal((await app.inject(context('cy', `${PP} d`, { 'x-prefetch': '1' }))).statusCode, 402);
    await app.close();
  });

  test('translate counts once, reports usage on the stream, and refunds a failure', async () => {
    const llm = new FakeLLM({ translation_result: [translation, '{}', '{}'] });
    const { app, store } = setup(llm);
    const ok = await app.inject({ method: 'POST', url: '/v1/translate', headers: as('di'), payload: { text: 'It is true.' } });
    assert.equal(ok.statusCode, 200);
    assert.equal(ok.headers['x-ai-used'], '1');
    assert.match(ok.headers['content-type'] as string, /event-stream/);
    const bad = await app.inject({ method: 'POST', url: '/v1/translate', headers: as('di'), payload: { text: 'Another one.' } });
    assert.match(bad.body, /event: error/);
    assert.equal(store.users.get('di')!.aiTotal, 1);
    await app.close();
  });

  test('pro counts per month; super is unlimited', async () => {
    const llm = new FakeLLM({ context_result: Array.from({ length: 6 }, (_, i) => answer(i)) });
    const { app, store } = setup(llm);
    await app.inject({ method: 'GET', url: '/v1/me', headers: as('pro') });
    await store.updateUser('pro', { tier: 'pro', aiTotal: 50 });
    for (let i = 0; i < 3; i++) assert.equal((await app.inject(context('pro', `${PP} p${i}`))).statusCode, 200);
    const over = await app.inject(context('pro', `${PP} p3`));
    assert.equal(over.statusCode, 402);
    assert.equal(over.json().error.usage.period, 'month');
    assert.ok(over.json().error.usage.resetsAt > Date.now());

    await app.inject({ method: 'GET', url: '/v1/me', headers: as('sup') });
    await store.updateUser('sup', { tier: 'super' });
    const s = await app.inject(context('sup', `${PP} s`));
    assert.equal(s.statusCode, 200);
    assert.equal(s.headers['x-ai-limit'], 'none');
    await app.close();
  });

  test('a new month starts the pro count again', async () => {
    const store = memoryAccountStore();
    const base = { displayName: '', email: null, phone: null, photoUrl: null, bio: '', role: 'user' as const, grantTier: 'free' as const, storeTier: 'free' as const, reviewReminders: true, lastReviewNudgeAt: null, lowAiNoticeFor: null, banned: false, createdAt: 0, updatedAt: 0 };
    await store.insertUser({ ...base, uid: 'p', tier: 'pro', aiTotal: 9, aiMonth: '2026-08', aiMonthUses: 3 });
    const allowance = allowanceFor('pro', { free: 2, proMonthly: 3 });
    assert.equal(await store.consumeAi('p', '2026-08', allowance), null);
    const september = await store.consumeAi('p', '2026-09', allowance);
    assert.equal(september!.aiMonthUses, 1);
    assert.equal(september!.aiTotal, 10);
    const now = Date.UTC(2026, 8, 24);
    assert.equal(monthOf(now), '2026-09');
    assert.equal(nextMonthStart(now), Date.UTC(2026, 9, 1));
    assert.equal(usageOf({ ...september!, aiMonth: '2026-08' }, { free: 2, proMonthly: 3 }, now).used, 0, 'last month’s count doesn’t show');
  });

  test('without enforcement (no Firebase project), AI stays open', async () => {
    const app = buildApp(appOptions(new FakeLLM({ context_result: [answer(1)] })));
    assert.equal((await app.inject(context(null, PP))).statusCode, 200);
    await app.close();
  });
});

describe('one phone, many accounts', () => {
  const on = (phone: string) => ({ 'x-device-id': phone });
  let n = 0;
  const context = (uid: string | null, _sentence: string, headers: Record<string, string> = {}) => contextBase(uid, `${PP} ${n++}`, headers);
  function phoneSetup(limits = { free: 2, proMonthly: 3, freeAccountsPerDevice: 3 }) {
    const store = memoryAccountStore();
    // Plenty of model answers: each call below uses its own sentence, since a cached repeat is free.
    const app = buildApp({ ...appOptions(new FakeLLM({ context_result: Array.from({ length: 12 }, (_, k) => answer(k)) })), accounts: { store, verifier, cloudinary: null }, enforceQuota: true, limits });
    return { app, store };
  }

  test('a new email on the same phone does not reset the free allowance', async () => {
    const { app } = phoneSetup();
    assert.equal((await app.inject(context('ana', PP, on('X')))).statusCode, 200);
    assert.equal((await app.inject(context('ana', PP, on('X')))).statusCode, 200);

    const bo = await app.inject(context('bo', PP, on('X')));
    assert.equal(bo.statusCode, 402);
    assert.equal(bo.json().error.reason, 'phone');
    assert.equal(bo.json().error.usage.used, 2);
    // bo's own count was given back: on another phone they still have theirs.
    assert.equal((await app.inject(context('bo', PP, on('Y')))).headers['x-ai-used'], '1');
    // …and /me on the spent phone says so.
    const me = (await app.inject({ method: 'GET', url: '/v1/me', headers: as('bo', on('X')) })).json().data;
    assert.equal(me.usage.used, 2);
    assert.equal(me.usage.phone, true, 'the app can say it’s the phone, not bo, that used them');
    await app.close();
  });

  test('only a few free accounts may share one phone', async () => {
    const { app } = phoneSetup({ free: 10, proMonthly: 3, freeAccountsPerDevice: 2 });
    assert.equal((await app.inject(context('a', PP, on('X')))).statusCode, 200);
    assert.equal((await app.inject(context('b', PP, on('X')))).statusCode, 200);
    const c = await app.inject(context('c', PP, on('X')));
    assert.equal(c.statusCode, 402);
    assert.equal(c.json().error.reason, 'phone_accounts');
    assert.equal((await app.inject(context('a', PP, on('X')))).statusCode, 200, 'accounts already on the phone carry on');
    await app.close();
  });

  test('paid plans and admins are not held to the phone', async () => {
    const { app, store } = phoneSetup();
    await app.inject(context('ana', PP, on('X')));
    await app.inject(context('ana', PP, on('X')));
    await app.inject({ method: 'GET', url: '/v1/me', headers: as('pro') });
    await app.inject({ method: 'GET', url: '/v1/me', headers: as('boss') });
    await store.updateUser('pro', { tier: 'pro' });
    await store.updateUser('boss', { role: 'admin' });
    assert.equal((await app.inject(context('pro', PP, on('X')))).statusCode, 200);
    assert.equal((await app.inject(context('boss', PP, on('X')))).statusCode, 200);
    await app.close();
  });

  test('prefetch stops when the phone is spent; free AI needs the app’s device id', async () => {
    const { app } = phoneSetup();
    await app.inject(context('ana', PP, on('X')));
    await app.inject(context('ana', PP, on('X')));
    assert.equal((await app.inject(context('bo', PP, { ...on('X'), 'x-prefetch': '1' }))).statusCode, 402);

    const bare = await app.inject({ method: 'POST', url: '/v1/context', headers: { authorization: 'Bearer t:cy' }, payload: { word: 'single', sentence: PP } });
    assert.equal(bare.statusCode, 400);
    await app.close();
  });
});
