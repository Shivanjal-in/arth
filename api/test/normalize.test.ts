import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { contextKey, normalizeSentence, normalizeWord, sentenceKey } from '../src/normalize.js';

type Vector =
  | { id: string; kind: 'sentence' | 'word'; input: string; expected: string }
  | { id: string; kind: 'key'; keyKind: 'context'; word: string; sentence: string; expected: string }
  | { id: string; kind: 'key'; keyKind: 'sentence'; text: string; expected: string };

const vectorsPath = fileURLToPath(new URL('../../contracts/normalize-vectors.json', import.meta.url));
const { vectors } = JSON.parse(readFileSync(vectorsPath, 'utf8')) as { version: number; vectors: Vector[] };

assert.ok(vectors.length >= 40, 'vector file looks truncated');

for (const v of vectors) {
  test(`normalize vector ${v.id}`, () => {
    switch (v.kind) {
      case 'sentence':
        assert.equal(normalizeSentence(v.input), v.expected);
        break;
      case 'word':
        assert.equal(normalizeWord(v.input), v.expected);
        break;
      case 'key':
        if (v.keyKind === 'context') assert.equal(contextKey(v.word, v.sentence), v.expected);
        else assert.equal(sentenceKey(v.text), v.expected);
        break;
    }
  });
}
