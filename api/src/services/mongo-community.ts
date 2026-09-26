import { CommentModel, DeckModel, ReactionModel, ReportModel } from '../db/models/community.js';
import type { Comment, CommunityStore, Deck, Report } from './community.js';

const toDeck = ({ _id, score: _s, ...d }: Record<string, unknown>) => ({ id: _id, ...d }) as Deck;
const toComment = ({ _id, ...c }: Record<string, unknown>) => ({ id: _id, ...c }) as Comment;
const toReport = ({ _id, ...r }: Record<string, unknown>) => ({ id: _id, ...r }) as Report;

const escape = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

async function refreshScore(id: string) {
  await DeckModel.updateOne({ _id: id }, [{ $set: { score: { $add: ['$likes', { $multiply: [2, '$saves'] }] } } }]);
}

export const mongoCommunityStore: CommunityStore = {
  async insertDeck(deck) {
    const { id, ...rest } = deck;
    await DeckModel.create({ _id: id, ...rest, score: 0 });
  },
  async updateDeck(id, set) {
    const { id: _i, ...fields } = set;
    const doc = await DeckModel.findByIdAndUpdate(id, { $set: fields }, { new: true }).lean();
    return doc ? toDeck(doc as Record<string, unknown>) : null;
  },
  async findDeck(id) {
    const doc = await DeckModel.findById(id).lean();
    return doc ? toDeck(doc as Record<string, unknown>) : null;
  },
  async listDecks({ sort, q, owner, page, limit }) {
    const filter: Record<string, unknown> = { status: 'live' };
    if (owner) filter.owner = owner;
    const needle = q?.trim();
    if (needle) {
      const re = new RegExp(escape(needle), 'i');
      filter.$or = [{ bookTitle: re }, { title: re }];
    }
    const docs = await DeckModel.find(filter, { cards: { $slice: 3 } })
      .sort(sort === 'popular' ? { score: -1, createdAt: -1 } : { createdAt: -1 })
      .skip(page * limit)
      .limit(limit)
      .lean();
    return docs.map((d) => toDeck(d as Record<string, unknown>));
  },
  async forgetUser(uid) {
    const gone = (await DeckModel.find({ owner: uid }, { _id: 1 }).lean()).map((d) => d._id);
    const onGone = (await CommentModel.find({ deckId: { $in: gone } }, { _id: 1 }).lean()).map((c) => c._id);
    const mine = await CommentModel.find({ owner: uid, deckId: { $nin: gone } }, { _id: 1, deckId: 1, status: 1 }).lean();
    const mineIds = mine.map((c) => c._id);
    // Their comments on others' recaps: the counts go down, replies stay.
    for (const c of mine) {
      if (c.status === 'live') await DeckModel.updateOne({ _id: c.deckId, comments: { $gt: 0 } }, { $inc: { comments: -1 } });
    }
    await CommentModel.updateMany({ parentId: { $in: mineIds } }, { $set: { parentId: null } });
    // Their likes and saves on others' recaps: the counts go down.
    const reactions = await ReactionModel.find({ uid, deckId: { $nin: gone } }).lean();
    for (const r of reactions) {
      const field = r.kind === 'like' ? 'likes' : 'saves';
      await DeckModel.updateOne({ _id: r.deckId, [field]: { $gt: 0 } }, { $inc: { [field]: -1 } });
      await refreshScore(r.deckId);
    }
    await ReportModel.deleteMany({ $or: [{ reporter: uid }, { targetId: { $in: [...gone, ...onGone, ...mineIds] } }] });
    await ReactionModel.deleteMany({ $or: [{ uid }, { deckId: { $in: gone } }] });
    await CommentModel.deleteMany({ $or: [{ owner: uid }, { deckId: { $in: gone } }] });
    await DeckModel.deleteMany({ _id: { $in: gone } });
  },
  async toggleLike(deckId, uid) {
    const _id = `like:${deckId}:${uid}`;
    const removed = await ReactionModel.deleteOne({ _id });
    const liked = removed.deletedCount === 0;
    if (liked) await ReactionModel.create({ _id, kind: 'like', deckId, uid, createdAt: Date.now() });
    const doc = await DeckModel.findByIdAndUpdate(deckId, { $inc: { likes: liked ? 1 : -1 } }, { new: true, projection: { likes: 1 } }).lean();
    await refreshScore(deckId);
    return { liked, likes: doc?.likes ?? 0 };
  },
  async likedBy(uid, deckIds) {
    const docs = await ReactionModel.find({ uid, kind: 'like', deckId: { $in: deckIds } }, { deckId: 1 }).lean();
    return new Set(docs.map((d) => d.deckId));
  },
  async addSave(deckId, uid) {
    const res = await ReactionModel.updateOne(
      { _id: `save:${deckId}:${uid}` },
      { $setOnInsert: { kind: 'save', deckId, uid, createdAt: Date.now() } },
      { upsert: true },
    );
    const doc =
      res.upsertedCount > 0
        ? await DeckModel.findByIdAndUpdate(deckId, { $inc: { saves: 1 } }, { new: true, projection: { saves: 1 } }).lean()
        : await DeckModel.findById(deckId, { saves: 1 }).lean();
    if (res.upsertedCount > 0) await refreshScore(deckId);
    return doc?.saves ?? 0;
  },
  async insertComment(comment) {
    const { id, ...rest } = comment;
    await CommentModel.create({ _id: id, ...rest });
  },
  async updateComment(id, set) {
    const { id: _i, ...fields } = set;
    const doc = await CommentModel.findByIdAndUpdate(id, { $set: fields }, { new: true }).lean();
    return doc ? toComment(doc as Record<string, unknown>) : null;
  },
  async findComment(id) {
    const doc = await CommentModel.findById(id).lean();
    return doc ? toComment(doc as Record<string, unknown>) : null;
  },
  async listComments(deckId) {
    const docs = await CommentModel.find({ deckId }).sort({ createdAt: 1 }).limit(1000).lean();
    return docs.map((d) => toComment(d as Record<string, unknown>));
  },
  async addReport(report) {
    const { id, ...rest } = report;
    const existing = await ReportModel.findOne({ kind: report.kind, targetId: report.targetId, reporter: report.reporter, resolvedAt: null }, { _id: 1 }).lean();
    if (!existing) await ReportModel.create({ _id: id, ...rest });
    const open = await ReportModel.countDocuments({ kind: report.kind, targetId: report.targetId, resolvedAt: null });
    return { created: !existing, open };
  },
  async openReports(limit) {
    const docs = await ReportModel.find({ resolvedAt: null }).sort({ createdAt: 1 }).limit(limit).lean();
    return docs.map((d) => toReport(d as Record<string, unknown>));
  },
  async findReport(id) {
    const doc = await ReportModel.findById(id).lean();
    return doc ? toReport(doc as Record<string, unknown>) : null;
  },
  async resolveReports(kind, targetId, resolution, at) {
    await ReportModel.updateMany({ kind, targetId, resolvedAt: null }, { $set: { resolvedAt: at, resolution } });
  },
};
