import { Schema, model } from 'mongoose';

const status = { type: String, enum: ['live', 'hidden', 'removed'], default: 'live' };

/** A reader's published recap of a book. Cards are a snapshot at publish time. */
const deckSchema = new Schema(
  {
    _id: { type: String, required: true },
    owner: { type: String, required: true },
    title: { type: String, default: '' },
    bookTitle: { type: String, required: true },
    bookKey: { type: String, default: null },
    blurb: { type: String, default: '' },
    cards: [
      {
        _id: false,
        kind: { type: String, enum: ['idea', 'quote', 'word'], required: true },
        front: { type: String, required: true },
        back: { type: String, default: '' },
        note: { type: String, default: '' },
        location: { type: String, default: null },
      },
    ],
    cardCount: { type: Number, default: 0 },
    likes: { type: Number, default: 0 },
    saves: { type: Number, default: 0 },
    comments: { type: Number, default: 0 },
    /** likes + 2·saves, kept for sorting "popular". */
    score: { type: Number, default: 0 },
    status,
    reports: { type: Number, default: 0 },
    createdAt: { type: Number, required: true },
    updatedAt: { type: Number, required: true },
  },
  { versionKey: false, collection: 'decks' },
);
deckSchema.index({ status: 1, createdAt: -1 });
deckSchema.index({ status: 1, score: -1, createdAt: -1 });
deckSchema.index({ owner: 1, status: 1, createdAt: -1 });

const commentSchema = new Schema(
  {
    _id: { type: String, required: true },
    deckId: { type: String, required: true },
    owner: { type: String, required: true },
    parentId: { type: String, default: null },
    text: { type: String, required: true },
    status,
    reports: { type: Number, default: 0 },
    createdAt: { type: Number, required: true },
  },
  { versionKey: false, collection: 'comments' },
);
commentSchema.index({ deckId: 1, createdAt: 1 });

/** One document per (deck, reader): a like or a save. */
const reactionSchema = new Schema(
  {
    _id: { type: String, required: true }, // `${kind}:${deckId}:${uid}`
    kind: { type: String, enum: ['like', 'save'], required: true },
    deckId: { type: String, required: true },
    uid: { type: String, required: true },
    createdAt: { type: Number, required: true },
  },
  { versionKey: false, collection: 'reactions' },
);
reactionSchema.index({ uid: 1, kind: 1, deckId: 1 });

const reportSchema = new Schema(
  {
    _id: { type: String, required: true },
    kind: { type: String, enum: ['deck', 'comment'], required: true },
    targetId: { type: String, required: true },
    reporter: { type: String, required: true },
    reason: { type: String, default: '' },
    createdAt: { type: Number, required: true },
    resolvedAt: { type: Number, default: null },
    resolution: { type: String, enum: ['removed', 'dismissed', null], default: null },
  },
  { versionKey: false, collection: 'reports' },
);
reportSchema.index({ resolvedAt: 1, createdAt: 1 });
reportSchema.index({ kind: 1, targetId: 1, reporter: 1, resolvedAt: 1 });

export const DeckModel = model('Deck', deckSchema);
export const CommentModel = model('Comment', commentSchema);
export const ReactionModel = model('Reaction', reactionSchema);
export const ReportModel = model('Report', reportSchema);
