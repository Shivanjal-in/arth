import { Schema, model, type InferSchemaType } from 'mongoose';

/** Multi-word phrase → lemma. `_id` is the space-joined normalized phrase. */
const phraseSchema = new Schema(
  {
    _id: { type: String, required: true },
    lemma: { type: String, required: true },
    firstToken: { type: String, required: true },
    tokenCount: { type: Number, required: true, min: 2, max: 4 },
  },
  { versionKey: false, collection: 'phrases' },
);
phraseSchema.index({ firstToken: 1 });

export type PhraseDoc = InferSchemaType<typeof phraseSchema>;
export const PhraseModel = model('Phrase', phraseSchema);
