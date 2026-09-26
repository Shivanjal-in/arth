import { test, describe, after } from 'node:test';
import assert from 'node:assert/strict';
import { buildApp } from '../src/app.js';
import { ApiError } from '../src/lib/errors.js';
import { parseCloudinaryUrl, signParams } from '../src/lib/cloudinary.js';
import { memoryAccountStore, sync, type CardRow } from '../src/services/accounts.js';
import type { TokenVerifier } from '../src/auth/verifier.js';
import { appOptions, FakeLLM } from './fakes.js';

/** "t:<uid>" is a valid token for <uid>; anything else is rejected. */
const fakeVerifier: TokenVerifier = {
  async verify(token) {
    if (!token.startsWith('t:')) throw new ApiError('UNAUTHORIZED', 'bad token');
    const uid = token.slice(2);
    return { uid, email: `${uid}@example.com`, name: `User ${uid}`, picture: 'https://lh3.googleusercontent.com/x' };
  },
};

const store = memoryAccountStore();
const cloudinary = parseCloudinaryUrl('cloudinary://123456:s3cret@arth-cloud');
const app = buildApp({ ...appOptions(new FakeLLM({})), accounts: { store, verifier: fakeVerifier, cloudinary } });
after(() => app.close());

const as = (uid: string) => ({ authorization: `Bearer t:${uid}` });

function card(id: string, updatedAt: number, extra: Partial<CardRow> = {}): CardRow {
  return {
    id,
    kind: 'idea',
    front: `front ${id}`,
    back: '',
    note: '',
    context: null,
    bookKey: 'k1',
    bookTitle: 'Emma',
    page: 3,
    block: null,
    location: 'Chapter 3',
    box: 0,
    dueAt: null,
    createdAt: 1,
    updatedAt,
    deletedAt: null,
    ...extra,
  };
}

const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;

describe('auth', () => {
  test('no token → 401; bad token → 401', async () => {
    assert.equal((await app.inject({ method: 'GET', url: '/v1/me' })).statusCode, 401);
    const bad = await app.inject({ method: 'GET', url: '/v1/me', headers: { authorization: 'Bearer nope' } });
    assert.equal(bad.statusCode, 401);
    assert.equal(bad.json().error.code, 'UNAUTHORIZED');
  });

  test('a signed-out sync with a bad body is still a 401, not a 400', async () => {
    const res = await app.inject({ method: 'POST', url: '/v1/sync', payload: { nonsense: true } });
    assert.equal(res.statusCode, 401);
  });

  test('first request creates a free user from the token', async () => {
    const res = await app.inject({ method: 'GET', url: '/v1/me', headers: as('alice') });
    assert.equal(res.statusCode, 200);
    const me = res.json().data;
    assert.equal(me.uid, 'alice');
    assert.equal(me.displayName, 'User alice');
    assert.equal(me.tier, 'free');
    assert.equal(me.role, 'user');
    assert.equal(me.photoUrl, 'https://lh3.googleusercontent.com/x');
  });

  test('concurrent first requests end up with one user, not a conflict', async () => {
    const results = await Promise.all([
      app.inject({ method: 'GET', url: '/v1/me', headers: as('racer') }),
      app.inject({ method: 'POST', url: '/v1/sync', headers: as('racer'), payload: { cursor: 0 } }),
      app.inject({ method: 'GET', url: '/v1/me', headers: as('racer') }),
    ]);
    assert.deepEqual(results.map((r) => r.statusCode), [200, 200, 200]);
  });

  test('without accounts configured, account routes answer 503', async () => {
    const bare = buildApp(appOptions(new FakeLLM({})));
    const res = await bare.inject({ method: 'GET', url: '/v1/me', headers: as('alice') });
    assert.equal(res.statusCode, 503);
    await bare.close();
  });
});

describe('profile', () => {
  test('edits name and bio; trims', async () => {
    const res = await app.inject({ method: 'PATCH', url: '/v1/me', headers: as('bob'), payload: { displayName: '  Bob  ', bio: 'Reads Austen.' } });
    assert.equal(res.statusCode, 200);
    assert.equal(res.json().data.displayName, 'Bob');
    assert.equal(res.json().data.bio, 'Reads Austen.');
  });

  test('photo must be one of our Cloudinary images', async () => {
    const good = await app.inject({
      method: 'PATCH',
      url: '/v1/me',
      headers: as('bob'),
      payload: { photoUrl: 'https://res.cloudinary.com/arth-cloud/image/upload/v1/arth/avatars/bob.jpg' },
    });
    assert.equal(good.statusCode, 200);
    const bad = await app.inject({ method: 'PATCH', url: '/v1/me', headers: as('bob'), payload: { photoUrl: 'https://evil.example/x.png' } });
    assert.equal(bad.statusCode, 400);
    const cleared = await app.inject({ method: 'PATCH', url: '/v1/me', headers: as('bob'), payload: { photoUrl: null } });
    assert.equal(cleared.json().data.photoUrl, null);
  });

  test('an empty name is rejected; role and tier cannot be self-set', async () => {
    assert.equal((await app.inject({ method: 'PATCH', url: '/v1/me', headers: as('bob'), payload: { displayName: '' } })).statusCode, 400);
    // Fastify strips properties the schema doesn't list (removeAdditional).
    const res = await app.inject({ method: 'PATCH', url: '/v1/me', headers: as('bob'), payload: { tier: 'super', role: 'admin' } });
    assert.equal(res.json().data.tier, 'free');
    assert.equal(res.json().data.role, 'user');
  });

  test('avatar ticket is signed over the exact params, per user', async () => {
    const res = await app.inject({ method: 'POST', url: '/v1/me/avatar', headers: as('bob') });
    assert.equal(res.statusCode, 200);
    const t = res.json().data;
    assert.equal(t.uploadUrl, 'https://api.cloudinary.com/v1_1/arth-cloud/image/upload');
    assert.equal(t.apiKey, '123456');
    assert.equal(t.params.public_id, 'bob');
    assert.equal(t.signature, signParams({ ...t.params, timestamp: t.timestamp }, 's3cret'));
    assert.ok(!JSON.stringify(t).includes('s3cret'), 'the secret never leaves the server');
  });
});

