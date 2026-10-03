import { Schema, model, type InferSchemaType } from 'mongoose';

/**
 * Resolved LLM results, keyed by content hash (see contracts/normalize.md).
 * No TTL: books don't change, so this is an asset that appreciates.
 */
const cacheSchema = new Schema(
  {
    _id: { type: String, required: true },
    kind: { type: String, enum: ['context', 'sentence', 'cover'], required: true },
    data: { type: Schema.Types.Mixed, required: true },
    hits: { type: Number, default: 0 },
    createdAt: { type: Date, default: () => new Date() },
  },
  { versionKey: false, collection: 'cache' },
);
cacheSchema.index({ kind: 1 });

export type CacheDoc = InferSchemaType<typeof cacheSchema>;
export const CacheModel = model('Cache', cacheSchema);
