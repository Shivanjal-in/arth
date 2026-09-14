import { test, describe, after } from 'node:test';
import assert from 'node:assert/strict';
import { buildApp } from '../src/app.js';
import { appOptions, FakeLLM } from './fakes.js';

describe('rate limits per device', () => {
  test('lookups: 3rd call within a minute from the same device → 429 with a Hindi message', async () => {
    const app = buildApp({ ...appOptions(new FakeLLM({})), rateLimits: { lookups: 2, llm: 1, prefetch: 1 } });
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

  test('LLM budget: spent only on model calls; cache hits and single-sense words are free', async () => {
    const ok = JSON.stringify({ senseIndex: 0, meaning: 'x', note: '' });
    const llm = new FakeLLM({ context_result: [ok, ok] });
    const app = buildApp({ ...appOptions(llm), rateLimits: { lookups: 100, llm: 1, prefetch: 1 } });
    after(() => app.close());
    const h = { 'x-device-id': 'dev-C' };
    const c1 = await app.inject({ method: 'POST', url: '/v1/context', headers: h, payload: { word: 'single', sentence: 'A single man.' } });
    assert.equal(c1.statusCode, 200, 'first model call');
    const again = await app.inject({ method: 'POST', url: '/v1/context', headers: h, payload: { word: 'single', sentence: 'A single man.' } });
    assert.equal(again.statusCode, 200, 'cache hit is free');
    const one = await app.inject({ method: 'POST', url: '/v1/context', headers: h, payload: { word: 'wives', sentence: 'His wives.' } });
    assert.equal(one.statusCode, 200, 'single-sense bypass is free');
    const c2 = await app.inject({ method: 'POST', url: '/v1/context', headers: h, payload: { word: 'single', sentence: 'A single rose.' } });
    assert.equal(c2.statusCode, 429, 'second model call within the minute');
    assert.equal(c2.json().error.code, 'RATE_LIMITED');
    assert.equal(llm.requests.length, 1, 'the refused call never reached the model');
    const l = await app.inject({ method: 'GET', url: '/v1/lookup?word=fortune', headers: h });
    assert.equal(l.statusCode, 200, 'lookups are a separate bucket');
  });

  test('translate: refused before the stream opens, as an SSE error event', async () => {
    const r = JSON.stringify({ source: '', hindi: 'x', simpleMeaning: 'y', difficultWords: [] });
    const llm = new FakeLLM({ translation_result: [r, r] });
    const app = buildApp({ ...appOptions(llm), rateLimits: { lookups: 100, llm: 1, prefetch: 1 } });
    after(() => app.close());
    const h = { 'x-device-id': 'dev-T' };
    const t1 = await app.inject({ method: 'POST', url: '/v1/translate', headers: h, payload: { text: 'One.' } });
    assert.match(t1.body, /event: done/);
    const t2 = await app.inject({ method: 'POST', url: '/v1/translate', headers: h, payload: { text: 'Two.' } });
    assert.match(t2.body, /event: error/);
    assert.match(t2.body, /RATE_LIMITED/);
    const cached = await app.inject({ method: 'POST', url: '/v1/translate', headers: h, payload: { text: 'One.' } });
    assert.match(cached.body, /event: done/, 'cache replay is free');
  });
});

describe('prefetch budget', () => {
  test('X-Prefetch: 1 model calls have their own budget; the tap budget is untouched', async () => {
    const ok = JSON.stringify({ senseIndex: 0, meaning: 'x', note: '' });
    const llm = new FakeLLM({ context_result: [ok, ok, ok, ok] });
    const app = buildApp({ ...appOptions(llm), rateLimits: { lookups: 100, llm: 1, prefetch: 2 } });
    after(() => app.close());
    const h = { 'x-device-id': 'dev-P', 'x-prefetch': '1' };
    const p1 = await app.inject({ method: 'POST', url: '/v1/context', headers: h, payload: { word: 'single', sentence: 'A single man.' } });
    const p2 = await app.inject({ method: 'POST', url: '/v1/context', headers: h, payload: { word: 'single', sentence: 'A single rose.' } });
    const p3 = await app.inject({ method: 'POST', url: '/v1/context', headers: h, payload: { word: 'single', sentence: 'A single day.' } });
    assert.deepEqual([p1.statusCode, p2.statusCode, p3.statusCode], [200, 200, 429]);
    const tap = await app.inject({ method: 'POST', url: '/v1/context', headers: { 'x-device-id': 'dev-P' }, payload: { word: 'single', sentence: 'A single word.' } });
    assert.equal(tap.statusCode, 200);
  });
});
