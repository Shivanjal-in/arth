import { EntryModel, FormModel, toDictionaryEntry } from '../db/models/index.js';
import type { DictionaryEntry } from '../contracts.js';
import type { LemmaStore } from './lemma.js';

export const mongoLemmaStore: LemmaStore = {
  async findEntry(id: string): Promise<DictionaryEntry | null> {
    const doc = await EntryModel.findById(id).lean();
    return doc ? toDictionaryEntry(doc) : null;
  },
  async findFormLemma(form: string): Promise<string | null> {
    const doc = await FormModel.findById(form).lean();
    return doc?.lemma ?? null;
  },
};
