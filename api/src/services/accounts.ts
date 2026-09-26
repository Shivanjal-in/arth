/**
 * Accounts and sync. A user is created on first sign-in from the verified
 * token; their flashcards and bookmarks sync as rows the app owns (UUID ids,
 * millisecond timestamps, deletes as tombstones).
 *
 * Sync is last-write-wins by the row's updatedAt. Every accepted write takes
 * the next number from a per-user sequence; a device pulls "everything after
 * the sequence number I last saw", so clock skew between devices never hides
 * a change — it only decides which of two edits to the same card wins.
 */
import type { Claims } from '../auth/verifier.js';
import type { Allowance } from './quota.js';

export type Role = 'user' | 'admin';
export type Tier = 'free' | 'pro' | 'super';

export type User = {
  uid: string;
  displayName: string;
  email: string | null;
  phone: string | null;
  photoUrl: string | null;
  bio: string;
  role: Role;
  tier: Tier;
  /** AI uses ever (the free allowance counts these). */
  aiTotal: number;
  /** The UTC month ("2026-09") [aiMonthUses] counts. */
  aiMonth: string | null;
  aiMonthUses: number;
  /** Push a daily nudge when cards are due for review. */
  reviewReminders: boolean;
  /** When the last review reminder went out (ms), so it's at most daily. */
  lastReviewNudgeAt: number | null;
  /** The allowance period ("lifetime" or a month) already warned as running low. */
  lowAiNoticeFor: string | null;
  /** Barred from publishing, commenting and reporting (admins decide). */
  banned: boolean;
  createdAt: number;
  updatedAt: number;
};

export type ProfilePatch = Partial<Pick<User, 'displayName' | 'bio' | 'photoUrl' | 'reviewReminders'>>;

/** A phone that can receive this user's notifications. */
export type PushDevice = { token: string; platform: 'android' | 'ios'; lang: Lang; updatedAt: number };

/** The interface language a phone uses; notifications are written in it. */
export type Lang = 'en' | 'hi';

/** Due cards per book, for a review reminder. */
export type DueSummary = { total: number; topBook: string | null };

export type CardRow = {
  id: string;
  kind: 'idea' | 'quote' | 'word';
  front: string;
  back: string;
  note: string;
  context: string | null;
  /** Content fingerprint of the book file, so a device can find its copy. */
  bookKey: string | null;
  bookTitle: string | null;
  page: number | null;
  block: number | null;
  location: string | null;
  box: number;
  dueAt: number | null;
  createdAt: number;
  updatedAt: number;
  deletedAt: number | null;
};

export type BookmarkRow = {
  id: string;
  bookKey: string | null;
  bookTitle: string | null;
  page: number;
  block: number | null;
  label: string | null;
  excerpt: string | null;
  createdAt: number;
  updatedAt: number;
  deletedAt: number | null;
};

/** The outcome of counting a use against a phone. */
export type DeviceCharge = { ok: true; used: number } | { ok: false; reason: 'exhausted' | 'accounts'; used: number };

export type SyncKind = 'cards' | 'bookmarks';
export type RowOf<K extends SyncKind> = K extends 'cards' ? CardRow : BookmarkRow;