describe('cloudinary signing', () => {
  test('matches Cloudinary’s documented example', () => {
    // https://cloudinary.com/documentation/authentication_signatures
    assert.equal(
      signParams({ eager: 'w_400,h_300,c_pad|w_260,h_200,c_crop', public_id: 'sample_image', timestamp: 1315060510 }, 'abcd'),
      'bfd09f95f331f558cbd1320e67aa8d488770583e',
    );
  });
});

describe('sync', () => {
  test('push, then another device pulls it; the pusher gets no echo', async () => {
    const pushA = await app.inject({ method: 'POST', url: '/v1/sync', headers: as('carol'), payload: { cursor: 0, cards: [card(id(1), 100)] } });
    assert.equal(pushA.statusCode, 200);
    const a = pushA.json().data;
    assert.equal(a.accepted, 1);
    assert.deepEqual(a.cards, [], 'no echo of what it just sent');
    assert.ok(a.cursor > 0);

    const pullB = (await app.inject({ method: 'POST', url: '/v1/sync', headers: as('carol'), payload: { cursor: 0 } })).json().data;
    assert.equal(pullB.cards.length, 1);
    assert.equal(pullB.cards[0].front, `front ${id(1)}`);
    assert.equal(pullB.cards[0].bookKey, 'k1');

    const again = (await app.inject({ method: 'POST', url: '/v1/sync', headers: as('carol'), payload: { cursor: pullB.cursor } })).json().data;
    assert.deepEqual(again.cards, []);
  });

  test('last write wins by updatedAt; a stale edit is ignored', async () => {
    const s = memoryAccountStore();
    await s.insertUser({ uid: 'd', displayName: '', email: null, phone: null, photoUrl: null, bio: '', role: 'user', tier: 'free', grantTier: 'free', storeTier: 'free', aiTotal: 0, aiMonth: null, aiMonthUses: 0, reviewReminders: true, lastReviewNudgeAt: null, lowAiNoticeFor: null, banned: false, createdAt: 0, updatedAt: 0 });
    await sync(s, 'd', { cursor: 0, cards: [card(id(2), 200, { front: 'new' })], bookmarks: [] });
    const stale = await sync(s, 'd', { cursor: 0, cards: [card(id(2), 150, { front: 'old' })], bookmarks: [] });
    assert.equal(stale.accepted, 0);
    assert.equal(stale.cards[0]!.front, 'new', 'the device is told the newer version');
    const tomb = await sync(s, 'd', { cursor: 0, cards: [card(id(2), 300, { deletedAt: 300 })], bookmarks: [] });
    assert.equal(tomb.accepted, 1);
  });

  test('one user cannot overwrite or read another user’s rows', async () => {
    await app.inject({ method: 'POST', url: '/v1/sync', headers: as('erin'), payload: { cursor: 0, cards: [card(id(3), 100, { front: 'erin' })] } });
    const hijack = (
      await app.inject({ method: 'POST', url: '/v1/sync', headers: as('mallory'), payload: { cursor: 0, cards: [card(id(3), 999, { front: 'mallory' })] } })
    ).json().data;
    assert.equal(hijack.accepted, 0);
    assert.deepEqual(hijack.cards, []);
    const erin = (await app.inject({ method: 'POST', url: '/v1/sync', headers: as('erin'), payload: { cursor: 0 } })).json().data;
    assert.equal(erin.cards[0].front, 'erin');
  });

  test('pages through a long history without skipping rows', async () => {
    const s = memoryAccountStore();
    await s.insertUser({ uid: 'f', displayName: '', email: null, phone: null, photoUrl: null, bio: '', role: 'user', tier: 'free', grantTier: 'free', storeTier: 'free', aiTotal: 0, aiMonth: null, aiMonthUses: 0, reviewReminders: true, lastReviewNudgeAt: null, lowAiNoticeFor: null, banned: false, createdAt: 0, updatedAt: 0 });
    const rows = Array.from({ length: 7 }, (_, i) => card(id(100 + i), 10 + i));
    await sync(s, 'f', { cursor: 0, cards: rows.slice(0, 4), bookmarks: [] });
    await sync(s, 'f', {
      cursor: 0,
      cards: rows.slice(4),
      bookmarks: [{ id: id(200), bookKey: 'k1', bookTitle: 'Emma', page: 4, block: 2, label: 'Chapter 4', excerpt: null, createdAt: 1, updatedAt: 1, deletedAt: null }],
    });
    const seen: string[] = [];
    let cursor = 0;
    for (let i = 0; i < 10; i++) {
      const page = await sync(s, 'f', { cursor, cards: [], bookmarks: [] }, 3);
      seen.push(...page.cards.map((c) => c.id), ...page.bookmarks.map((b) => b.id));
      cursor = page.cursor;
      if (!page.more) break;
    }
    assert.equal(seen.length, 8);
    assert.equal(new Set(seen).size, 8);
  });

  test('rejects malformed rows', async () => {
    const res = await app.inject({ method: 'POST', url: '/v1/sync', headers: as('carol'), payload: { cursor: 0, cards: [{ id: id(9), kind: 'poem' }] } });
    assert.equal(res.statusCode, 400);
  });
});
