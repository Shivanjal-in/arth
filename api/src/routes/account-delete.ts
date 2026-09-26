/**
 * DELETE /v1/me: the reader deletes their account, from Profile.
 *
 * Gone: their recaps, comments, likes, saves and reports; their synced cards
 * and bookmarks; their profile photo; their account; and their Firebase
 * sign-in. Kept, as the Privacy Policy says: a phone's Free-plan AI count,
 * no longer linked to them. A store subscription isn't touched; the app
 * tells them to cancel it in the store.
 */
import type { FastifyPluginAsync } from 'fastify';
import { ok } from '../lib/envelope.js';
import { destroyAvatar } from '../lib/cloudinary.js';
import { authenticate, type AccountDeps } from './account.js';
import type { CommunityStore } from '../services/community.js';

/** Removes a Firebase sign-in (firebase-admin in production). */
export type LoginRemover = (uid: string) => Promise<void>;

export type AccountDeleteDeps = AccountDeps & { community: CommunityStore; removeLogin?: LoginRemover | undefined };

export const accountDeleteRoutes: FastifyPluginAsync<AccountDeleteDeps> = async (app, deps) => {
  app.delete('/me', async (req) => {
    const user = await authenticate(req, deps);
    await deps.community.forgetUser(user.uid);
    await deps.store.deleteUser(user.uid);
    // The rest is outside our database: try each, and log what fails rather
    // than leave the reader half-deleted with an error.
    const cloud = deps.cloudinary;
    if (cloud && user.photoUrl?.startsWith(`https://res.cloudinary.com/${cloud.cloudName}/`)) {
      await destroyAvatar(cloud, user.uid).catch((err: unknown) => req.log.warn({ err, uid: user.uid }, 'avatar delete failed'));
    }
    if (deps.removeLogin) await deps.removeLogin(user.uid).catch((err: unknown) => req.log.warn({ err, uid: user.uid }, 'firebase user delete failed'));
    req.log.info({ uid: user.uid }, 'account deleted');
    return ok({ deleted: true });
  });
};
