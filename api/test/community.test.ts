import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { buildApp } from '../src/app.js';
import { ApiError } from '../src/lib/errors.js';
import { memoryAccountStore } from '../src/services/accounts.js';
import { memoryCommunityStore } from '../src/services/community.js';
import { FakePusher } from '../src/push/pusher.js';
import type { TokenVerifier } from '../src/auth/verifier.js';
import { appOptions, FakeLLM } from './fakes.js';

const verifier: TokenVerifier = {
  async verify(token) {
    if (!token.startsWith('t:')) throw new ApiError('UNAUTHORIZED', 'bad');
    const uid = token.slice(2);
    return { uid, name: uid[0]!.toUpperCase() + uid.slice(1) };
  },
};
const as = (uid: string) => ({ authorization: `Bearer t:${uid}` });

async function setup() {
  const store = memoryAccountStore();
  const community = memoryCommunityStore();
  const pusher = new FakePusher();
  const app = buildApp({ ...appOptions(new FakeLLM({})), accounts: { store, verifier, cloudinary: null, pusher }, community });
  // Everyone signs in once; tiers and roles as the tests need.
  for (const uid of ['pro', 'free', 'other', 'admin', 'third']) await app.inject({ method: 'GET', url: '/v1/me', headers: as(uid) });
  await store.updateUser('pro', { tier: 'pro' });
  await store.updateUser('admin', { role: 'admin' });
  for (const uid of ['pro', 'free', 'other']) await store.addPushDevice(uid, { token: `tok-${uid}-${'x'.repeat(20)}`, platform: 'android', lang: 'en', updatedAt: 0 });
  return { app, store, community, pusher };
}

const deckBody = {
  title: 'What stayed with me',
  bookTitle: 'The Lighthouse Keeper',
  bookKey: 'key-1',
  blurb: 'Ideas and quotes from a quiet book.',
  cards: [
    { kind: 'idea', front: 'Who is Mira?', back: 'The keeper’s curious daughter', note: '', location: 'Chapter 1' },
    { kind: 'quote', front: 'A peculiar kind of solitude', back: 'एक अनोखा एकांत' },
    { kind: 'word', front: 'solitude', back: 'एकांत' },
    { kind: 'idea', front: 'The storm', back: 'Arrives in October' },
  ],
};

async function publish(app: Awaited<ReturnType<typeof setup>>['app']) {
  const res = await app.inject({ method: 'POST', url: '/v1/community/decks', headers: as('pro'), payload: deckBody });
  assert.equal(res.statusCode, 200, res.body);
  return res.json().data.id as string;
}

