import { BookmarkModel, FlashcardModel, PhoneModel, UserModel } from '../db/models/account.js';
import type { AccountStore, BookmarkRow, CardRow, SyncKind, User } from './accounts.js';

const models = { cards: FlashcardModel, bookmarks: BookmarkModel } as const;

function toUser(doc: Record<string, unknown>): User {
  return {
    uid: doc._id as string,
    displayName: (doc.displayName as string) ?? '',
    email: (doc.email as string | null) ?? null,
    phone: (doc.phone as string | null) ?? null,
    photoUrl: (doc.photoUrl as string | null) ?? null,
    bio: (doc.bio as string) ?? '',
    role: (doc.role as User['role']) ?? 'user',
    tier: (doc.tier as User['tier']) ?? 'free',
    aiTotal: (doc.aiTotal as number) ?? 0,
    aiMonth: (doc.aiMonth as string | null) ?? null,
    aiMonthUses: (doc.aiMonthUses as number) ?? 0,
    reviewReminders: (doc.reviewReminders as boolean | undefined) ?? true,
    lastReviewNudgeAt: (doc.lastReviewNudgeAt as number | null) ?? null,
    lowAiNoticeFor: (doc.lowAiNoticeFor as string | null) ?? null,
    banned: (doc.banned as boolean | undefined) ?? false,
    createdAt: doc.createdAt as number,
    updatedAt: doc.updatedAt as number,
  };
}

/** A stored row back to its wire shape: `_id` → `id`, bookkeeping dropped. */
function toRow(doc: Record<string, unknown>): CardRow | BookmarkRow {
  const { _id, owner: _o, seq: _s, ...rest } = doc;
  return { id: _id as string, ...rest } as CardRow | BookmarkRow;
}

