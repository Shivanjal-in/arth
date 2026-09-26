import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildApp } from '../src/app.js';
import { appOptions, FakeLLM } from './fakes.js';

test('the Terms of Use and Privacy Policy are public web pages', async () => {
  const app = buildApp(appOptions(new FakeLLM({})));
  for (const [url, heading] of [['/legal/terms', 'Terms of Use'], ['/legal/privacy', 'Privacy Policy'], ['/legal/delete-account', 'Delete your Arth account']] as const) {
    const r = await app.inject({ method: 'GET', url });
    assert.equal(r.statusCode, 200);
    assert.match(r.headers['content-type'] as string, /text\/html/);
    assert.match(r.body, new RegExp(`<h1>${heading}</h1>`));
  }
  const terms = (await app.inject({ method: 'GET', url: '/legal/terms' })).body;
  assert.match(terms, /renew automatically/, 'the auto-renewal terms the stores require');
  assert.match(terms, /free trial/);
  await app.close();
});
