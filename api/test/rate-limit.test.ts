import { test, describe, after } from 'node:test';
import assert from 'node:assert/strict';
import { buildApp } from '../src/app.js';
import { appOptions, FakeLLM } from './fakes.js';

describe('rate limits per device', () => {
  test('lookups: 3rd call within a minute from the same device → 429 with a Hindi message', async () => {
    const app = buildApp({ ...appOptions(new FakeLLM({})), rateLimits: { lookups: 2, llm: 1 } });
    after(() => app.close());
    const h = { 'x-device-id': 'dev-A' };
    for (let i = 0; i < 2; i++) {
      const r = await app.inject({ method: 'GET', url: '/v1/lookup?word=fortune', headers: h });
      assert.equal(r.statusCode, 200);
    }
    const r3 = await app.inject({ method: 'GET', url: '/v1/lookup?word=fortune', headers: h });
    assert.equal(r3.statusCode, 429);
    assert.equal(r3.json().ok, false);
    assert.equal(r3.json().error.code, 'RATE_LIMITED');
    assert.match(r3.json().error.message, /\p{Script=Devanagari}/u);
    // Another device is unaffected.
    const other = await app.inject({ method: 'GET', url: '/v1/lookup?word=fortune', headers: { 'x-device-id': 'dev-B' } });
    assert.equal(other.statusCode, 200);
  });

  test('LLM bucket is separate from the lookup bucket', async () => {
    const llm = new FakeLLM({ context_result: [JSON.stringify({ senseIndex: 0, meaning: 'x', note: '' }), JSON.stringify({ senseIndex: 0, meaning: 'x', note: '' })] });
    const app = buildApp({ ...appOptions(llm), rateLimits: { lookups: 100, llm: 1 } });
    after(() => app.close());
    const h = { 'x-device-id': 'dev-C' };
    const c1 = await app.inject({ method: 'POST', url: '/v1/context', headers: h, payload: { word: 'single', sentence: 'A single man.' } });
    assert.equal(c1.statusCode, 200);
    const c2 = await app.inject({ method: 'POST', url: '/v1/context', headers: h, payload: { word: 'single', sentence: 'A single rose.' } });
    assert.equal(c2.statusCode, 429);
    const l = await app.inject({ method: 'GET', url: '/v1/lookup?word=fortune', headers: h });
    assert.equal(l.statusCode, 200, 'lookups still allowed');
  });
});
