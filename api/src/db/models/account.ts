import { Schema, model, type InferSchemaType } from 'mongoose';

/** One person, keyed by Firebase uid. `seq` numbers their synced writes. */
const userSchema = new Schema(
  {
    _id: { type: String, required: true },
    displayName: { type: String, default: '' },
    email: { type: String, default: null },
    phone: { type: String, default: null },
    photoUrl: { type: String, default: null },
    bio: { type: String, default: '' },
    role: { type: String, enum: ['user', 'admin'], default: 'user' },
    tier: { type: String, enum: ['free', 'pro', 'super'], default: 'free' },
    aiTotal: { type: Number, default: 0 },
    aiMonth: { type: String, default: null },
    aiMonthUses: { type: Number, default: 0 },
    reviewReminders: { type: Boolean, default: true },
    lastReviewNudgeAt: { type: Number, default: null },
    lowAiNoticeFor: { type: String, default: null },
    banned: { type: Boolean, default: false },
    /** Phones that receive this user's notifications (FCM registration tokens). */
    pushDevices: {
      type: [
        {
          _id: false,
          token: { type: String, required: true },
          platform: { type: String, enum: ['android', 'ios'] },
          lang: { type: String, enum: ['en', 'hi'], default: 'en' },
          updatedAt: Number,
        },
      ],
      default: [],
    },
    seq: { type: Number, default: 0 },
    createdAt: { type: Number, required: true },
    updatedAt: { type: Number, required: true },
  },
  { versionKey: false, collection: 'users' },
);
userSchema.index({ email: 1 }, { sparse: true });
userSchema.index({ 'pushDevices.token': 1 });

export type UserDoc = InferSchemaType<typeof userSchema>;
export const UserModel = model('User', userSchema);

/** Fields every synced row has: its owner and where it sits in their sequence. */
const synced = {
  _id: { type: String, required: true },
  owner: { type: String, required: true },
  seq: { type: Number, required: true },
  createdAt: { type: Number, required: true },
  updatedAt: { type: Number, required: true },
  deletedAt: { type: Number, default: null },
};

const flashcardSchema = new Schema(
  {
    ...synced,
    kind: { type: String, enum: ['idea', 'quote', 'word'], required: true },
    front: { type: String, required: true },
    back: { type: String, default: '' },
    note: { type: String, default: '' },
    context: { type: String, default: null },
    bookKey: { type: String, default: null },
    bookTitle: { type: String, default: null },
    page: { type: Number, default: null },
    block: { type: Number, default: null },
    location: { type: String, default: null },
    box: { type: Number, default: 0 },
    dueAt: { type: Number, default: null },
  },
  { versionKey: false, collection: 'flashcards' },
);
flashcardSchema.index({ owner: 1, seq: 1 });
flashcardSchema.index({ owner: 1, deletedAt: 1, dueAt: 1 });

const bookmarkSchema = new Schema(
  {
    ...synced,
    bookKey: { type: String, default: null },
    bookTitle: { type: String, default: null },
    page: { type: Number, required: true },
    block: { type: Number, default: null },
    label: { type: String, default: null },
    excerpt: { type: String, default: null },
  },
  { versionKey: false, collection: 'bookmarks' },
);
bookmarkSchema.index({ owner: 1, seq: 1 });

export const FlashcardModel = model('Flashcard', flashcardSchema);
export const BookmarkModel = model('Bookmark', bookmarkSchema);

/**
 * A phone's Free-plan AI uses, whichever accounts made them, and those
 * accounts: signing in with a new email doesn't reset the allowance.
 * Keyed by the app's device id (stable across reinstalls).
 */
const phoneSchema = new Schema(
  {
    _id: { type: String, required: true },
    aiUsed: { type: Number, default: 0 },
    accounts: { type: [String], default: [] },
    updatedAt: { type: Number, required: true },
  },
  { versionKey: false, collection: 'phones' },
);

export const PhoneModel = model('Phone', phoneSchema);
