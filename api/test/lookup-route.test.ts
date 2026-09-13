import { test, describe, after } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { buildApp } from '../src/app.js';
import type { LemmaStore } from '../src/services/lemma.js';
import { validate, type DictionaryEntry } from '../src/contracts.js';

type SeedFile = {
  entries: (DictionaryEntry & { freqRank: number })[];
  forms: { form: string; lemma: string }[];
};
const seed = JSON.parse(
  readFileSync(fileURLToPath(new URL('../seed/seed.json', import.meta.url)), 'utf8'),
) as SeedFile;

const entries = new Map(seed.entries.map((e) => [e.word, e]));
const forms = new Map(seed.forms.map((f) => [f.form, f.lemma]));

const store: LemmaStore = {
  async findEntry(id) {
    const e = entries.get(id);
    if (!e) return null;
    const { freqRank: _r, ...wire } = e;
    return wire;
  },
  async findFormLemma(form) {
    return forms.get(form) ?? null;
  },
};

const app = buildApp({ logLevel: 'silent', store });
after(() => app.close());

describe('seed file', () => {
  test('every seed entry validates against contracts/schemas/dictionary-entry.json', () => {
    for (const e of seed.entries) {
      const { freqRank: _r, ...wire } = e;
      assert.ok(validate.dictionaryEntry(wire), `${e.word}: ${JSON.stringify(validate.dictionaryEntry.errors)}`);
    }
    assert.ok(seed.entries.length >= 20);
  });

  test('sense indexes are 0..n-1 in order', () => {
    for (const e of seed.entries) {
      e.senses.forEach((s, i) => assert.equal(s.index, i, `${e.word} sense ${i}`));
    }
  });

  test('every form points at an existing entry', () => {
    for (const f of seed.forms) assert.ok(entries.has(f.lemma), `${f.form} → ${f.lemma}`);
  });
});

describe('GET /v1/lookup', () => {
  test('returns a valid DictionaryEntry in the envelope', async () => {
    const res = await app.inject({ method: 'GET', url: '/v1/lookup?word=fortune' });
    assert.equal(res.statusCode, 200);
    const body = res.json();
    assert.equal(body.ok, true);
    assert.equal(body.data.word, 'fortune');
    assert.ok(validate.dictionaryEntry(body.data));
    assert.equal(body.data.senses[0].meaning, 'धन-दौलत');
  });

  test('resolves an inflected form', async () => {
    const res = await app.inject({ method: 'GET', url: '/v1/lookup?word=acknowledged' });
    assert.equal(res.statusCode, 200);
    assert.equal(res.json().data.word, 'acknowledge');
  });

  test('resolves a possessive', async () => {
    const res = await app.inject({ method: 'GET', url: "/v1/lookup?word=wife's" });
    assert.equal(res.statusCode, 200);
    assert.equal(res.json().data.word, 'wife');
  });

  test('miss → 404 error envelope with empty suggestions', async () => {
    const res = await app.inject({ method: 'GET', url: '/v1/lookup?word=zzzzq' });
    assert.equal(res.statusCode, 404);
    const body = res.json();
    assert.equal(body.ok, false);
    assert.equal(body.error.code, 'NOT_FOUND');
    assert.deepEqual(body.error.suggestions, []);
    assert.match(body.error.message, /शब्द/);
  });

  test('missing word → 400', async () => {
    const res = await app.inject({ method: 'GET', url: '/v1/lookup' });
    assert.equal(res.statusCode, 400);
    assert.equal(res.json().error.code, 'BAD_REQUEST');
  });
});