describe('publishing', () => {
  test('Pro publishes; Free is told why not; the list says who can publish', async () => {
    const { app } = await setup();
    const free = await app.inject({ method: 'POST', url: '/v1/community/decks', headers: as('free'), payload: deckBody });
    assert.equal(free.statusCode, 403);
    assert.equal(free.json().error.reason, 'tier');
    await publish(app);
    const asFree = (await app.inject({ method: 'GET', url: '/v1/community/decks', headers: as('free') })).json().data;
    assert.equal(asFree.canPublish, false);
    assert.equal((await app.inject({ method: 'GET', url: '/v1/community/decks', headers: as('pro') })).json().data.canPublish, true);
    await app.close();
  });

  test('anyone can browse signed out; the list is a light preview with the author', async () => {
    const { app } = await setup();
    const id = await publish(app);
    const list = (await app.inject({ method: 'GET', url: '/v1/community/decks' })).json().data;
    assert.equal(list.decks.length, 1);
    const d = list.decks[0];
    assert.equal(d.id, id);
    assert.equal(d.cardCount, 4);
    assert.equal(d.preview.length, 3);
    assert.equal(d.author.name, 'Pro');
    assert.equal(d.author.tier, 'pro');
    assert.equal(d.cards, undefined, 'full cards only on the deck page');
    const page = (await app.inject({ method: 'GET', url: `/v1/community/decks/${id}` })).json().data;
    assert.equal(page.cards.length, 4);
    assert.equal(page.cards[1].note, '');
    assert.equal(page.mine, false);
    await app.close();
  });

  test('search by book, sort by popularity', async () => {
    const { app } = await setup();
    const a = await publish(app);
    const b = (await app.inject({ method: 'POST', url: '/v1/community/decks', headers: as('pro'), payload: { ...deckBody, bookTitle: 'Emma' } })).json().data.id;
    await app.inject({ method: 'POST', url: `/v1/community/decks/${a}/save`, headers: as('free') });
    const found = (await app.inject({ method: 'GET', url: '/v1/community/decks?q=emm' })).json().data.decks;
    assert.deepEqual(found.map((d: { id: string }) => d.id), [b]);
    const popular = (await app.inject({ method: 'GET', url: '/v1/community/decks?sort=popular' })).json().data.decks;
    assert.equal(popular[0].id, a);
    await app.close();
  });

  test('only the author edits; the author or an admin removes', async () => {
    const { app } = await setup();
    const id = await publish(app);
    assert.equal((await app.inject({ method: 'PATCH', url: `/v1/community/decks/${id}`, headers: as('other'), payload: { title: 'x' } })).statusCode, 403);
    assert.equal((await app.inject({ method: 'PATCH', url: `/v1/community/decks/${id}`, headers: as('pro'), payload: { title: 'Better title' } })).statusCode, 200);
    assert.equal((await app.inject({ method: 'DELETE', url: `/v1/community/decks/${id}`, headers: as('other') })).statusCode, 403);
    assert.equal((await app.inject({ method: 'DELETE', url: `/v1/community/decks/${id}`, headers: as('admin') })).statusCode, 200);
    assert.equal((await app.inject({ method: 'GET', url: `/v1/community/decks/${id}` })).statusCode, 404);
    // An admin can still open it, and is told it's gone.
    const seen = (await app.inject({ method: 'GET', url: `/v1/community/decks/${id}`, headers: as('admin') })).json().data;
    assert.equal(seen.removed, true);
    await app.close();
  });
});

describe('card font', () => {
  test('a recap keeps the font its author chose; older ones read as Montserrat', async () => {
    const { app } = await setup();
    const plain = await publish(app);
    assert.equal((await app.inject({ method: 'GET', url: `/v1/community/decks/${plain}` })).json().data.font, 'montserrat');

    const res = await app.inject({ method: 'POST', url: '/v1/community/decks', headers: as('pro'), payload: { ...deckBody, font: 'quintessential' } });
    const id = res.json().data.id as string;
    assert.equal((await app.inject({ method: 'GET', url: `/v1/community/decks/${id}` })).json().data.font, 'quintessential');
    const listed = (await app.inject({ method: 'GET', url: '/v1/community/decks' })).json().data.decks;
    assert.equal(listed.find((d: { id: string }) => d.id === id).font, 'quintessential');

    await app.inject({ method: 'PATCH', url: `/v1/community/decks/${id}`, headers: as('pro'), payload: { font: 'bricolage' } });
    assert.equal((await app.inject({ method: 'GET', url: `/v1/community/decks/${id}` })).json().data.font, 'bricolage');

    const bad = await app.inject({ method: 'POST', url: '/v1/community/decks', headers: as('pro'), payload: { ...deckBody, font: 'comic-sans' } });
    assert.equal(bad.statusCode, 400);
    await app.close();
  });
});

