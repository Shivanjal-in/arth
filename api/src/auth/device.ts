// The phone behind a request, for the Free plan's per-phone AI allowance.

import type { FastifyRequest } from 'fastify';
import type { Usage } from '../services/quota.js';

/** The app's device id (stable across reinstalls); none from other clients. */
export const deviceIdOf = (req: FastifyRequest) => (req.headers['x-device-id'] as string | undefined)?.trim().slice(0, 64) || null;

/**
 * Free-plan usage as the reader sees it: the account's count, or the phone's
 * when that's higher (another account on this phone used the allowance).
 */
export const withPhone = (usage: Usage, phoneUsed: number): Usage =>
  usage.period === 'lifetime' && phoneUsed > usage.used ? { ...usage, used: phoneUsed, phone: true } : usage;
