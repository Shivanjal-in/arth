/**
 * Loads seed/seed.json into Mongo with idempotent upserts.
 * Same bulkWrite pattern the Python loader (pipeline/05_load.py) uses.
 *
 *   npm run seed
 */
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { loadConfig } from '../src/config.js';
import { connectMongo, disconnectMongo } from '../src/db/connect.js';
import { EntryModel, FormModel, PhraseModel } from '../src/db/models/index.js';
import { validate, formatErrors, type DictionaryEntry } from '../src/contracts.js';
import { normalizeWord, normalizeSentence } from '../src/normalize.js';

type SeedFile = {
  entries: (DictionaryEntry & { freqRank: number })[];
  forms: { form: string; lemma: string }[];
  phrases: { phrase: string; lemma: string }[];
};

const seedPath = fileURLToPath(new URL('../seed/seed.json', import.meta.url));
const seed = JSON.parse(readFileSync(seedPath, 'utf8')) as SeedFile;

// Validate every entry against the contract before touching the DB.
let bad = 0;
for (const e of seed.entries) {
  const { freqRank: _freqRank, ...wire } = e;
  if (!validate.dictionaryEntry(wire)) {
    bad++;
    console.error(`invalid entry "${e.word}": ${formatErrors(validate.dictionaryEntry.errors)}`);
  }
}
if (bad > 0) {
  console.error(`${bad} invalid entries; aborting`);
  process.exit(1);
}

const config = loadConfig();
await connectMongo(config.MONGODB_URI);

const now = new Date();
const BATCH = 1000;

async function upsertInBatches<T>(label: string, items: T[], toOp: (item: T) => object, model: { bulkWrite: (ops: never[], opts: object) => Promise<unknown> }) {
  let done = 0;
  for (let i = 0; i < items.length; i += BATCH) {
    const ops = items.slice(i, i + BATCH).map(toOp) as never[];
    await model.bulkWrite(ops, { ordered: false });
    done += ops.length;
  }
  console.log(`${label}: upserted ${done}`);
}

await upsertInBatches(
  'entries',
  seed.entries,
  (e) => {
    const id = e.isPhrase ? normalizeSentence(e.word).toLowerCase() : normalizeWord(e.word);
    return { updateOne: { filter: { _id: id }, update: { $set: { ...e, word: id, updatedAt: now } }, upsert: true } };
  },
  EntryModel,
);

await upsertInBatches(
  'forms',
  seed.forms,
  (f) => ({ updateOne: { filter: { _id: normalizeWord(f.form) }, update: { $set: { lemma: f.lemma } }, upsert: true } }),
  FormModel,
);

await upsertInBatches(
  'phrases',
  seed.phrases,
  (p) => {
    const id = normalizeSentence(p.phrase).toLowerCase();
    const tokens = id.split(' ');
    return {
      updateOne: {
        filter: { _id: id },
        update: { $set: { lemma: p.lemma, firstToken: tokens[0], tokenCount: tokens.length } },
        upsert: true,
      },
    };
  },
  PhraseModel,
);

// Make sure the secondary indexes from the schemas exist.
await Promise.all([EntryModel.syncIndexes(), FormModel.syncIndexes(), PhraseModel.syncIndexes()]);
console.log('indexes synced');

await disconnectMongo();
