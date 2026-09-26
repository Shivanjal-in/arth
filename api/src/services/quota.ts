/**
 * AI usage limits by tier. Only AI answers count — a meaning "in this
 * sentence" (/context), a sentence translation (/translate), and a
 * dictionary entry generated live (/lookup of a staged word). Words already
 * in the dictionary, on the device or the server, are free.
 *
 *   free   100 uses, lifetime
 *   pro    1,000 uses per calendar month (UTC)
 *   super  unlimited
 *
 * A use is reserved atomically before the work and refunded if the answer
 * didn't need AI after all (single-sense words) or failed.
 */
import type { Tier, User } from './accounts.js';

/**
 * [free] is also the most one phone gets on the Free plan, whichever
 * accounts use it, and [freeAccountsPerDevice] how many Free accounts may
 * share a phone's allowance: signing in with a fresh email doesn't reset it.
 */
export type Limits = { free: number; proMonthly: number; freeAccountsPerDevice?: number };
export const defaultLimits: Limits = { free: 100, proMonthly: 1000, freeAccountsPerDevice: 3 };

/** How a tier is limited: a lifetime cap, a monthly cap, or none. */
export type Allowance = { period: 'lifetime'; max: number } | { period: 'month'; max: number } | { period: 'none' };

export function allowanceFor(tier: Tier, limits: Limits = defaultLimits): Allowance {
  switch (tier) {
    case 'free':
      return { period: 'lifetime', max: limits.free };
    case 'pro':
      return { period: 'month', max: limits.proMonthly };
    case 'super':
      return { period: 'none' };
  }
}

/** "2026-09": the UTC month a monthly allowance counts in. */
export const monthOf = (now: number) => new Date(now).toISOString().slice(0, 7);

/** Midnight UTC on the 1st of next month. */
export function nextMonthStart(now: number): number {
  const d = new Date(now);
  return Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + 1, 1);
}

/** What the app shows: used of limit, and when it resets. */
export type Usage = {
  used: number;
  /** Null when unlimited. */
  limit: number | null;
  period: Allowance['period'];
  /** Ms timestamp for a monthly allowance; null otherwise. */
  resetsAt: number | null;
  /** Set when the phone's Free allowance, not the account's, is the limit. */
  phone?: true;
};

export function usageOf(user: User, limits: Limits = defaultLimits, now = Date.now()): Usage {
  const a = allowanceFor(user.tier, limits);
  const monthUses = user.aiMonth === monthOf(now) ? user.aiMonthUses : 0;
  switch (a.period) {
    case 'lifetime':
      return { used: user.aiTotal, limit: a.max, period: 'lifetime', resetsAt: null };
    case 'month':
      return { used: monthUses, limit: a.max, period: 'month', resetsAt: nextMonthStart(now) };
    case 'none':
      return { used: monthUses, limit: null, period: 'none', resetsAt: null };
  }
}

export function hasRemaining(user: User, limits: Limits = defaultLimits, now = Date.now()): boolean {
  const u = usageOf(user, limits, now);
  return u.limit === null || u.used < u.limit;
}
