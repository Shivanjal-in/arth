import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { resolveLemma, type LemmaStore } from '../src/services/lemma.js';
import type { DictionaryEntry } from '../src/contracts.js';

const entry = (word: string): DictionaryEntry => ({
  word,
  ipa: '',
  hindiPronunciation: '',
  senses: [{ index: 0, partOfSpeech: 'संज्ञा', meaning: 'x', definition: 'x', examples: [] }],
  synonyms: [],
  antonyms: [],
  forms: [],
  isPhrase: false,
});

function memStore(entries: string[], forms: Record<string, string>): LemmaStore & { reads: string[] } {
  const reads: string[] = [];
  const set = new Set(entries);
  return {
    reads,
    async findEntry(id) {
      reads.push(`entry:${id}`);
      return set.has(id) ? entry(id) : null;
    },
    async findFormLemma(form) {
      reads.push(`form:${form}`);
      return forms[form] ?? null;
    },
  };
}

describe('resolveLemma', () => {
  test('exact hit', async () => {
    const store = memStore(['fortune'], {});
    const r = await resolveLemma(store, 'fortune');
    assert.equal(r?.lemma, 'fortune');
    assert.equal(r?.via, 'exact');
    assert.deepEqual(store.reads, ['entry:fortune']);
  });

  test('inflected form → lemma', async () => {
    const store = memStore(['acknowledge'], { acknowledged: 'acknowledge' });
    const r = await resolveLemma(store, 'acknowledged');
    assert.equal(r?.lemma, 'acknowledge');
    assert.equal(r?.via, 'form');
  });

  test('lowercase fallback', async () => {
    const store = memStore(['fortune'], {});
    const r = await resolveLemma(store, 'Fortune');
    assert.equal(r?.lemma, 'fortune');
    assert.equal(r?.via, 'lowercase');
  });

  test('lowercase then form', async () => {
    const store = memStore(['wife'], { wives: 'wife' });
    const r = await resolveLemma(store, 'Wives');
    assert.equal(r?.lemma, 'wife');
    assert.equal(r?.via, 'lowercase-form');
  });

  test("strip trailing 's", async () => {
    const store = memStore(['darcy'], {});
    const r = await resolveLemma(store, "Darcy's");
    assert.equal(r?.lemma, 'darcy');
    assert.equal(r?.via, 'possessive');
  });

  test("possessive of an inflected form", async () => {
    const store = memStore(['daughter'], { daughters: 'daughter' });
    const r = await resolveLemma(store, "daughters's");
    assert.equal(r?.lemma, 'daughter');
    assert.equal(r?.via, 'possessive-form');
  });

  test('order: exact wins over form even when both exist', async () => {
    const store = memStore(['object', 'objects'], { objects: 'object' });
    const r = await resolveLemma(store, 'objects');
    assert.equal(r?.lemma, 'objects');
    assert.equal(r?.via, 'exact');
  });

  test('miss returns null and does not strip a lone apostrophe-s', async () => {
    const store = memStore([], {});
    assert.equal(await resolveLemma(store, 'zzzz'), null);
    assert.equal(await resolveLemma(store, "'s"), null);
    assert.equal(await resolveLemma(store, '   '), null);
  });

  test('a form pointing at a missing entry is a miss, not a crash', async () => {
    const store = memStore([], { orphans: 'orphan' });
    assert.equal(await resolveLemma(store, 'orphans'), null);
  });
});