/** Storage primitives; the sync rules live in the functions below. */
export interface AccountStore {
  findUser(uid: string): Promise<User | null>;
  /** Several users at once (authors on a page of decks). */
  findUsers(uids: string[]): Promise<Map<string, User>>;
  /** Admin search by name, email, phone or uid; newest first. */
  searchUsers(q: string, limit: number): Promise<User[]>;
  /** Users with at least one phone for notifications, [tier] if given (broadcasts). */
  usersWithDevices(tier?: Tier): Promise<string[]>;
  /**
   * Creates [user] unless one with that uid exists, atomically; returns
   * whichever is stored. A first sign-in fires several requests at once
   * (profile, sync) and they must all end up with the same user.
   */
  insertUser(user: User): Promise<User>;
  updateUser(uid: string, set: Partial<User>): Promise<User | null>;
  /**
   * Counts one AI use if [allowance] has room, atomically: a burst of
   * parallel requests can't overshoot the limit. The month counter restarts
   * when [month] changes. Null when there's no room (or no such user).
   */
  consumeAi(uid: string, month: string, allowance: Allowance): Promise<User | null>;
  /** Gives back a use counted by [consumeAi] in [month]. */
  refundAi(uid: string, month: string): Promise<void>;
  /**
   * Counts one Free-plan AI use against a phone, atomically, if it has room
   * (fewer than [max] uses) and [uid] is one of at most [maxAccounts]
   * accounts that have used it. Otherwise says why not.
   */
  consumeDeviceAi(deviceId: string, uid: string, max: number, maxAccounts: number): Promise<DeviceCharge>;
  /** Gives back a use counted by [consumeDeviceAi]. */
  refundDeviceAi(deviceId: string): Promise<void>;
  /** Free-plan AI uses counted against a phone so far. */
  deviceAiUsed(deviceId: string): Promise<number>;
  /**
   * Saves [device] for [uid]. A token belongs to one phone, so it's first
   * removed from any other user (a phone that changed accounts).
   */
  addPushDevice(uid: string, device: PushDevice): Promise<void>;
  removePushToken(uid: string, token: string): Promise<void>;
  pushDevices(uid: string): Promise<PushDevice[]>;
  /** Forgets tokens FCM reports as gone, whoever they belonged to. */
  removeDeadTokens(tokens: string[]): Promise<void>;
  /** Users with review reminders on, a device, and no reminder since [before]. */
  reminderCandidates(before: number): Promise<User[]>;
  /** [uid]'s cards due at [now] (live cards only), and the book with most. */
  dueCards(uid: string, now: number): Promise<DueSummary>;
  /** Reserves [n] consecutive sequence numbers for [uid]; returns the first. */
  reserveSeqs(uid: string, n: number): Promise<number>;
  /**
   * Writes [row] if no row with its id exists for this user, or the stored
   * one is older. Never touches another user's row with the same id.
   * True when written.
   */
  upsertIfNewer<K extends SyncKind>(kind: K, uid: string, row: RowOf<K>, seq: number): Promise<boolean>;
  /** Rows with seq > [after], ascending by seq, at most [limit]. */
  changedSince<K extends SyncKind>(kind: K, uid: string, after: number, limit: number): Promise<{ row: RowOf<K>; seq: number }[]>;
}

/** The user for a verified sign-in, created the first time. */
export async function signIn(store: AccountStore, claims: Claims, now = Date.now()): Promise<User> {
  const existing = await store.findUser(claims.uid);
  if (existing) {
    // Fill in what the provider knows that we don't (e.g. a phone user
    // who later links Google). Never overwrite what the user set.
    const set: Partial<User> = {};
    if (!existing.email && claims.email) set.email = claims.email;
    if (!existing.phone && claims.phone) set.phone = claims.phone;
    if (!existing.displayName && claims.name) set.displayName = claims.name;
    if (Object.keys(set).length === 0) return existing;
    return (await store.updateUser(claims.uid, { ...set, updatedAt: now })) ?? existing;
  }
  return store.insertUser({
    uid: claims.uid,
    displayName: claims.name ?? '',
    email: claims.email ?? null,
    phone: claims.phone ?? null,
    // The provider's picture (Google) until they upload their own.
    photoUrl: claims.picture ?? null,
    bio: '',
    role: 'user',
    tier: 'free',
    aiTotal: 0,
    aiMonth: null,
    aiMonthUses: 0,
    reviewReminders: true,
    lastReviewNudgeAt: null,
    lowAiNoticeFor: null,
    banned: false,
    createdAt: now,
    updatedAt: now,
  });
}

export async function updateProfile(store: AccountStore, uid: string, patch: ProfilePatch, now = Date.now()): Promise<User | null> {
  const set: Partial<User> = { updatedAt: now };
  if (patch.displayName !== undefined) set.displayName = patch.displayName.trim();
  if (patch.bio !== undefined) set.bio = patch.bio.trim();
  if (patch.photoUrl !== undefined) set.photoUrl = patch.photoUrl;
  if (patch.reviewReminders !== undefined) set.reviewReminders = patch.reviewReminders;
  return store.updateUser(uid, set);
}

