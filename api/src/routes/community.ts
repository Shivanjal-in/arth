import type { FastifyPluginAsync, FastifyRequest } from 'fastify';
import { ok } from '../lib/envelope.js';
import { ApiError, messages } from '../lib/errors.js';
import { authenticate, type AccountDeps } from './account.js';
import type { User } from '../services/accounts.js';
import {
  addComment,
  canBrowse,
  canPublish,
  editDeck,
  publishDeck,
  removeComment,
  removeDeck,
  report,
  visibleComments,
  visibleDeck,
  type Comment,
  type CommunityStore,
  type Deck,
  type DeckCard,
  type DeckFont,
  DECK_FONTS,
} from '../services/community.js';
import { notifyUser } from '../push/notify.js';
import { disabledPusher } from '../push/pusher.js';
import { commentMessage, replyMessage } from '../push/community-messages.js';

export type CommunityDeps = AccountDeps & { community: CommunityStore };

/**
 * The community is part of Pro and Super: a signed-in reader on one of
 * those plans (or an admin). Free readers are told what it takes, by
 * `reason: 'plan'`, so the app can show them the plans.
 */
async function member(req: FastifyRequest, deps: AccountDeps): Promise<User> {
  const user = await authenticate(req, deps);
  if (!canBrowse(user)) throw new ApiError('FORBIDDEN', messages.communityNeedsPlan, { reason: 'plan' });
  return user;
}

export type Author = { uid: string; name: string; photoUrl: string | null; tier: User['tier'] };

const authorOf = (u: User | undefined, uid: string): Author => ({
  uid,
  name: u?.displayName || 'Reader',
  photoUrl: u?.photoUrl ?? null,
  tier: u?.tier ?? 'free',
});

const summary = (d: Deck, author: Author, liked: boolean) => ({
  id: d.id,
  title: d.title,
  bookTitle: d.bookTitle,
  blurb: d.blurb,
  font: d.font ?? 'montserrat',
  cardCount: d.cardCount,
  preview: d.cards.slice(0, 3).map((c) => ({ kind: c.kind, front: c.front })),
  likes: d.likes,
  saves: d.saves,
  comments: d.comments,
  createdAt: d.createdAt,
  author,
  liked,
});

const commentView = (c: Comment, author: Author, viewerUid: string | undefined) => ({
  id: c.id,
  parentId: c.parentId,
  text: c.text,
  createdAt: c.createdAt,
  hidden: c.status === 'hidden',
  author,
  mine: c.owner === viewerUid,
});

const text = (max: number) => ({ type: 'string', maxLength: max }) as const;
const cardSchema = {
  type: 'object',
  additionalProperties: false,
  required: ['kind', 'front'],
  properties: {
    kind: { enum: ['idea', 'quote', 'word'] },
    front: { type: 'string', minLength: 1, maxLength: 2000 },
    back: text(4000),
    note: text(4000),
    location: { type: ['string', 'null'], maxLength: 300 },
  },
} as const;

type PublishBody = { title?: string; bookTitle: string; bookKey?: string | null; blurb?: string; font?: DeckFont; cards: Partial<DeckCard>[] };

const normalizeCards = (cards: Partial<DeckCard>[]): DeckCard[] =>
  cards.map((c) => ({ kind: c.kind!, front: c.front!, back: c.back ?? '', note: c.note ?? '', location: c.location ?? null }));

