import assert from 'node:assert/strict';
import { beforeEach, describe, test } from 'node:test';
import { buildApp } from '../src/app.js';
import { FakeLLM, appOptions } from './fakes.js';
import { clearCoverMisses, titleScore } from '../src/services/cover.js';

const docs = (...d: Array<{ title: string; cover_i?: number; edition_count?: number }>) => ({ docs: d });

function app(response: unknown, calls: string[] = []) {
  return buildApp({
    ...appOptions(new FakeLLM({})),
    coverFetch: async (url) => {
      calls.push(url);
      if (response instanceof Error) throw response;
      return response;
    },
  });
}

describe('titleScore', () => {
  test('same book scores high, a different one low', () => {
    assert.ok(titleScore('crime and punishment', 'Crime and Punishment') > 0.95);
    assert.ok(titleScore('crime and punishment', 'Crime and Punishment (Penguin Classics)') > 0.7);
    assert.ok(titleScore('crime and punishment', 'The Punishment of Virtue') < 0.7);
    assert.ok(titleScore('lighthouse', 'Moby Dick') < 0.1);
  });
  test('file-name noise is ignored', () => {
    assert.ok(titleScore('Crime And Punishment pdf free download', 'Crime and Punishment') > 0.95);
  });
});

describe('GET /v1/cover', () => {
  beforeEach(clearCoverMisses);

  test('returns the best match with a cover', async () => {
    const a = app(docs({ title: 'Crime and Punishment', cover_i: 111, edition_count: 500 }, { title: 'Crime', cover_i: 222 }));
    const r = await a.inject({ method: 'GET', url: '/v1/cover?title=crime+and+punishment&author=dostoevsky' });
    assert.equal(r.statusCode, 200);
    assert.equal(r.json().data.url, 'https://covers.openlibrary.org/b/id/111-M.jpg');
    await a.close();
  });

  test('skips editions without a cover, and refuses a poor match', async () => {
    const a = app(docs({ title: 'Crime and Punishment' }, { title: 'The Punishment of Virtue', cover_i: 9 }));
    const r = await a.inject({ method: 'GET', url: '/v1/cover?title=crime+and+punishment' });
    assert.equal(r.statusCode, 200);
    assert.equal(r.json().data.url, null);
    await a.close();
  });

  test('a hit is remembered; Open Library is asked once', async () => {
    const calls: string[] = [];
    const a = app(docs({ title: 'Walden', cover_i: 5 }), calls);
    for (let i = 0; i < 3; i++) assert.equal((await a.inject({ method: 'GET', url: '/v1/cover?title=Walden' })).json().data.url, 'https://covers.openlibrary.org/b/id/5-M.jpg');
    assert.equal(calls.length, 1);
    await a.close();
  });

  test('a miss is remembered for the day; an outage is not', async () => {
    const calls: string[] = [];
    const none = app(docs(), calls);
    await none.inject({ method: 'GET', url: '/v1/cover?title=An+Unknown+Title' });
    await none.inject({ method: 'GET', url: '/v1/cover?title=An+Unknown+Title' });
    assert.equal(calls.length, 1);
    await none.close();

    const down = app(new Error('boom'), calls);
    const r = await down.inject({ method: 'GET', url: '/v1/cover?title=Another+Title' });
    assert.equal(r.statusCode, 200);
    assert.equal(r.json().data.url, null);
    await down.inject({ method: 'GET', url: '/v1/cover?title=Another+Title' });
    assert.equal(calls.length, 3, 'the outage was retried');
    await down.close();
  });

  test('rejects a missing or silly title', async () => {
    const a = app(docs());
    assert.equal((await a.inject({ method: 'GET', url: '/v1/cover' })).statusCode, 400);
    assert.equal((await a.inject({ method: 'GET', url: '/v1/cover?title=x' })).statusCode, 400);
    await a.close();
  });
});
