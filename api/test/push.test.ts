import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { buildApp } from '../src/app.js';
import { ApiError } from '../src/lib/errors.js';
import { memoryAccountStore, sync, type CardRow } from '../src/services/accounts.js';
import { FakePusher } from '../src/push/pusher.js';
import { maybeWarnLowAi, reviewMessage, sendReviewReminders, tierMessage } from '../src/push/notify.js';
import { parseServiceAccount } from '../src/auth/firebase-app.js';
import type { TokenVerifier } from '../src/auth/verifier.js';
import { appOptions, FakeLLM } from './fakes.js';

const verifier: TokenVerifier = {
  async verify(token) {
    if (!token.startsWith('t:')) throw new ApiError('UNAUTHORIZED', 'bad');
    return { uid: token.slice(2) };
  },
};
const as = (uid: string) => ({ authorization: `Bearer t:${uid}`, 'x-device-id': `phone-${uid}` });
const tok = (s: string) => `fcm-token-${s}-${'x'.repeat(20)}`;

function setup() {
  const store = memoryAccountStore();
  const pusher = new FakePusher();
  const llm = new FakeLLM({ context_result: Array.from({ length: 12 }, (_, i) => JSON.stringify({ senseIndex: 0, meaning: 'अविवाहित', note: `n${i}` })) });
  const app = buildApp({ ...appOptions(llm), accounts: { store, verifier, cloudinary: null, pusher }, enforceQuota: true, limits: { free: 12, proMonthly: 100 } });
  return { store, pusher, app };
}

function card(id: string, dueAt: number | null, extra: Partial<CardRow> = {}): CardRow {
  return {
    id, kind: 'idea', front: 'f', back: '', note: '', context: null, bookKey: null, bookTitle: 'Emma', page: 1, block: null,
    location: null, box: 0, dueAt, createdAt: 1, updatedAt: 1, deletedAt: null, ...extra,
  };
}
const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;

describe('push tokens', () => {
  test('register, test push reaches every phone in its language, unregister', async () => {
    const { app, pusher } = setup();
    await app.inject({ method: 'POST', url: '/v1/me/push-token', headers: as('ana'), payload: { token: tok('phone'), platform: 'android', lang: 'hi' } });
    await app.inject({ method: 'POST', url: '/v1/me/push-token', headers: as('ana'), payload: { token: tok('tablet'), platform: 'ios' } });
    const res = await app.inject({ method: 'POST', url: '/v1/me/push-test', headers: as('ana') });
    assert.equal(res.statusCode, 200);
    assert.deepEqual(res.json().data, { devices: 2, sent: 2 });
    const byToken = Object.fromEntries(pusher.sent.flatMap((s) => s.tokens.map((t) => [t, s.message.body])));
    assert.match(byToken[tok('phone')]!, /सूचनाएँ/);
    assert.match(byToken[tok('tablet')]!, /Notifications are working/);

    await app.inject({ method: 'DELETE', url: '/v1/me/push-token', headers: as('ana'), payload: { token: tok('phone') } });
    const after = await app.inject({ method: 'POST', url: '/v1/me/push-test', headers: as('ana') });
    assert.equal(after.json().data.devices, 1);
    await app.close();
  });

  test('a phone that switches accounts only gets the new account’s pushes', async () => {
    const { app, store } = setup();
    await app.inject({ method: 'POST', url: '/v1/me/push-token', headers: as('ben'), payload: { token: tok('shared'), platform: 'android' } });
    await app.inject({ method: 'POST', url: '/v1/me/push-token', headers: as('cy'), payload: { token: tok('shared'), platform: 'android' } });
    assert.equal((await store.pushDevices('ben')).length, 0);
    assert.equal((await store.pushDevices('cy')).length, 1);
    await app.close();
  });

  test('dead tokens are forgotten after a send', async () => {
    const { app, store, pusher } = setup();
    await app.inject({ method: 'POST', url: '/v1/me/push-token', headers: as('di'), payload: { token: tok('old'), platform: 'android' } });
    pusher.dead.add(tok('old'));
    await app.inject({ method: 'POST', url: '/v1/me/push-test', headers: as('di') });
    assert.equal((await store.pushDevices('di')).length, 0);
    await app.close();
  });

  test('signed out: 401; without a service account: 503', async () => {
    const { app } = setup();
    assert.equal((await app.inject({ method: 'POST', url: '/v1/me/push-token', payload: { token: tok('a'), platform: 'android' } })).statusCode, 401);
    await app.close();
    const store = memoryAccountStore();
    const bare = buildApp({ ...appOptions(new FakeLLM({})), accounts: { store, verifier, cloudinary: null } });
    assert.equal((await bare.inject({ method: 'POST', url: '/v1/me/push-test', headers: as('ed') })).statusCode, 503);
    await bare.close();
  });
});

