import { test } from 'node:test';
import assert from 'node:assert/strict';
import { completedTopLevelFields } from '../src/llm/partial-json.js';

const full =
  '{"source":"It is.","hindi":"यह है।","simpleMeaning":"बस \\"यही\\" है।","difficultWords":[{"en":"is","hi":"है"}]}';

test('fields appear in order as the buffer grows, never partially', () => {
  const seen: string[][] = [];
  for (let i = 1; i <= full.length; i++) {
    seen.push([...completedTopLevelFields(full.slice(0, i)).keys()]);
  }
  // Monotonic: each prefix's key set is a prefix of the next.
  for (let i = 1; i < seen.length; i++) {
    assert.deepEqual(seen[i]!.slice(0, seen[i - 1]!.length), seen[i - 1]);
  }
  assert.deepEqual(seen.at(-1), ['source', 'hindi', 'simpleMeaning', 'difficultWords']);
});

test('values are exact, including escaped quotes and nested arrays', () => {
  const f = completedTopLevelFields(full);
  assert.equal(f.get('simpleMeaning'), 'बस "यही" है।');
  assert.deepEqual(f.get('difficultWords'), [{ en: 'is', hi: 'है' }]);
});

test('an open string is not reported', () => {
  const f = completedTopLevelFields('{"source":"It is.","hindi":"यह');
  assert.deepEqual([...f.keys()], ['source']);
});

test('garbage is tolerated', () => {
  assert.equal(completedTopLevelFields('').size, 0);
  assert.equal(completedTopLevelFields('nope').size, 0);
  assert.equal(completedTopLevelFields('{"a":').size, 0);
});
