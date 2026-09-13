import { EntryModel, FormModel, PhraseModel, SenseNotesModel, toDictionaryEntry } from '../db/models/index.js';
import type { DictionaryEntry } from '../contracts.js';
import type { LemmaStore } from './lemma.js';
import type { PhraseStore } from './phrases.js';
import type { SenseNotesStore } from './context.js';

export type Store = LemmaStore & PhraseStore & SenseNotesStore;

export const mongoStore: Store = {
  async findEntry(id: string): Promise<DictionaryEntry | null> {
    const doc = await EntryModel.findById(id).lean();
    return doc ? toDictionaryEntry(doc) : null;
  },
  async findFormLemma(form: string): Promise<string | null> {
    const doc = await FormModel.findById(form).lean();
    return doc?.lemma ?? null;
  },
  async findPhraseLemma(phrase: string): Promise<string | null> {
    const doc = await PhraseModel.findById(phrase).lean();
    return doc?.lemma ?? null;
  },
  async findSenseNotes(word: string): Promise<string[] | null> {
    const doc = await SenseNotesModel.findById(word).lean();
    return doc?.notes ?? null;
  },
};
