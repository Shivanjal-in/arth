import { after, describe, test } from 'node:test';
import assert from 'node:assert/strict';
import { gunzipSync } from 'node:zlib';
import { buildApp } from '../src/app.js';
import { parseRange, SeedFileCache, type SeedSource } from '../src/services/seed-file.js';
import { appOptions, FakeLLM } from './fakes.js';

/** A dictionary whose version and lines the test changes. */
function fakeSource(rows: number) {
  const s = { version: 'v1', rows, builds: 0, versionChecks: 0 };
  const source: SeedSource = {
    async version() {
      s.versionChecks++;
      return s.version;
    },
    async *lines() {
      s.builds++;
      yield JSON.stringify({ t: 'meta', entries: s.rows });
      for (let i = 1; i <= s.rows; i++) yield JSON.stringify({ t: 'entry', word: `word${i}`, freqRank: i });
      yield JSON.stringify({ t: 'end' });
    },
  };
  return { s, source };
}

const tick = () => new Promise((r) => setImmediate(r));

describe('SeedFileCache', () => {
  test('builds once, even for requests that arrive together', async () => {
    const { s, source } = fakeSource(50);
    const cache = new SeedFileCache(source);
    const [a, b] = await Promise.all([cache.current(), cache.current()]);
    assert.equal(s.builds, 1);
    assert.equal(a, b);
    const lines = gunzipSync(a.body).toString().trim().split('\n');
    assert.equal(lines.length, 52);
    assert.deepEqual(JSON.parse(lines.at(-1)!), { t: 'end' });
  });

  test('rebuilds when the version changes, serving the old file meanwhile', async () => {
    let now = 0;
    const { s, source } = fakeSource(10);
    const cache = new SeedFileCache(source, { recheckMs: 1000, now: () => now });
    const first = await cache.current();

    now = 500; // too soon to check
    assert.equal(await cache.current(), first);
    assert.equal(s.versionChecks, 1);

    now = 1500; // checked, unchanged
    assert.equal(await cache.current(), first);
    await tick();
    assert.equal(s.versionChecks, 2);
    assert.equal(s.builds, 1);

    now = 3000;
    s.version = 'v2';
    s.rows = 20;
    assert.equal(await cache.current(), first, 'answers at once with the file it has');
    await new Promise((r) => setTimeout(r, 20));
    const second = await cache.current();
    assert.notEqual(second.etag, first.etag);
    assert.equal(second.version, 'v2');
  });

  test('rebuilds a day-old file even when the version looks the same', async () => {
    let now = 0;
    const { s, source } = fakeSource(5);
    const cache = new SeedFileCache(source, { recheckMs: 1000, maxAgeMs: 10_000, now: () => now });
    await cache.current();
    now = 11_000;
    await cache.current();
    await new Promise((r) => setTimeout(r, 20));
    assert.equal(s.builds, 2);
  });

  test('a failed first build fails the request, and the next request tries again', async () => {
    const { source } = fakeSource(5);
    let fail = true;
    const cache = new SeedFileCache({
      version: () => (fail ? Promise.reject(new Error('mongo down')) : source.version()),
      lines: () => source.lines(),
    });
    await assert.rejects(cache.current(), /mongo down/);
    fail = false;
    assert.ok((await cache.current()).body.length > 0);
  });
});

describe('parseRange', () => {
  test('the ranges a resuming phone sends, and the odd ones', () => {
    assert.deepEqual(parseRange('bytes=100-', 1000), { start: 100, end: 999 });
    assert.deepEqual(parseRange('bytes=0-9', 1000), { start: 0, end: 9 });
    assert.deepEqual(parseRange('bytes=990-5000', 1000), { start: 990, end: 999 });
    assert.deepEqual(parseRange('bytes=-10', 1000), { start: 990, end: 999 });
    assert.deepEqual(parseRange('bytes=0-9,20-29', 1000), { start: 0, end: 9 }, 'first range only');
    assert.equal(parseRange('bytes=1000-', 1000), 'unsatisfiable');
    assert.equal(parseRange('bytes=9-3', 1000), 'unsatisfiable');
    assert.equal(parseRange(undefined, 1000), null);
    assert.equal(parseRange('items=0-9', 1000), null);
    assert.equal(parseRange('bytes=-', 1000), null);
  });
});

describe('GET /v1/seed/file', () => {
  const { source } = fakeSource(2000);
  const app = buildApp({ ...appOptions(new FakeLLM({})), seedFile: new SeedFileCache(source) });
  after(() => app.close());

  test('the whole file, with what a resume needs', async () => {
    const r = await app.inject({ method: 'GET', url: '/v1/seed/file' });
    assert.equal(r.statusCode, 200);
    assert.equal(r.headers['content-type'], 'application/gzip');
    assert.equal(r.headers['accept-ranges'], 'bytes');
    assert.equal(Number(r.headers['content-length']), r.rawPayload.length);
    assert.match(String(r.headers['etag']), /^"[0-9a-f]{20}"$/);
    assert.equal(gunzipSync(r.rawPayload).toString().trim().split('\n').length, 2002);
  });

  test('a resume gets the rest of the same file', async () => {
    const whole = await app.inject({ method: 'GET', url: '/v1/seed/file' });
    const etag = String(whole.headers['etag']);
    const r = await app.inject({ method: 'GET', url: '/v1/seed/file', headers: { range: 'bytes=1000-', 'if-range': etag } });
    assert.equal(r.statusCode, 206);
    assert.equal(r.headers['content-range'], `bytes 1000-${whole.rawPayload.length - 1}/${whole.rawPayload.length}`);
    assert.deepEqual(Buffer.concat([whole.rawPayload.subarray(0, 1000), r.rawPayload]), whole.rawPayload);
  });

  test('a resume of a file that has since changed starts over', async () => {
    const r = await app.inject({ method: 'GET', url: '/v1/seed/file', headers: { range: 'bytes=1000-', 'if-range': '"stale"' } });
    assert.equal(r.statusCode, 200);
    assert.equal(Number(r.headers['content-length']), r.rawPayload.length);
  });

  test('past the end: 416 with the real size', async () => {
    const whole = await app.inject({ method: 'GET', url: '/v1/seed/file' });
    const r = await app.inject({ method: 'GET', url: '/v1/seed/file', headers: { range: `bytes=${whole.rawPayload.length}-` } });
    assert.equal(r.statusCode, 416);
    assert.equal(r.headers['content-range'], `bytes */${whole.rawPayload.length}`);
  });

  test('a server without a file says so, and the phone falls back to the stream', async () => {
    const bare = buildApp(appOptions(new FakeLLM({})));
    after(() => bare.close());
    const r = await bare.inject({ method: 'GET', url: '/v1/seed/file' });
    assert.equal(r.statusCode, 404);
    assert.equal(r.json().error.code, 'NOT_FOUND');
  });
});
