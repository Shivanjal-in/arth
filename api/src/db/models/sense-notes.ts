import { Schema, model, type InferSchemaType } from 'mongoose';

/** Pre-written per-sense contrast notes (Phase 3 index-only context path). `_id` = lemma. */
const senseNotesSchema = new Schema(
  {
    _id: { type: String, required: true },
    notes: { type: [String], required: true },
    model: { type: String },
    updatedAt: { type: Date, default: () => new Date() },
  },
  { versionKey: false, collection: 'senseNotes' },
);

export type SenseNotesDoc = InferSchemaType<typeof senseNotesSchema>;
export const SenseNotesModel = model('SenseNotes', senseNotesSchema);
