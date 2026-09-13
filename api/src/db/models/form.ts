import { Schema, model, type InferSchemaType } from 'mongoose';

/** Inflected form → lemma. `_id` is the form itself (lowercase). */
const formSchema = new Schema(
  {
    _id: { type: String, required: true },
    lemma: { type: String, required: true },
  },
  { versionKey: false, collection: 'forms' },
);

export type FormDoc = InferSchemaType<typeof formSchema>;
export const FormModel = model('Form', formSchema);