describe('reactions and comments', () => {
  test('like toggles; a save counts once per reader', async () => {
    const { app } = await setup();
    const id = await publish(app);
    const like = (u: string) => app.inject({ method: 'POST', url: `/v1/community/decks/${id}/like`, headers: as(u) });
    assert.deepEqual((await like('free')).json().data, { liked: true, likes: 1 });
    assert.deepEqual((await like('free')).json().data, { liked: false, likes: 0 });
    const save = (u: string) => app.inject({ method: 'POST', url: `/v1/community/decks/${id}/save`, headers: as(u) });
    await save('free');
    await save('free');
    assert.equal((await save('other')).json().data.saves, 2);
    await app.close();
  });

  test('a comment notifies the author; a reply notifies the commenter, not the replier', async () => {
    const { app, pusher } = await setup();
    const id = await publish(app);
    const c1 = (await app.inject({ method: 'POST', url: `/v1/community/decks/${id}/comments`, headers: as('free'), payload: { text: 'Loved the storm card' } })).json().data;
    assert.equal(c1.author.name, 'Free');
    await new Promise((r) => setTimeout(r, 10));
    const toPro = pusher.sent.filter((s) => s.tokens[0]!.includes('pro'));
    assert.equal(toPro.length, 1);
    assert.equal(toPro[0]!.message.title, 'New comment on your recap of “The Lighthouse Keeper”');
    assert.equal(toPro[0]!.message.route, `/community/deck/${id}`);

    pusher.sent.length = 0;
    await app.inject({ method: 'POST', url: `/v1/community/decks/${id}/comments`, headers: as('other'), payload: { text: 'Me too', parentId: c1.id } });
    await new Promise((r) => setTimeout(r, 10));
    const recipients = pusher.sent.map((s) => s.tokens[0]!.split('-')[1]).sort();
    assert.deepEqual(recipients, ['free', 'pro'], 'the commenter gets a reply notice, the author a comment notice');
    assert.equal(pusher.sent.find((s) => s.tokens[0]!.includes('free'))!.message.title, 'Other replied to you');

    const page = (await app.inject({ method: 'GET', url: `/v1/community/decks/${id}` })).json().data;
    assert.equal(page.thread.length, 2);
    assert.equal(page.thread[1].parentId, c1.id);
    assert.equal(page.thread[0].mine, false);
    assert.equal(page.thread[0].text, 'Loved the storm card');
    await app.close();
  });

  test('the deck’s author can delete comments on their page; others can’t', async () => {
    const { app } = await setup();
    const id = await publish(app);
    const c = (await app.inject({ method: 'POST', url: `/v1/community/decks/${id}/comments`, headers: as('free'), payload: { text: 'spam' } })).json().data;
    assert.equal((await app.inject({ method: 'DELETE', url: `/v1/community/comments/${c.id}`, headers: as('other') })).statusCode, 403);
    assert.equal((await app.inject({ method: 'DELETE', url: `/v1/community/comments/${c.id}`, headers: as('pro') })).statusCode, 200);
    const page = (await app.inject({ method: 'GET', url: `/v1/community/decks/${id}` })).json().data;
    assert.equal(page.thread.length, 0);
    await app.close();
  });
});

describe('reports and moderation', () => {
  test('three reports hide a deck; the owner still sees it; an admin dismisses and it’s back', async () => {
    const { app, store } = await setup();
    const id = await publish(app);
    for (const u of ['free', 'other']) {
      await app.inject({ method: 'POST', url: '/v1/community/reports', headers: as(u), payload: { kind: 'deck', targetId: id, reason: 'spam' } });
    }
    // A repeat report from the same reader doesn't count twice.
    await app.inject({ method: 'POST', url: '/v1/community/reports', headers: as('free'), payload: { kind: 'deck', targetId: id } });
    assert.equal((await app.inject({ method: 'GET', url: `/v1/community/decks/${id}` })).statusCode, 200, 'two reports: still live');
    const third = await app.inject({ method: 'POST', url: '/v1/community/reports', headers: as('third'), payload: { kind: 'deck', targetId: id } });
    assert.equal(third.json().data.hidden, true);
    assert.equal((await app.inject({ method: 'GET', url: `/v1/community/decks/${id}` })).statusCode, 404);
    assert.equal((await app.inject({ method: 'GET', url: '/v1/community/decks' })).json().data.decks.length, 0);
    const own = (await app.inject({ method: 'GET', url: `/v1/community/decks/${id}`, headers: as('pro') })).json().data;
    assert.equal(own.hidden, true);

    assert.equal((await app.inject({ method: 'GET', url: '/v1/admin/reports', headers: as('pro') })).statusCode, 403);
    const queue = (await app.inject({ method: 'GET', url: '/v1/admin/reports', headers: as('admin') })).json().data.items;
    assert.equal(queue.length, 1);
    assert.equal(queue[0].count, 3);
    assert.deepEqual(queue[0].reasons, ['spam', 'spam']);
    assert.equal(queue[0].preview.bookTitle, 'The Lighthouse Keeper');

    await app.inject({ method: 'POST', url: '/v1/admin/moderate', headers: as('admin'), payload: { kind: 'deck', targetId: id, action: 'dismiss' } });
    assert.equal((await app.inject({ method: 'GET', url: `/v1/community/decks/${id}` })).statusCode, 200);
    assert.equal((await app.inject({ method: 'GET', url: '/v1/admin/reports', headers: as('admin') })).json().data.items.length, 0);
    assert.equal((await store.findUser('pro'))!.banned, false);
    await app.close();
  });

  test('removing a reported comment tells its author and updates the count', async () => {
    const { app, pusher } = await setup();
    const id = await publish(app);
    const c = (await app.inject({ method: 'POST', url: `/v1/community/decks/${id}/comments`, headers: as('other'), payload: { text: 'rude words' } })).json().data;
    await app.inject({ method: 'POST', url: '/v1/community/reports', headers: as('free'), payload: { kind: 'comment', targetId: c.id } });
    pusher.sent.length = 0;
    await app.inject({ method: 'POST', url: '/v1/admin/moderate', headers: as('admin'), payload: { kind: 'comment', targetId: c.id, action: 'remove' } });
    await new Promise((r) => setTimeout(r, 10));
    assert.equal(pusher.sent[0]!.message.title, 'Your comment was removed');
    assert.deepEqual((await app.inject({ method: 'GET', url: `/v1/community/decks/${id}` })).json().data.thread, [], 'gone from the page');
    const deck = (await app.inject({ method: 'GET', url: '/v1/community/decks' })).json().data.decks[0];
    assert.equal(deck.comments, 0);
    await app.close();
  });

  test('you can’t report your own post', async () => {
    const { app } = await setup();
    const id = await publish(app);
    assert.equal((await app.inject({ method: 'POST', url: '/v1/community/reports', headers: as('pro'), payload: { kind: 'deck', targetId: id } })).statusCode, 400);
    await app.close();
  });
});

