import type { FastifyPluginAsync } from 'fastify';
import { ok } from '../lib/envelope.js';
import { ApiError } from '../lib/errors.js';
import { authenticate } from './account.js';
import type { CommunityDeps } from './community.js';
import type { Tier, User } from '../services/accounts.js';
import { moderate, type ReportKind } from '../services/community.js';
import { usageOf, type Limits } from '../services/quota.js';
import { notifyUser, tierMessage } from '../push/notify.js';
import { disabledPusher } from '../push/pusher.js';
import { broadcastMessage, removedMessage } from '../push/community-messages.js';

const userView = (u: User, limits: Limits) => ({
  uid: u.uid,
  displayName: u.displayName,
  email: u.email,
  phone: u.phone,
  photoUrl: u.photoUrl,
  role: u.role,
  tier: u.tier,
  banned: u.banned,
  usage: usageOf(u, limits),
  createdAt: u.createdAt,
});

export const adminRoutes: FastifyPluginAsync<CommunityDeps & { limits: Limits }> = async (app, deps) => {
  const { community, limits } = deps;
  const pusher = deps.pusher ?? disabledPusher;

  app.addHook('onRequest', async (req) => {
    const me = await authenticate(req, deps);
    if (me.role !== 'admin') throw new ApiError('FORBIDDEN', 'यह सिर्फ़ एडमिन के लिए है।');
    req.user = me;
  });

  /** Open reports, grouped by what was reported, with that thing's content. */
  app.get('/admin/reports', async () => {
    const reports = await community.openReports(500);
    const groups = new Map<string, { kind: ReportKind; targetId: string; reasons: string[]; count: number; firstAt: number }>();
    for (const r of reports) {
      const key = `${r.kind}:${r.targetId}`;
      const g = groups.get(key) ?? { kind: r.kind, targetId: r.targetId, reasons: [], count: 0, firstAt: r.createdAt };
      g.count++;
      if (r.reason) g.reasons.push(r.reason);
      groups.set(key, g);
    }
    const items = [];
    for (const g of groups.values()) {
      const target = g.kind === 'deck' ? await community.findDeck(g.targetId) : await community.findComment(g.targetId);
      if (!target) continue;
      const owner = await deps.store.findUser(target.owner);
      const preview =
        g.kind === 'deck'
          ? { bookTitle: (target as { bookTitle: string }).bookTitle, title: (target as { title: string }).title, deckId: target.id }
          : { text: (target as { text: string }).text, deckId: (target as { deckId: string }).deckId };
      items.push({ ...g, status: target.status, owner: owner ? { uid: owner.uid, name: owner.displayName, banned: owner.banned } : null, preview });
    }
    // Most-reported first.
    items.sort((a, b) => b.count - a.count || a.firstAt - b.firstAt);
    return ok({ items });
  });

  app.post<{ Body: { kind: ReportKind; targetId: string; action: 'remove' | 'dismiss' } }>(
    '/admin/moderate',
    {
      schema: {
        body: {
          type: 'object',
          additionalProperties: false,
          required: ['kind', 'targetId', 'action'],
          properties: { kind: { enum: ['deck', 'comment'] }, targetId: { type: 'string', maxLength: 64 }, action: { enum: ['remove', 'dismiss'] } },
        },
      },
    },
    async (req) => {
      const { kind, targetId, action } = req.body;
      const removed = await moderate(community, kind, targetId, action);
      if (removed) void notifyUser(deps.store, pusher, removed.owner, removedMessage(kind, removed.title)).catch(() => {});
      return ok({ done: true });
    },
  );

  app.get<{ Querystring: { q?: string } }>(
    '/admin/users',
    { schema: { querystring: { type: 'object', properties: { q: { type: 'string', maxLength: 100 } } } } },
    async (req) => {
      const users = await deps.store.searchUsers(req.query.q ?? '', 50);
      return ok({ users: users.map((u) => userView(u, limits)) });
    },
  );

  app.patch<{ Params: { uid: string }; Body: { tier?: Tier; banned?: boolean } }>(
    '/admin/users/:uid',
    {
      schema: {
        body: {
          type: 'object',
          additionalProperties: false,
          properties: { tier: { enum: ['free', 'pro', 'super'] }, banned: { type: 'boolean' } },
        },
      },
    },
    async (req) => {
      const before = await deps.store.findUser(req.params.uid);
      if (!before) throw new ApiError('NOT_FOUND', 'यह उपयोगकर्ता नहीं मिला।');
      if (req.params.uid === req.user!.uid && req.body.banned) throw new ApiError('BAD_REQUEST', 'खुद को प्रतिबंधित नहीं कर सकते।');
      const set: Partial<User> = { updatedAt: Date.now() };
      if (req.body.tier !== undefined) set.tier = req.body.tier;
      if (req.body.banned !== undefined) set.banned = req.body.banned;
      const after = (await deps.store.updateUser(req.params.uid, set))!;
      if (after.tier !== before.tier) void notifyUser(deps.store, pusher, after.uid, tierMessage(after.tier)).catch(() => {});
      return ok(userView(after, limits));
    },
  );

  /** A notification to everyone (or one tier) with a phone registered. */
  app.post<{ Body: { title: string; body: string; tier?: Tier; route?: string } }>(
    '/admin/broadcast',
    {
      schema: {
        body: {
          type: 'object',
          additionalProperties: false,
          required: ['title', 'body'],
          properties: {
            title: { type: 'string', minLength: 1, maxLength: 80 },
            body: { type: 'string', minLength: 1, maxLength: 240 },
            tier: { enum: ['free', 'pro', 'super'] },
            route: { type: 'string', pattern: '^/[a-z/?=&0-9-]*$', maxLength: 100 },
          },
        },
      },
    },
    async (req) => {
      if (!pusher.enabled) throw new ApiError('UNAVAILABLE', 'सूचनाएँ अभी उपलब्ध नहीं हैं।');
      const { title, body, tier, route } = req.body;
      const uids = await deps.store.usersWithDevices(tier);
      let sent = 0;
      for (const uid of uids) sent += await notifyUser(deps.store, pusher, uid, broadcastMessage(title, body, route));
      return ok({ readers: uids.length, sent });
    },
  );
};
