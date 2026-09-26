import type { FastifyPluginAsync, FastifyRequest } from 'fastify';
import type { TokenVerifier } from '../auth/verifier.js';
import { avatarTicket, type CloudinaryConfig } from '../lib/cloudinary.js';
import { ok } from '../lib/envelope.js';
import { ApiError, messages } from '../lib/errors.js';
import { signIn, sync, updateProfile, type AccountStore, type ProfilePatch, type SyncRequest, type User } from '../services/accounts.js';
import { defaultLimits, usageOf, type Limits } from '../services/quota.js';
import { deviceIdOf, withPhone } from '../auth/device.js';
import { disabledPusher, type Pusher } from '../push/pusher.js';
import { notifyUser, testMessage } from '../push/notify.js';

declare module 'fastify' {
  interface FastifyRequest {
    /** The signed-in user, set by the account routes' auth hook. */
    user?: User;
  }
}

export type AccountDeps = {
  store: AccountStore;
  verifier: TokenVerifier;
  cloudinary: CloudinaryConfig | null;
  /** Sends notifications; disabled without a service account. */
  pusher?: Pusher;
};

/** Verifies `Authorization: Bearer <Firebase ID token>`; creates the user on first sight. */
export async function authenticate(req: FastifyRequest, deps: AccountDeps): Promise<User> {
  const header = req.headers.authorization ?? '';
  const token = header.startsWith('Bearer ') ? header.slice(7).trim() : '';
  if (!token) throw new ApiError('UNAUTHORIZED', messages.signInRequired);
  const claims = await deps.verifier.verify(token);
  return signIn(deps.store, claims);
}

const uuid = '^[0-9a-fA-F-]{8,64}$';
const ms = { type: 'integer', minimum: 0 } as const;
const nullableMs = { type: ['integer', 'null'], minimum: 0 } as const;
const text = (max: number) => ({ type: 'string', maxLength: max }) as const;
const nullableText = (max: number) => ({ type: ['string', 'null'], maxLength: max }) as const;
const nullableInt = { type: ['integer', 'null'], minimum: 0 } as const;

const cardSchema = {
  type: 'object',
  additionalProperties: false,
  required: ['id', 'kind', 'front', 'back', 'note', 'box', 'createdAt', 'updatedAt'],
  properties: {
    id: { type: 'string', pattern: uuid },
    kind: { enum: ['idea', 'quote', 'word'] },
    front: text(2000),
    back: text(4000),
    note: text(4000),
    context: nullableText(2000),
    bookKey: nullableText(128),
    bookTitle: nullableText(300),
    page: nullableInt,
    block: nullableInt,
    location: nullableText(300),
    box: { type: 'integer', minimum: 0, maximum: 10 },
    dueAt: nullableMs,
    createdAt: ms,
    updatedAt: ms,
    deletedAt: nullableMs,
  },
} as const;

const bookmarkSchema = {
  type: 'object',
  additionalProperties: false,
  required: ['id', 'page', 'createdAt', 'updatedAt'],
  properties: {
    id: { type: 'string', pattern: uuid },
    bookKey: nullableText(128),
    bookTitle: nullableText(300),
    page: { type: 'integer', minimum: 0 },
    block: nullableInt,
    label: nullableText(300),
    excerpt: nullableText(500),
    createdAt: ms,
    updatedAt: ms,
    deletedAt: nullableMs,
  },
} as const;

/** Wire defaults for optional nullable fields, so stored rows are uniform. */
const cardDefaults = { context: null, bookKey: null, bookTitle: null, page: null, block: null, location: null, dueAt: null, deletedAt: null };
const bookmarkDefaults = { bookKey: null, bookTitle: null, block: null, label: null, excerpt: null, deletedAt: null };

/** The user as the app sees them: profile, tier, and AI usage. */
const view = (user: User, limits: Limits, phoneUsed = 0) => {
  const { aiTotal: _t, aiMonth: _m, aiMonthUses: _u, lastReviewNudgeAt: _r, lowAiNoticeFor: _l, grantTier: _g, storeTier: _s, ...profile } = user;
  return { ...profile, usage: withPhone(usageOf(user, limits), user.role === 'admin' ? 0 : phoneUsed) };
};