export const communityRoutes: FastifyPluginAsync<CommunityDeps> = async (app, deps) => {
  const store = deps.community;
  const pusher = deps.pusher ?? disabledPusher;
  const authors = async (uids: string[]) => deps.store.findUsers([...new Set(uids)]);
  const signedIn = async (req: FastifyRequest) => authenticate(req, deps);

  /** Pushes without holding up the response; a failed push is only logged. */
  const push = (req: FastifyRequest, uid: string, message: Parameters<typeof notifyUser>[3]) => {
    void notifyUser(deps.store, pusher, uid, message).catch((err: unknown) => req.log.warn({ err }, 'community push failed'));
  };

  app.get<{ Querystring: { sort?: 'recent' | 'popular'; q?: string; page?: number; owner?: string } }>(
    '/community/decks',
    {
      schema: {
        querystring: {
          type: 'object',
          properties: {
            sort: { enum: ['recent', 'popular'], default: 'recent' },
            q: { type: 'string', maxLength: 100 },
            page: { type: 'integer', minimum: 0, maximum: 500, default: 0 },
            owner: { type: 'string', maxLength: 128 },
          },
        },
      },
    },
    async (req) => {
      const me = await member(req, deps);
      const { sort = 'recent', q, page = 0, owner } = req.query;
      const limit = 20;
      const decks = await store.listDecks({ sort, q, owner, page, limit });
      const users = await authors(decks.map((d) => d.owner));
      const liked = me ? await store.likedBy(me.uid, decks.map((d) => d.id)) : new Set<string>();
      return ok({
        decks: decks.map((d) => summary(d, authorOf(users.get(d.owner), d.owner), liked.has(d.id))),
        more: decks.length === limit,
        canPublish: me ? canPublish(me) : false,
      });
    },
  );

  app.get<{ Params: { id: string } }>('/community/decks/:id', async (req) => {
    const me = await member(req, deps);
    const deck = await visibleDeck(store, req.params.id, me);
    const comments = await visibleComments(store, deck.id, me);
    const users = await authors([deck.owner, ...comments.map((c) => c.owner)]);
    const liked = me ? (await store.likedBy(me.uid, [deck.id])).has(deck.id) : false;
    return ok({
      ...summary(deck, authorOf(users.get(deck.owner), deck.owner), liked),
      bookKey: deck.bookKey,
      cards: deck.cards,
      hidden: deck.status === 'hidden',
      // Only admins ever see a removed deck.
      removed: deck.status === 'removed',
      mine: deck.owner === me?.uid,
      // `comments` is the count (from the summary); the list is the thread.
      thread: comments.map((c) => commentView(c, authorOf(users.get(c.owner), c.owner), me?.uid)),
    });
  });

  app.post<{ Body: PublishBody }>(
    '/community/decks',
    {
      bodyLimit: 2 * 1024 * 1024,
      schema: {
        body: {
          type: 'object',
          additionalProperties: false,
          required: ['bookTitle', 'cards'],
          properties: {
            title: text(120),
            bookTitle: { type: 'string', minLength: 1, maxLength: 300 },
            bookKey: { type: ['string', 'null'], maxLength: 128 },
            blurb: text(600),
            font: { enum: [...DECK_FONTS] },
            cards: { type: 'array', minItems: 1, maxItems: 300, items: cardSchema },
          },
        },
      },
    },
    async (req) => {
      const me = await member(req, deps);
      const b = req.body;
      const deck = await publishDeck(store, me, {
        title: b.title ?? '',
        bookTitle: b.bookTitle,
        bookKey: b.bookKey ?? null,
        blurb: b.blurb ?? '',
        ...(b.font ? { font: b.font } : {}),
        cards: normalizeCards(b.cards),
      });
      return ok({ id: deck.id });
    },
  );

  app.patch<{ Params: { id: string }; Body: Partial<PublishBody> }>(
    '/community/decks/:id',
    {
      bodyLimit: 2 * 1024 * 1024,
      schema: {
        body: {
          type: 'object',
          additionalProperties: false,
          properties: { title: text(120), blurb: text(600), font: { enum: [...DECK_FONTS] }, cards: { type: 'array', minItems: 1, maxItems: 300, items: cardSchema } },
        },
      },
    },
    async (req) => {
      const me = await member(req, deps);
      const b = req.body;
      await editDeck(store, me, req.params.id, {
        ...(b.title !== undefined ? { title: b.title } : {}),
        ...(b.blurb !== undefined ? { blurb: b.blurb } : {}),
        ...(b.font !== undefined ? { font: b.font } : {}),
        ...(b.cards !== undefined ? { cards: normalizeCards(b.cards) } : {}),
      });
      return ok({ id: req.params.id });
    },
  );

  app.delete<{ Params: { id: string } }>('/community/decks/:id', async (req) => {
    await removeDeck(store, await signedIn(req), req.params.id);
    return ok({ removed: true });
  });

  app.post<{ Params: { id: string } }>('/community/decks/:id/like', async (req) => {
    const me = await member(req, deps);
    await visibleDeck(store, req.params.id, me);
    return ok(await store.toggleLike(req.params.id, me.uid));
  });

  /** Counts the save; the app copies the cards (it already has them from the deck page). */
  app.post<{ Params: { id: string } }>('/community/decks/:id/save', async (req) => {
    const me = await member(req, deps);
    await visibleDeck(store, req.params.id, me);
    return ok({ saves: await store.addSave(req.params.id, me.uid) });
  });

  app.post<{ Params: { id: string }; Body: { text: string; parentId?: string | null } }>(
    '/community/decks/:id/comments',
    {
      schema: {
        body: {
          type: 'object',
          additionalProperties: false,
          required: ['text'],
          properties: { text: { type: 'string', minLength: 1, maxLength: 1000 }, parentId: { type: ['string', 'null'], maxLength: 64 } },
        },
      },
    },
    async (req) => {
      const me = await member(req, deps);
      if (!req.body.text.trim()) throw new ApiError('BAD_REQUEST', 'खाली टिप्पणी नहीं भेज सकते।');
      const { comment, deck, parent } = await addComment(store, me, req.params.id, req.body.text, req.body.parentId ?? null);
      const route = `/community/deck/${deck.id}`;
      // Tell the deck's author, and whoever was replied to — never yourself, never twice.
      if (parent && parent.owner !== me.uid) push(req, parent.owner, replyMessage(me.displayName, deck.bookTitle, comment.text, route));
      if (deck.owner !== me.uid && deck.owner !== parent?.owner) push(req, deck.owner, commentMessage(me.displayName, deck.bookTitle, comment.text, route));
      return ok(commentView(comment, authorOf(me, me.uid), me.uid));
    },
  );

  app.delete<{ Params: { id: string } }>('/community/comments/:id', async (req) => {
    await removeComment(store, await signedIn(req), req.params.id);
    return ok({ removed: true });
  });

  app.post<{ Body: { kind: 'deck' | 'comment'; targetId: string; reason?: string } }>(
    '/community/reports',
    {
      schema: {
        body: {
          type: 'object',
          additionalProperties: false,
          required: ['kind', 'targetId'],
          properties: { kind: { enum: ['deck', 'comment'] }, targetId: { type: 'string', maxLength: 64 }, reason: text(300) },
        },
      },
    },
    async (req) => {
      const me = await member(req, deps);
      return ok(await report(store, me, req.body.kind, req.body.targetId, req.body.reason ?? ''));
    },
  );
};
