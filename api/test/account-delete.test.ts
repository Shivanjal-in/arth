import { describe, test } from 'node:test';
import assert from 'node:assert/strict';
import { buildApp } from '../src/app.js';
import { ApiError } from '../src/lib/errors.js';
import { destroyAvatar, signParams } from '../src/lib/cloudinary.js';
import { memoryAccountStore, sync, type CardRow } from '../src/services/accounts.js';
import { memoryCommunityStore } from '../src/services/community.js';
import type { TokenVerifier } from '../src/auth/verifier.js';
import { appOptions, FakeLLM } from './fakes.js';

const verifier: TokenVerifier = {
  async verify(token) {
    if (!token.startsWith('t:')) throw new ApiError('UNAUTHORIZED', 'bad token');
    return { uid: token.slice(2) };
  },
};
const as = (uid: string) => ({ authorization: `Bearer t:${uid}`, 'x-device-id': 'phone-1' });

const card = (id: string): CardRow => ({
  id,
  kind: 'idea',
  front: 'Who is Mira?',
  back: '',
  note: '',
  context: null,
  bookKey: 'k1',
  bookTitle: 'The Lighthouse Keeper',
  page: 1,
  block: null,
  location: null,
  box: 0,
  dueAt: null,
  createdAt: 1,
  updatedAt: 1,
  deletedAt: null,
});
const deckBody = { bookTitle: 'Emma', cards: [{ kind: 'idea', front: 'Knightley' }] };

describe('deleting an account', () => {
  test('their data goes; other readers’ stays, and the counts are right', async () => {
    const store = memoryAccountStore();
    const community = memoryCommunityStore();
    const removed: string[] = [];
    const app = buildApp({
      ...appOptions(new FakeLLM({})),
      accounts: { store, verifier, cloudinary: null },
      community,
      removeLogin: async (uid) => {
        removed.push(uid);
      },
    });
    for (const uid of ['leaver', 'stayer']) {
      await app.inject({ method: 'GET', url: '/v1/me', headers: as(uid) });
      await store.updateUser(uid, { tier: 'super' });
    }
    await sync(store, 'leaver', { cursor: 0, cards: [card('00000000-0000-4000-8000-000000000001')], bookmarks: [] });
    await store.consumeDeviceAi('phone-1', 'leaver', 100, 3);

    const own = (await app.inject({ method: 'POST', url: '/v1/community/decks', headers: as('leaver'), payload: deckBody })).json().data.id as string;
    const theirs = (await app.inject({ method: 'POST', url: '/v1/community/decks', headers: as('stayer'), payload: deckBody })).json().data.id as string;
    await app.inject({ method: 'POST', url: `/v1/community/decks/${theirs}/like`, headers: as('leaver') });
    await app.inject({ method: 'POST', url: `/v1/community/decks/${theirs}/save`, headers: as('leaver') });
    const said = (await app.inject({ method: 'POST', url: `/v1/community/decks/${theirs}/comments`, headers: as('leaver'), payload: { text: 'Lovely' } })).json().data;
    const reply = (await app.inject({ method: 'POST', url: `/v1/community/decks/${theirs}/comments`, headers: as('stayer'), payload: { text: 'Thanks!', parentId: said.id } })).json().data;
    await app.inject({ method: 'POST', url: `/v1/community/decks/${own}/comments`, headers: as('stayer'), payload: { text: 'Nice' } });

    const r = await app.inject({ method: 'DELETE', url: '/v1/me', headers: as('leaver') });
    assert.equal(r.statusCode, 200);

    assert.equal(await store.findUser('leaver'), null);
    assert.deepEqual(removed, ['leaver'], 'the Firebase sign-in goes too');
    assert.equal(community.decks.has(own), false, 'their recap');
    assert.equal([...community.comments.values()].some((c) => c.deckId === own), false, 'and comments on it');
    const left = community.decks.get(theirs)!;
    assert.deepEqual([left.likes, left.saves, left.comments], [0, 0, 1], 'their like, save and comment are gone from the counts');
    assert.equal(community.comments.get(reply.id)!.parentId, null, 'a reply to them stays, on its own');
    assert.equal(await store.deviceAiUsed('phone-1'), 1, 'the phone’s free count is kept');
    // …but a new account on it isn't blocked by the deleted one.
    assert.equal((await store.consumeDeviceAi('phone-1', 'new', 100, 1)).ok, true);

    // Their sign-in stays valid for a while, on this phone or another; it
    // mustn't bring the account back (and a sync from another phone with it).
    assert.equal((await app.inject({ method: 'POST', url: '/v1/sync', headers: as('leaver'), payload: { cursor: 0 } })).statusCode, 401);
    assert.equal(await store.findUser('leaver'), null);
    assert.equal((await app.inject({ method: 'DELETE', url: '/v1/me' })).statusCode, 401);
    await app.close();
  });

  test('the profile photo is destroyed with a signed request', async () => {
    const calls: { url: string; body: URLSearchParams }[] = [];
    const fakeFetch = (async (url: string, init: { body: URLSearchParams }) => {
      calls.push({ url, body: init.body });
      return new Response('{"result":"ok"}', { status: 200 });
    }) as unknown as typeof fetch;
    const cfg = { cloudName: 'demo', apiKey: 'key', apiSecret: 'secret' };
    await destroyAvatar(cfg, 'u1', fakeFetch, 1_790_000_000_000);
    assert.equal(calls[0]!.url, 'https://api.cloudinary.com/v1_1/demo/image/destroy');
    const b = calls[0]!.body;
    assert.equal(b.get('public_id'), 'arth/avatars/u1');
    assert.equal(b.get('signature'), signParams({ invalidate: 'true', public_id: 'arth/avatars/u1', timestamp: 1_790_000_000 }, 'secret'));
  });
});
