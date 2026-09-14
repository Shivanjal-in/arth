import { EntryModel, FormModel, PhraseModel, SenseNotesModel, WiktionaryModel, toDictionaryEntry } from '../db/models/index.js';
import type { DictionaryEntry, WiktionaryExtract } from '../contracts.js';
import type { LemmaStore } from './lemma.js';
import type { PhraseStore } from './phrases.js';
import type { SenseNotesStore } from './context.js';
import type { StagingStore } from './ondemand.js';

export type Store = LemmaStore & PhraseStore & SenseNotesStore & StagingStore;

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
  async findStaged(lemma: string) {
    const doc = await WiktionaryModel.findById(lemma).lean();
    return doc ? { extract: doc.extract as WiktionaryExtract, freqRank: doc.freqRank } : null;
  },
  async saveGenerated(entry: DictionaryEntry, meta: { freqRank: number; model: string }) {
    await EntryModel.updateOne(
      { _id: entry.word },
      { $set: { ...entry, freqRank: meta.freqRank, tier: 'ondemand', model: meta.model, updatedAt: new Date() } },
      { upsert: true },
    );
  },
};
