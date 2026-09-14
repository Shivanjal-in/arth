import { Schema, model, type InferSchemaType } from 'mongoose';

/** Inflected form → lemma. `_id` is the form itself (lowercase). */
const formSchema = new Schema(
  {
    _id: { type: String, required: true },
    lemma: { type: String, required: true },
    /** Points at a staged (not yet generated) lemma; the seed skips these. */
    staged: { type: Boolean },
  },
  { versionKey: false, collection: 'forms' },
);

export type FormDoc = InferSchemaType<typeof formSchema>;
export const FormModel = model('Form', formSchema);
