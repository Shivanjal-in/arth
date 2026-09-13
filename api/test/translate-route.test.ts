import { test, describe, after } from 'node:test';
import assert from 'node:assert/strict';
import { buildApp } from '../src/app.js';
import { appOptions, FakeLLM } from './fakes.js';

const result = {
  source: 'ignored by server',
  hindi: 'यह एक सच है।',
  simpleMeaning: 'बात साफ़ है।',
  difficultWords: [{ en: 'truth', hi: 'सच' }],
};

function parseSse(body: string): { event: string; data: unknown }[] {
  return body
    .split('\n\n')
    .filter((b) => b.trim())
    .map((block) => {
      const event = /^event: (.*)$/m.exec(block)![1]!;
      const data = JSON.parse(/^data: (.*)$/m.exec(block)![1]!);
      return { event, data };
    });
}

describe('POST /v1/translate', () => {
  test('streams hindi → simpleMeaning → difficultWords → done, then replays from cache', async () => {
    const llm = new FakeLLM({ translation_result: [JSON.stringify(result)] });
    const app = buildApp(appOptions(llm));
    after(() => app.close());

    const r1 = await app.inject({ method: 'POST', url: '/v1/translate', payload: { text: ' It is a  truth. ' } });
    assert.equal(r1.statusCode, 200);
    assert.match(r1.headers['content-type'] as string, /text\/event-stream/);
    const ev = parseSse(r1.body);
    assert.deepEqual(ev.map((e) => e.event), ['hindi', 'simpleMeaning', 'difficultWords', 'done']);
    assert.deepEqual(ev[0]!.data, { hindi: 'यह एक सच है।' });
    const done = ev[3]!.data as { source: string };
    assert.equal(done.source, 'It is a truth.', 'source is the normalized input, not the model echo');

    const r2 = await app.inject({ method: 'POST', url: '/v1/translate', payload: { text: 'It is a truth.' } });
    assert.deepEqual(parseSse(r2.body).map((e) => e.event), ['hindi', 'simpleMeaning', 'difficultWords', 'done']);
    assert.equal(llm.requests.length, 1, 'cache hit');
    assert.match(JSON.parse(llm.requests[0]!.messages.at(-1)!.content).text, /^It is a truth\.$/);
  });

  test('context is forwarded only when given', async () => {
    const llm = new FakeLLM({ translation_result: [JSON.stringify(result), JSON.stringify(result)] });
    const app = buildApp(appOptions(llm));
    after(() => app.close());
    await app.inject({ method: 'POST', url: '/v1/translate', payload: { text: 'He left.', context: 'The man stood up.' } });
    const u = JSON.parse(llm.requests[0]!.messages.at(-1)!.content);
    assert.equal(u.context, 'The man stood up.');
    await app.inject({ method: 'POST', url: '/v1/translate', payload: { text: 'She left.' } });
    assert.equal(JSON.parse(llm.requests[1]!.messages.at(-1)!.content).context, null);
  });

  test('invalid stream → one non-streaming retry, fields resent, done', async () => {
    const llm = new FakeLLM({ translation_result: ['{"hindi":"x"}', JSON.stringify(result)] });
    const app = buildApp(appOptions(llm));
    after(() => app.close());
    const r = await app.inject({ method: 'POST', url: '/v1/translate', payload: { text: 'Retry me.' } });
    const ev = parseSse(r.body);
    assert.equal(ev.at(-1)!.event, 'done');
    assert.equal(llm.requests.length, 2);
  });

  test('invalid twice → error event, nothing cached', async () => {
    const llm = new FakeLLM({ translation_result: ['{}', '{}'] });
    const opts = appOptions(llm);
    const app = buildApp(opts);
    after(() => app.close());
    const r = await app.inject({ method: 'POST', url: '/v1/translate', payload: { text: 'Bad twice.' } });
    const ev = parseSse(r.body);
    assert.equal(ev.at(-1)!.event, 'error');
    assert.equal((opts.cache as unknown as { map: Map<string, unknown> }).map.size, 0);
  });

  test('empty text → 400 JSON, before any stream', async () => {
    const app = buildApp(appOptions(new FakeLLM({})));
    after(() => app.close());
    const r = await app.inject({ method: 'POST', url: '/v1/translate', payload: { text: '  ' } });
    assert.equal(r.statusCode, 400);
    assert.equal(r.json().error.code, 'BAD_REQUEST');
  });
});
