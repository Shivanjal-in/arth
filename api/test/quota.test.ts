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
const as = (uid: string, extra: Record<string, string> = {}) => ({ authorization: `Bearer t:${uid}`, ...extra });

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

const context = (uid: string | null, sentence: string, headers: Record<string, string> = {}) => ({
  method: 'POST' as const,
  url: '/v1/context',
  headers: uid ? as(uid, headers) : headers,
  payload: { word: 'single', sentence },
});

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
    // A cache hit is still an AI answer the reader asked for.
    assert.equal((await app.inject(context('ana', `${PP} 1`))).headers['x-ai-used'], '2');
    const over = await app.inject(context('ana', `${PP} 2`));
    assert.equal(over.statusCode, 402);
    assert.equal(over.json().error.code, 'QUOTA_EXCEEDED');
    assert.deepEqual(over.json().error.usage, { used: 2, limit: 2, period: 'lifetime', resetsAt: null });
    assert.equal(llm.requests.length, 1, 'no model call once the allowance is spent');

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
    const base = { displayName: '', email: null, phone: null, photoUrl: null, bio: '', role: 'user' as const, reviewReminders: true, lastReviewNudgeAt: null, lowAiNoticeFor: null, banned: false, createdAt: 0, updatedAt: 0 };
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