export const mongoAccountStore: AccountStore = {
  async findUser(uid) {
    const doc = await UserModel.findById(uid).lean();
    return doc ? toUser(doc) : null;
  },
  async findUsers(uids) {
    const docs = await UserModel.find({ _id: { $in: uids } }).lean();
    return new Map(docs.map((d) => [d._id as string, toUser(d as Record<string, unknown>)] as const));
  },
  async searchUsers(q, limit) {
    const needle = q.trim();
    const re = new RegExp(needle.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i');
    const filter = needle ? { $or: [{ _id: needle }, { displayName: re }, { email: re }, { phone: re }] } : {};
    const docs = await UserModel.find(filter).sort({ createdAt: -1 }).limit(limit).lean();
    return docs.map((d) => toUser(d as Record<string, unknown>));
  },
  async usersWithDevices(tier) {
    const docs = await UserModel.find({ 'pushDevices.0': { $exists: true }, ...(tier ? { tier } : {}) }, { _id: 1 }).lean();
    return docs.map((d) => d._id as string);
  },
  async insertUser(user) {
    const { uid, ...rest } = user;
    // Insert-if-absent in one step: concurrent first requests (profile and
    // sync right after sign-in) can't collide on _id.
    const doc = await UserModel.findOneAndUpdate(
      { _id: uid },
      { $setOnInsert: { ...rest, seq: 0 } },
      { upsert: true, new: true },
    ).lean();
    return toUser(doc!);
  },
  async updateUser(uid, set) {
    const { uid: _u, ...fields } = set;
    const doc = await UserModel.findByIdAndUpdate(uid, { $set: fields }, { new: true }).lean();
    return doc ? toUser(doc) : null;
  },
  async consumeAi(uid, month, allowance) {
    // The month's count, as it will be before this use: 0 in a new month.
    const monthUses = { $cond: [{ $eq: ['$aiMonth', month] }, '$aiMonthUses', 0] };
    const room =
      allowance.period === 'lifetime'
        ? { aiTotal: { $lt: allowance.max } }
        : allowance.period === 'month'
          ? { $or: [{ aiMonth: { $ne: month } }, { aiMonthUses: { $lt: allowance.max } }] }
          : {};
    const doc = await UserModel.findOneAndUpdate(
      { _id: uid, ...room },
      [{ $set: { aiTotal: { $add: [{ $ifNull: ['$aiTotal', 0] }, 1] }, aiMonthUses: { $add: [monthUses, 1] }, aiMonth: month } }],
      { new: true },
    ).lean();
    return doc ? toUser(doc) : null;
  },
  async refundAi(uid, month) {
    await UserModel.updateOne({ _id: uid, aiTotal: { $gt: 0 } }, { $inc: { aiTotal: -1 } });
    await UserModel.updateOne({ _id: uid, aiMonth: month, aiMonthUses: { $gt: 0 } }, { $inc: { aiMonthUses: -1 } });
  },
  async consumeDeviceAi(deviceId, uid, max, maxAccounts) {
    const now = Date.now();
    await PhoneModel.updateOne({ _id: deviceId }, { $setOnInsert: { aiUsed: 0, accounts: [], updatedAt: now } }, { upsert: true });
    // One atomic step: room left, and this account is known or there's a
    // free slot for it. Parallel taps can't overshoot either limit.
    const doc = await PhoneModel.findOneAndUpdate(
      {
        _id: deviceId,
        aiUsed: { $lt: max },
        $or: [{ accounts: uid }, { $expr: { $lt: [{ $size: '$accounts' }, maxAccounts] } }],
      },
      { $inc: { aiUsed: 1 }, $addToSet: { accounts: uid }, $set: { updatedAt: now } },
      { new: true },
    ).lean();
    if (doc) return { ok: true, used: doc.aiUsed };
    const cur = await PhoneModel.findById(deviceId).lean();
    const used = cur?.aiUsed ?? 0;
    const known = cur?.accounts.includes(uid) ?? false;
    return { ok: false, reason: !known && (cur?.accounts.length ?? 0) >= maxAccounts ? 'accounts' : 'exhausted', used };
  },
  async refundDeviceAi(deviceId) {
    await PhoneModel.updateOne({ _id: deviceId, aiUsed: { $gt: 0 } }, { $inc: { aiUsed: -1 } });
  },
  async deviceAiUsed(deviceId) {
    return (await PhoneModel.findById(deviceId, { aiUsed: 1 }).lean())?.aiUsed ?? 0;
  },
  async addPushDevice(uid, device) {
    await UserModel.updateMany({ _id: { $ne: uid } }, { $pull: { pushDevices: { token: device.token } } });
    await UserModel.updateOne({ _id: uid }, { $pull: { pushDevices: { token: device.token } } });
    // Keep the ten most recent: old phones fall off rather than piling up.
    await UserModel.updateOne({ _id: uid }, { $push: { pushDevices: { $each: [device], $slice: -10 } } });
  },
  async removePushToken(uid, token) {
    await UserModel.updateOne({ _id: uid }, { $pull: { pushDevices: { token } } });
  },
  async pushDevices(uid) {
    const doc = await UserModel.findById(uid, { pushDevices: 1 }).lean();
    return (doc?.pushDevices ?? []).map((d) => ({
      token: d.token,
      platform: (d.platform as 'android' | 'ios' | undefined) ?? 'android',
      lang: ((d as { lang?: string }).lang === 'hi' ? 'hi' : 'en') as 'en' | 'hi',
      updatedAt: d.updatedAt ?? 0,
    }));
  },
  async removeDeadTokens(tokens) {
    if (tokens.length === 0) return;
    await UserModel.updateMany({ 'pushDevices.token': { $in: tokens } }, { $pull: { pushDevices: { token: { $in: tokens } } } });
  },
  async reminderCandidates(before) {
    const docs = await UserModel.find({
      reviewReminders: { $ne: false },
      'pushDevices.0': { $exists: true },
      $or: [{ lastReviewNudgeAt: null }, { lastReviewNudgeAt: { $lt: before } }],
    }).lean();
    return docs.map((d) => toUser(d as Record<string, unknown>));
  },
  async dueCards(uid, now) {
    const rows = await FlashcardModel.aggregate<{ _id: string | null; n: number }>([
      { $match: { owner: uid, deletedAt: null, $or: [{ dueAt: null }, { dueAt: { $lte: now } }] } },
      { $group: { _id: '$bookTitle', n: { $sum: 1 } } },
      { $sort: { n: -1 } },
    ]);
    return { total: rows.reduce((a, r) => a + r.n, 0), topBook: rows[0]?._id ?? null };
  },
  async reserveSeqs(uid, n) {
    const doc = await UserModel.findByIdAndUpdate(uid, { $inc: { seq: n } }, { new: true, projection: { seq: 1 } }).lean();
    if (!doc) throw new Error(`no user ${uid}`);
    return doc.seq - n + 1;
  },
  async upsertIfNewer(kind: SyncKind, uid, row, seq) {
    const { id, ...fields } = row;
    try {
      // Matches only this user's older copy. If a newer copy (or another
      // user's row with this id) exists, the upsert's insert collides on
      // _id: that's "not written", not an error.
      const res = await (models[kind] as typeof FlashcardModel).updateOne(
        { _id: id, owner: uid, updatedAt: { $lt: row.updatedAt } },
        { $set: { ...fields, owner: uid, seq } },
        { upsert: true },
      );
      return res.modifiedCount + res.upsertedCount > 0;
    } catch (err) {
      if ((err as { code?: number }).code === 11000) return false;
      throw err;
    }
  },
  async changedSince(kind, uid, after, limit) {
    const docs = await (models[kind] as typeof FlashcardModel)
      .find({ owner: uid, seq: { $gt: after } })
      .sort({ seq: 1 })
      .limit(limit)
      .lean();
    return docs.map((d) => ({ row: toRow(d as Record<string, unknown>), seq: d.seq })) as never;
  },
};