export const accountRoutes: FastifyPluginAsync<AccountDeps & { limits?: Limits }> = async (app, { limits = defaultLimits, ...deps }) => {
  // Before body validation: a signed-out request is a 401, whatever it sent.
  app.addHook('onRequest', async (req) => {
    req.user = await authenticate(req, deps);
  });

  app.get('/me', async (req) => {
    const device = deviceIdOf(req);
    return ok(view(req.user!, limits, device ? await deps.store.deviceAiUsed(device) : 0));
  });

  app.patch<{ Body: ProfilePatch }>(
    '/me',
    {
      schema: {
        body: {
          type: 'object',
          additionalProperties: false,
          properties: {
            displayName: { type: 'string', minLength: 1, maxLength: 60 },
            bio: { type: 'string', maxLength: 280 },
            photoUrl: { type: ['string', 'null'], maxLength: 500 },
            reviewReminders: { type: 'boolean' },
          },
        },
      },
    },
    async (req) => {
      const { photoUrl } = req.body;
      // Only our own Cloudinary account's images: a profile photo shown to
      // other readers must not be an arbitrary URL.
      if (photoUrl != null) {
        const cloud = deps.cloudinary?.cloudName;
        if (!cloud || !photoUrl.startsWith(`https://res.cloudinary.com/${cloud}/`)) {
          throw new ApiError('BAD_REQUEST', messages.badRequest);
        }
      }
      const user = await updateProfile(deps.store, req.user!.uid, req.body);
      return ok(user && view(user, limits));
    },
  );

  /** This phone can receive notifications: remember its FCM token. */
  app.post<{ Body: { token: string; platform: 'android' | 'ios'; lang?: 'en' | 'hi' } }>(
    '/me/push-token',
    {
      schema: {
        body: {
          type: 'object',
          additionalProperties: false,
          required: ['token', 'platform'],
          properties: {
            token: { type: 'string', minLength: 20, maxLength: 4096 },
            platform: { enum: ['android', 'ios'] },
            lang: { enum: ['en', 'hi'] },
          },
        },
      },
    },
    async (req) => {
      const { token, platform, lang = 'en' } = req.body;
      await deps.store.addPushDevice(req.user!.uid, { token, platform, lang, updatedAt: Date.now() });
      return ok({ saved: true });
    },
  );

  /** Signing out on this phone: stop sending here. */
  app.delete<{ Body: { token: string } }>(
    '/me/push-token',
    {
      schema: {
        body: { type: 'object', additionalProperties: false, required: ['token'], properties: { token: { type: 'string', maxLength: 4096 } } },
      },
    },
    async (req) => {
      await deps.store.removePushToken(req.user!.uid, req.body.token);
      return ok({ removed: true });
    },
  );

  /** A notification to the caller's own phones, to check it all works. */
  app.post('/me/push-test', async (req) => {
    const pusher = deps.pusher ?? disabledPusher;
    if (!pusher.enabled) throw new ApiError('UNAVAILABLE', messages.pushUnavailable);
    const devices = (await deps.store.pushDevices(req.user!.uid)).length;
    const sent = await notifyUser(deps.store, pusher, req.user!.uid, testMessage);
    return ok({ devices, sent });
  });

  /** A signed ticket for uploading this user's avatar straight to Cloudinary. */
  app.post('/me/avatar', async (req) => {
    if (!deps.cloudinary) throw new ApiError('UNAVAILABLE', messages.uploadsUnavailable);
    return ok(avatarTicket(deps.cloudinary, req.user!.uid));
  });

  app.post<{ Body: SyncRequest }>(
    '/sync',
    {
      bodyLimit: 4 * 1024 * 1024,
      schema: {
        body: {
          type: 'object',
          additionalProperties: false,
          required: ['cursor'],
          properties: {
            cursor: { type: 'integer', minimum: 0 },
            cards: { type: 'array', maxItems: 1000, items: cardSchema, default: [] },
            bookmarks: { type: 'array', maxItems: 1000, items: bookmarkSchema, default: [] },
          },
        },
      },
    },
    async (req) => {
      const body = req.body;
      const res = await sync(deps.store, req.user!.uid, {
        cursor: body.cursor,
        cards: (body.cards ?? []).map((c) => ({ ...cardDefaults, ...c })),
        bookmarks: (body.bookmarks ?? []).map((b) => ({ ...bookmarkDefaults, ...b })),
      });
      return ok(res);
    },
  );
};
