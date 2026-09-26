/**
 * Plans bought in the app stores, through RevenueCat.
 *
 * The app identifies each buyer by their Firebase uid (Purchases.logIn), so
 * RevenueCat's app_user_id is our uid. Two entitlements carry the plans:
 * `pro` and `super`. Whatever arrives by webhook, the subscriber's current
 * entitlements (GET /v1/subscribers/{uid}) are the truth: events can come
 * late, twice, or out of order, and the REST answer can't.
 */
import type { Tier } from '../services/accounts.js';

/** What we read from GET /v1/subscribers/{id}. */
export type RcSubscriber = {
  subscriber?: {
    entitlements?: Record<string, { expires_date?: string | null; grace_period_expires_date?: string | null } | undefined>;
  };
};

/** Active: no end date (lifetime), or ending later, or still in a billing grace period. */
function active(e: { expires_date?: string | null; grace_period_expires_date?: string | null } | undefined, now: number): boolean {
  if (!e) return false;
  if (e.expires_date == null) return true;
  if (Date.parse(e.expires_date) > now) return true;
  return e.grace_period_expires_date != null && Date.parse(e.grace_period_expires_date) > now;
}

/** The plan a subscriber's entitlements give right now. */
export function storeTierFrom(body: RcSubscriber, now = Date.now()): Tier {
  const ents = body.subscriber?.entitlements ?? {};
  if (active(ents.super, now)) return 'super';
  if (active(ents.pro, now)) return 'pro';
  return 'free';
}

export interface Billing {
  readonly enabled: boolean;
  /** The plan [uid] has bought and is paying for now. */
  storeTier(uid: string): Promise<Tier>;
}

export const disabledBilling: Billing = {
  enabled: false,
  async storeTier() {
    throw new Error('billing is not configured');
  },
};

/** RevenueCat's REST API with the project's secret key (never shipped in the app). */
export function revenueCatBilling(secretKey: string, fetchImpl: typeof fetch = fetch): Billing {
  return {
    enabled: true,
    async storeTier(uid) {
      const res = await fetchImpl(`https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(uid)}`, {
        headers: { authorization: `Bearer ${secretKey}`, accept: 'application/json' },
      });
      if (!res.ok) throw new Error(`RevenueCat ${res.status}`);
      return storeTierFrom((await res.json()) as RcSubscriber);
    },
  };
}