describe('admin', () => {
  test('ban stops writing but not reading; tier change notifies; can’t ban yourself', async () => {
    const { app, pusher } = await setup();
    const id = await publish(app);
    const found = (await app.inject({ method: 'GET', url: '/v1/admin/users?q=oth', headers: as('admin') })).json().data.users;
    assert.deepEqual(found.map((u: { uid: string }) => u.uid), ['other']);

    await app.inject({ method: 'PATCH', url: '/v1/admin/users/other', headers: as('admin'), payload: { banned: true } });
    assert.equal((await app.inject({ method: 'POST', url: `/v1/community/decks/${id}/comments`, headers: as('other'), payload: { text: 'hi' } })).statusCode, 403);
    assert.equal((await app.inject({ method: 'GET', url: `/v1/community/decks/${id}`, headers: as('other') })).statusCode, 200);
    assert.equal((await app.inject({ method: 'POST', url: `/v1/community/decks/${id}/save`, headers: as('other') })).statusCode, 200);

    pusher.sent.length = 0;
    const up = (await app.inject({ method: 'PATCH', url: '/v1/admin/users/free', headers: as('admin'), payload: { tier: 'super' } })).json().data;
    assert.equal(up.tier, 'super');
    await new Promise((r) => setTimeout(r, 10));
    assert.equal(pusher.sent[0]!.message.title, 'You’re on Super now ✨');
    assert.equal((await app.inject({ method: 'PATCH', url: '/v1/admin/users/admin', headers: as('admin'), payload: { banned: true } })).statusCode, 400);
    await app.close();
  });

  test('broadcast reaches every reader with a phone, or one tier', async () => {
    const { app, pusher } = await setup();
    const all = (await app.inject({ method: 'POST', url: '/v1/admin/broadcast', headers: as('admin'), payload: { title: 'New in Arth', body: 'Community is here' } })).json().data;
    assert.deepEqual(all, { readers: 3, sent: 3 });
    pusher.sent.length = 0;
    const pro = (await app.inject({ method: 'POST', url: '/v1/admin/broadcast', headers: as('admin'), payload: { title: 'Thanks', body: 'For being Pro', tier: 'pro', route: '/community' } })).json().data;
    assert.equal(pro.readers, 1);
    assert.equal(pusher.sent[0]!.message.route, '/community');
    assert.equal((await app.inject({ method: 'POST', url: '/v1/admin/broadcast', headers: as('pro'), payload: { title: 'x', body: 'y' } })).statusCode, 403);
    await app.close();
  });
});
