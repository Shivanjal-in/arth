import { Schema, model, type InferSchemaType } from 'mongoose';
import type { DictionaryEntry } from '../../contracts.js';

const pair = new Schema({ en: { type: String, required: true }, hi: { type: String, required: true } }, { _id: false });

const sense = new Schema(
  {
    index: { type: Number, required: true },
    partOfSpeech: { type: String, required: true },
    meaning: { type: String, required: true },
    definition: { type: String, required: true },
    examples: { type: [pair], default: [] },
  },
  { _id: false },
);

const form = new Schema(
  { en: { type: String, required: true }, label: { type: String, required: true }, hi: { type: String, required: true } },
  { _id: false },
);

/**
 * `_id` is the lemma itself, so `findById(word)` is a covered primary-key lookup
 * and the loader's upserts are idempotent.
 */
const entrySchema = new Schema(
  {
    _id: { type: String, required: true },
    word: { type: String, required: true },
    ipa: { type: String, default: '' },
    hindiPronunciation: { type: String, default: '' },
    senses: { type: [sense], required: true },
    synonyms: { type: [pair], default: [] },
    antonyms: { type: [pair], default: [] },
    forms: { type: [form], default: [] },
    isPhrase: { type: Boolean, default: false },
    freqRank: { type: Number, required: true },
    tier: { type: String, enum: ['top', 'tail'], required: false },
    updatedAt: { type: Date, default: () => new Date() },
  },
  { versionKey: false, collection: 'entries' },
);
entrySchema.index({ freqRank: 1 });

export type EntryDoc = InferSchemaType<typeof entrySchema>;
export const EntryModel = model('Entry', entrySchema);

/** Strip storage-only fields so the wire shape matches contracts/schemas/dictionary-entry.json exactly. */
export function toDictionaryEntry(doc: EntryDoc): DictionaryEntry {
  return {
    word: doc.word,
    ipa: doc.ipa,
    hindiPronunciation: doc.hindiPronunciation,
    senses: doc.senses.map((s) => ({
      index: s.index,
      partOfSpeech: s.partOfSpeech,
      meaning: s.meaning,
      definition: s.definition,
      examples: s.examples.map((e) => ({ en: e.en, hi: e.hi })),
    })),
    synonyms: doc.synonyms.map((p) => ({ en: p.en, hi: p.hi })),
    antonyms: doc.antonyms.map((p) => ({ en: p.en, hi: p.hi })),
    forms: doc.forms.map((f) => ({ en: f.en, label: f.label, hi: f.hi })),
    isPhrase: doc.isPhrase,
  };
}
