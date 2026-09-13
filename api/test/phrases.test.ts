import { test, describe, after } from 'node:test';
import assert from 'node:assert/strict';
import { phraseWindows, matchPhrase } from '../src/services/phrases.js';
import { buildApp } from '../src/app.js';
import { appOptions, memStore, FakeLLM } from './fakes.js';

describe('phraseWindows', () => {
  const tokens = ['a', 'single', 'man', 'in', 'possession', 'of', 'a', 'good'];
  test('longest first, all covering the index, leftmost first within a length', () => {
    const w = phraseWindows(tokens, 3).map((x) => x.phrase);
    assert.deepEqual(w, [
      'a single man in',
      'single man in possession',
      'man in possession of',
      'in possession of a',
      'single man in',
      'man in possession',
      'in possession of',
      'man in',
      'in possession',
    ]);
  });
  test('edges and empty tokens', () => {
    assert.deepEqual(phraseWindows(tokens, 0).map((x) => x.phrase), ['a single man in', 'a single man', 'a single']);
    assert.deepEqual(phraseWindows(['in', 'want', '', 'of'], 1).map((x) => x.phrase), ['in want']);
    assert.deepEqual(phraseWindows(['x'], 0), []);
  });
});

describe('matchPhrase', () => {
  test('longest match wins', async () => {
    const store = memStore();
    const m = await matchPhrase(store, ['must', 'be', 'in', 'want', 'of', 'a', 'wife'], 3);
    assert.deepEqual(m, { phrase: 'in want of', lemma: 'in want of', start: 2, tokenCount: 3 });
  });
  test('no phrase → null', async () => {
    assert.equal(await matchPhrase(memStore(), ['a', 'good', 'fortune'], 1), null);
  });
});

describe('POST /v1/phrases/match', () => {
  const app = buildApp(appOptions(new FakeLLM({})));
  after(() => app.close());
  test('normalizes tokens and returns the contract shape', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/v1/phrases/match',
      payload: { tokens: ['Man', 'in', 'Possession,', 'of', 'a'], index: 2 },
    });
    assert.equal(res.statusCode, 200);
    assert.deepEqual(res.json().data, { phrase: 'in possession of', lemma: 'in possession of', start: 1, tokenCount: 3 });
  });
  test('miss → data null (not an error)', async () => {
    const res = await app.inject({ method: 'POST', url: '/v1/phrases/match', payload: { tokens: ['x', 'y'], index: 0 } });
    assert.equal(res.statusCode, 200);
    assert.equal(res.json().data, null);
  });
  test('index out of range → 400', async () => {
    const res = await app.inject({ method: 'POST', url: '/v1/phrases/match', payload: { tokens: ['x'], index: 4 } });
    assert.equal(res.statusCode, 400);
  });
});