export type SyncRequest = { cursor: number; cards: CardRow[]; bookmarks: BookmarkRow[] };
export type SyncResponse = { cursor: number; more: boolean; cards: CardRow[]; bookmarks: BookmarkRow[]; accepted: number };

export const PULL_LIMIT = 500;

/**
 * Applies the device's changes, then returns what changed on the server
 * since its cursor — minus the rows it just sent, which it already has.
 */
export async function sync(store: AccountStore, uid: string, req: SyncRequest, limit = PULL_LIMIT): Promise<SyncResponse> {
  let accepted = 0;
  const pushed = new Set<string>();
  let seq = req.cards.length + req.bookmarks.length > 0 ? await store.reserveSeqs(uid, req.cards.length + req.bookmarks.length) : 0;
  const push = async <K extends SyncKind>(kind: K, rows: RowOf<K>[]) => {
    for (const row of rows) {
      pushed.add(`${kind}:${row.id}:${row.updatedAt}`);
      if (await store.upsertIfNewer(kind, uid, row, seq++)) accepted++;
    }
  };
  await push('cards', req.cards);
  await push('bookmarks', req.bookmarks);

  // One page across both collections, in sequence order: fetch a page of
  // each, merge, and stop at the limit so the cursor never skips a row.
  const cards = await store.changedSince('cards', uid, req.cursor, limit + 1);
  const bookmarks = await store.changedSince('bookmarks', uid, req.cursor, limit + 1);
  const merged = [
    ...cards.map((c) => ({ kind: 'cards' as const, ...c })),
    ...bookmarks.map((b) => ({ kind: 'bookmarks' as const, ...b })),
  ].sort((a, b) => a.seq - b.seq);
  const page = merged.slice(0, limit);
  const out: SyncResponse = {
    cursor: page.at(-1)?.seq ?? req.cursor,
    more: merged.length > limit,
    cards: [],
    bookmarks: [],
    accepted,
  };
  for (const item of page) {
    if (pushed.has(`${item.kind}:${item.row.id}:${item.row.updatedAt}`)) continue;
    if (item.kind === 'cards') out.cards.push(item.row as CardRow);
    else out.bookmarks.push(item.row as BookmarkRow);
  }
  return out;
}