describe('triggers', () => {
  test('AI running low: warned once, when exactly 10 free answers are left', async () => {
    const { app, pusher } = setup();
    await app.inject({ method: 'POST', url: '/v1/me/push-token', headers: as('fay'), payload: { token: tok('f'), platform: 'android' } });
    const PP = 'It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife.';
    for (let i = 0; i < 4; i++) {
      await app.inject({ method: 'POST', url: '/v1/context', headers: as('fay'), payload: { word: 'single', sentence: `${PP} ${i}` } });
    }
    await new Promise((r) => setTimeout(r, 20)); // the warning is sent off the request's path
    const warnings = pusher.sent.filter((s) => s.message.tag === 'ai-low');
    assert.equal(warnings.length, 1, 'limit 12: the 2nd use leaves 10 → one warning, none after');
    assert.equal(warnings[0]!.message.title, '10 AI answers left');
    assert.equal(warnings[0]!.message.route, '/plans');
    await app.close();
  });

  test('review reminders: only readers with due cards, at most daily, off when turned off', async () => {
    const store = memoryAccountStore();
    const pusher = new FakePusher();
    const base = { displayName: '', email: null, phone: null, photoUrl: null, bio: '', role: 'user' as const, tier: 'free' as const, grantTier: 'free' as const, storeTier: 'free' as const, aiTotal: 0, aiMonth: null, aiMonthUses: 0, lastReviewNudgeAt: null, lowAiNoticeFor: null, banned: false, createdAt: 0, updatedAt: 0 };
    for (const uid of ['due', 'notdue', 'optout']) {
      await store.insertUser({ ...base, uid, reviewReminders: uid !== 'optout' });
      await store.addPushDevice(uid, { token: tok(uid), platform: 'android', lang: 'en', updatedAt: 0 });
    }
    const now = 1_800_000_000_000;
    await sync(store, 'due', { cursor: 0, cards: [card(id(1), null), card(id(2), now - 1), card(id(3), now + 86_400_000), card(id(4), null, { deletedAt: 5 })], bookmarks: [] });
    await sync(store, 'notdue', { cursor: 0, cards: [card(id(5), now + 86_400_000)], bookmarks: [] });
    await sync(store, 'optout', { cursor: 0, cards: [card(id(6), null)], bookmarks: [] });

    const first = await sendReviewReminders(store, pusher, now);
    assert.deepEqual(first, { checked: 2, reminded: 1 });
    assert.equal(pusher.sent[0]!.message.body, '2 cards are ready — most from “Emma”.');
    assert.equal(pusher.sent[0]!.message.route, '/cards');

    const again = await sendReviewReminders(store, pusher, now + 3_600_000);
    assert.equal(again.reminded, 0, 'not twice in a day');
    const tomorrow = await sendReviewReminders(store, pusher, now + 21 * 3_600_000);
    assert.equal(tomorrow.reminded, 1);
  });

  test('messages read naturally in both languages', () => {
    assert.equal(reviewMessage(1, null)('en').body, '1 card is ready.');
    assert.match(reviewMessage(3, 'Godan')('hi').body, /3 कार्ड/);
    assert.equal(tierMessage('pro')('en').title, 'You’re on Pro now ✨');
    assert.match(tierMessage('super')('hi').body, /असीमित/);
  });

  test('low-AI warning skips Super and repeats per Pro month', async () => {
    const store = memoryAccountStore();
    const pusher = new FakePusher();
    const base = { displayName: '', email: null, phone: null, photoUrl: null, bio: '', role: 'user' as const, grantTier: 'free' as const, storeTier: 'free' as const, reviewReminders: true, lastReviewNudgeAt: null, lowAiNoticeFor: null, banned: false, createdAt: 0, updatedAt: 0 };
    await store.insertUser({ ...base, uid: 'p', tier: 'pro', aiTotal: 950, aiMonth: '2026-09', aiMonthUses: 950 });
    await store.addPushDevice('p', { token: tok('p'), platform: 'ios', lang: 'en', updatedAt: 0 });
    const limits = { free: 100, proMonthly: 1000 };
    const sept = Date.UTC(2026, 8, 20);
    assert.equal(await maybeWarnLowAi(store, pusher, (await store.findUser('p'))!, limits, sept), true);
    assert.equal(await maybeWarnLowAi(store, pusher, (await store.findUser('p'))!, limits, sept), false, 'once per month');
    await store.updateUser('p', { aiMonth: '2026-10', aiMonthUses: 950 });
    assert.equal(await maybeWarnLowAi(store, pusher, (await store.findUser('p'))!, limits, Date.UTC(2026, 9, 20)), true, 'a new month warns again');
    await store.insertUser({ ...base, uid: 's', tier: 'super', aiTotal: 90, aiMonth: null, aiMonthUses: 0 });
    assert.equal(await maybeWarnLowAi(store, pusher, (await store.findUser('s'))!, limits), false);
  });
});

describe('service account', () => {
  test('parses raw JSON or base64, fixing escaped newlines', () => {
    const json = JSON.stringify({ project_id: 'arth-reader', client_email: 'x@y.iam.gserviceaccount.com', private_key: '-----BEGIN PRIVATE KEY-----\\nabc\\n-----END PRIVATE KEY-----\\n' });
    const a = parseServiceAccount(json)!;
    assert.equal(a.projectId, 'arth-reader');
    assert.ok(a.privateKey.includes('\nabc\n'));
    assert.deepEqual(parseServiceAccount(Buffer.from(json).toString('base64')), a);
    assert.equal(parseServiceAccount(''), null);
    assert.equal(parseServiceAccount('{"nope":1}'), null);
  });
});
