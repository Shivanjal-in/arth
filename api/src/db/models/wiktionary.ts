import { Schema, model, type InferSchemaType } from 'mongoose';

/**
 * Staged Wiktionary senses (English side only) for lemmas beyond the generated
 * dictionary — the input for on-demand Hindi generation. `_id` = lemma.
 * Written by pipeline/08_stage.py.
 */
const wiktionarySchema = new Schema(
  {
    _id: { type: String, required: true },
    freqRank: { type: Number, required: true },
    extract: { type: Schema.Types.Mixed, required: true },
    updatedAt: { type: Date },
  },
  { versionKey: false, collection: 'wiktionary' },
);
wiktionarySchema.index({ freqRank: 1 });

export type WiktionaryDoc = InferSchemaType<typeof wiktionarySchema>;
export const WiktionaryModel = model('Wiktionary', wiktionarySchema);
