import { describe, test } from 'node:test';
import assert from 'node:assert/strict';
import { seedEntryFilter } from '../src/routes/seed.js';

describe('seed entry filter', () => {
  const since = new Date('2026-09-01T00:00:00Z');

  test('first launch: the whole slice', () => {
    assert.deepEqual(seedEntryFilter({ maxRank: 21_450 }), { freqRank: { $lte: 21_450 } });
  });

  test('daily delta: changed entries, still inside the slice', () => {
    assert.deepEqual(seedEntryFilter({ since, maxRank: 21_450 }), { updatedAt: { $gt: since }, freqRank: { $lte: 21_450 } });
  });

  test('catching up after SEED_LIMIT grows: only the new range', () => {
    assert.deepEqual(seedEntryFilter({ afterRank: 21_450, maxRank: 60_000 }), { freqRank: { $lte: 60_000, $gt: 21_450 } });
  });

  test('a dictionary smaller than the slice: no upper bound', () => {
    assert.deepEqual(seedEntryFilter({ maxRank: null }), {});
    assert.deepEqual(seedEntryFilter({ afterRank: 100, maxRank: null }), { freqRank: { $gt: 100 } });
  });
});
