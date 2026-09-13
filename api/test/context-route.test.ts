import { test, describe, after } from 'node:test';
import assert from 'node:assert/strict';
import { buildApp } from '../src/app.js';
import { contextKey } from '../src/services/context.js';
import { appOptions, FakeLLM } from './fakes.js';

const PP = 'It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife.';
const good = JSON.stringify({ senseIndex: 0, meaning: 'अविवाहित', note: "यहाँ 'single' का मतलब अविवाहित है, अकेला नहीं।" });

describe('POST /v1/context (live)', () => {
  test('picks the sense, second identical call is a cache hit with no model call', async () => {
    const llm = new FakeLLM({ context_result: [good] });
    const opts = appOptions(llm);
    const app = buildApp(opts);
    after(() => app.close());

    const r1 = await app.inject({ method: 'POST', url: '/v1/context', payload: { word: 'single', sentence: PP } });
    assert.equal(r1.statusCode, 200);
    assert.equal(r1.json().data.meaning, 'अविवाहित');
    assert.match(r1.json().data.note, /अकेला नहीं/);
    assert.equal(llm.requests.length, 1);
    // Prompt: system + 3 gold pairs + the user message, senses numbered.
    const msgs = llm.requests[0]!.messages;
    assert.equal(msgs[0]!.role, 'system');
    assert.match(JSON.parse(msgs.at(-1)!.content).senses[0].meaning, /अविवाहित/);

    const r2 = await app.inject({
      method: 'POST',
      url: '/v1/context',
      payload: { word: '“Single”', sentence: 'It is a truth universally acknowledged, that a single man in pos-\nsession of a good fortune,   must be in want of a wife.' },
    });
    assert.equal(r2.statusCode, 200);
    assert.deepEqual(r2.json().data, r1.json().data);
    assert.equal(llm.requests.length, 1, 'normalization made the second call a cache hit');
    assert.ok((opts.cache as unknown as { map: Map<string, unknown> }).map.has(contextKey('single', PP)));

    const health = await app.inject({ method: 'GET', url: '/v1/health' });
    assert.deepEqual(health.json().data.cache.hits, 1);
  });

  test('single-sense entries skip the model entirely', async () => {
    const llm = new FakeLLM({});
    const app = buildApp(appOptions(llm));
    after(() => app.close());
    const r = await app.inject({ method: 'POST', url: '/v1/context', payload: { word: 'wives', sentence: 'His wives were many.' } });
    assert.equal(r.statusCode, 200);
    assert.equal(r.json().data.senseIndex, 0);
    assert.equal(r.json().data.meaning, 'पत्नी');
    assert.equal(llm.requests.length, 0);
  });

  test('out-of-range senseIndex falls back to 0', async () => {
    const llm = new FakeLLM({ context_result: [JSON.stringify({ senseIndex: 9, meaning: 'x', note: 'y' })] });
    const app = buildApp(appOptions(llm));
    after(() => app.close());
    const r = await app.inject({ method: 'POST', url: '/v1/context', payload: { word: 'single', sentence: 'A single rose.' } });
    assert.equal(r.statusCode, 200);
    assert.equal(r.json().data.senseIndex, 0);
  });

  test('invalid output is retried once with the error appended, then succeeds', async () => {
    const llm = new FakeLLM({ context_result: ['{"senseIndex": "one"}', good] });
    const app = buildApp(appOptions(llm));
    after(() => app.close());
    const r = await app.inject({ method: 'POST', url: '/v1/context', payload: { word: 'single', sentence: 'A single man.' } });
    assert.equal(r.statusCode, 200);
    assert.equal(llm.requests.length, 2);
    assert.match(llm.requests[1]!.messages.at(-1)!.content, /failed validation/);
  });

  test('invalid twice → 502, never a fabricated result', async () => {
    const llm = new FakeLLM({ context_result: ['{}', '{}'] });
    const app = buildApp(appOptions(llm));
    after(() => app.close());
    const r = await app.inject({ method: 'POST', url: '/v1/context', payload: { word: 'single', sentence: 'A single man.' } });
    assert.equal(r.statusCode, 502);
    assert.equal(r.json().error.code, 'UPSTREAM_FAILED');
  });

  test('unknown word → 404', async () => {
    const app = buildApp(appOptions(new FakeLLM({})));
    after(() => app.close());
    const r = await app.inject({ method: 'POST', url: '/v1/context', payload: { word: 'zzzq', sentence: 'zzzq here.' } });
    assert.equal(r.statusCode, 404);
  });
});

describe('POST /v1/context (index mode)', () => {
  test('model returns only an index; note comes from senseNotes; meaning from the entry', async () => {
    const llm = new FakeLLM({ context_index: ['{"senseIndex":1}'] });
    const app = buildApp(appOptions(llm, { single: ['एक वाला', 'शादी वाला: अकेला नहीं'] }));
    after(() => app.close());
    const r = await app.inject({ method: 'POST', url: '/v1/context', payload: { word: 'single', sentence: PP, mode: 'index' } });
    assert.equal(r.statusCode, 200);
    assert.deepEqual(r.json().data, { senseIndex: 1, meaning: 'एक, सिर्फ़ एक', note: 'शादी वाला: अकेला नहीं' });
    assert.equal(llm.requests[0]!.model, 'fake-index');
    assert.equal(llm.requests[0]!.maxOutputTokens, 256);
    assert.deepEqual(Object.keys(llm.requests[0]!.schema.properties as object), ['senseIndex']);
  });
});