/** In-memory store, for tests. */
export function memoryAccountStore(): AccountStore & { users: Map<string, User>; devices: Map<string, PushDevice[]> } {
  const users = new Map<string, User>();
  const phones = new Map<string, { used: number; accounts: string[] }>();
  const devices = new Map<string, PushDevice[]>();
  const seqs = new Map<string, number>();
  const rows = { cards: new Map<string, { owner: string; row: CardRow; seq: number }>(), bookmarks: new Map<string, { owner: string; row: BookmarkRow; seq: number }>() };
  return {
    users,
    devices,
    async addPushDevice(uid, device) {
      for (const [other, list] of devices) devices.set(other, list.filter((d) => d.token !== device.token));
      devices.set(uid, [...(devices.get(uid) ?? []), device]);
    },
    async removePushToken(uid, token) {
      devices.set(uid, (devices.get(uid) ?? []).filter((d) => d.token !== token));
    },
    async pushDevices(uid) {
      return devices.get(uid) ?? [];
    },
    async removeDeadTokens(tokens) {
      const dead = new Set(tokens);
      for (const [uid, list] of devices) devices.set(uid, list.filter((d) => !dead.has(d.token)));
    },
    async reminderCandidates(before) {
      return [...users.values()].filter(
        (u) => u.reviewReminders && (devices.get(u.uid)?.length ?? 0) > 0 && (u.lastReviewNudgeAt ?? 0) < before,
      );
    },
    async dueCards(uid, now) {
      const byBook = new Map<string, number>();
      let total = 0;
      for (const r of rows.cards.values()) {
        if (r.owner !== uid || r.row.deletedAt !== null || (r.row.dueAt !== null && r.row.dueAt > now)) continue;
        total++;
        const book = r.row.bookTitle ?? '';
        byBook.set(book, (byBook.get(book) ?? 0) + 1);
      }
      const top = [...byBook.entries()].sort((a, b) => b[1] - a[1])[0]?.[0] || null;
      return { total, topBook: top };
    },
    async findUser(uid) {
      return users.get(uid) ?? null;
    },
    async findUsers(uids) {
      return new Map(uids.flatMap((u) => (users.has(u) ? [[u, users.get(u)!] as const] : [])));
    },
    async searchUsers(q, limit) {
      const needle = q.trim().toLowerCase();
      return [...users.values()]
        .filter((u) => !needle || [u.uid, u.displayName, u.email ?? '', u.phone ?? ''].some((f) => f.toLowerCase().includes(needle)))
        .sort((a, b) => b.createdAt - a.createdAt)
        .slice(0, limit);
    },
    async usersWithDevices(tier) {
      return [...users.values()].filter((u) => (devices.get(u.uid)?.length ?? 0) > 0 && (!tier || u.tier === tier)).map((u) => u.uid);
    },
    async insertUser(user) {
      const existing = users.get(user.uid);
      if (existing) return existing;
      users.set(user.uid, user);
      return user;
    },
    async updateUser(uid, set) {
      const u = users.get(uid);
      if (!u) return null;
      const next = { ...u, ...set };
      users.set(uid, next);
      return next;
    },
    async consumeAi(uid, month, allowance) {
      const u = users.get(uid);
      if (!u) return null;
      const monthUses = u.aiMonth === month ? u.aiMonthUses : 0;
      if (allowance.period === 'lifetime' && u.aiTotal >= allowance.max) return null;
      if (allowance.period === 'month' && monthUses >= allowance.max) return null;
      const next = { ...u, aiTotal: u.aiTotal + 1, aiMonth: month, aiMonthUses: monthUses + 1 };
      users.set(uid, next);
      return next;
    },
    async refundAi(uid, month) {
      const u = users.get(uid);
      if (!u) return;
      users.set(uid, {
        ...u,
        aiTotal: Math.max(0, u.aiTotal - 1),
        aiMonthUses: u.aiMonth === month ? Math.max(0, u.aiMonthUses - 1) : u.aiMonthUses,
      });
    },
    async consumeDeviceAi(deviceId, uid, max, maxAccounts) {
      const d = phones.get(deviceId) ?? { used: 0, accounts: [] };
      if (!d.accounts.includes(uid) && d.accounts.length >= maxAccounts) return { ok: false, reason: 'accounts', used: d.used };
      if (d.used >= max) return { ok: false, reason: 'exhausted', used: d.used };
      const next = { used: d.used + 1, accounts: d.accounts.includes(uid) ? d.accounts : [...d.accounts, uid] };
      phones.set(deviceId, next);
      return { ok: true, used: next.used };
    },
    async refundDeviceAi(deviceId) {
      const d = phones.get(deviceId);
      if (d && d.used > 0) phones.set(deviceId, { ...d, used: d.used - 1 });
    },
    async deviceAiUsed(deviceId) {
      return phones.get(deviceId)?.used ?? 0;
    },
    async reserveSeqs(uid, n) {
      const first = (seqs.get(uid) ?? 0) + 1;
      seqs.set(uid, first + n - 1);
      return first;
    },
    async upsertIfNewer(kind, uid, row, seq) {
      const table = rows[kind] as Map<string, { owner: string; row: typeof row; seq: number }>;
      const cur = table.get(row.id);
      if (cur && (cur.owner !== uid || cur.row.updatedAt >= row.updatedAt)) return false;
      table.set(row.id, { owner: uid, row, seq });
      return true;
    },
    async changedSince(kind, uid, after, limit) {
      const table = rows[kind] as Map<string, { owner: string; row: never; seq: number }>;
      return [...table.values()]
        .filter((r) => r.owner === uid && r.seq > after)
        .sort((a, b) => a.seq - b.seq)
        .slice(0, limit)
        .map(({ row, seq }) => ({ row, seq }));
    },
  };
}
