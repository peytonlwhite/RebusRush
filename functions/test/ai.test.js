import test from 'node:test';
import assert from 'node:assert/strict';
import {createAI} from '../src/ai.js';

test('temporary capacity failures back off and count every retry', async () => {
  let calls = 0, requests = 0; const delays = [];
  const ai = createAI({model: 'test', reserveCall: async () => calls++, wait: async ms => delays.push(ms), client: {models: {
    generateContent: async () => {if (++requests < 3) throw Object.assign(new Error('Capacity'), {status: 429}); return {text: '{"puzzles":[]}'};},
  }}});
  assert.deepEqual(await ai.generate([]), []);
  assert.equal(calls, 3);
  assert.equal(delays.length, 2);
  assert.ok(delays[0] >= 15000 && delays[1] >= 30000);
});

test('permanent errors and exhausted request budgets are never retried', async () => {
  let calls = 0;
  const client = {models: {generateContent: async () => {throw Object.assign(new Error('Bad schema'), {status: 400});}}};
  const ai = createAI({model: 'test', reserveCall: async () => calls++, client});
  await assert.rejects(ai.generate([]), /Bad schema/); assert.equal(calls, 1);
  const limited = createAI({model: 'test', reserveCall: async () => {throw new Error('Budget exhausted');}, client});
  await assert.rejects(limited.generate([]), /Budget exhausted/);
});

test('truncated model responses fail before any partial puzzle is accepted', async () => {
  let calls = 0;
  const ai = createAI({model: 'test', reserveCall: async () => calls++, client: {models: {
    generateContent: async () => ({text: '{"puzzles":[', candidates: [{finishReason: 'MAX_TOKENS'}]}),
  }}});
  await assert.rejects(ai.generate([]), /token limit/);
  assert.equal(calls, 1);
});

test('small complete batches use bounded thinking and preserve image review input', async () => {
  const requests = [];
  const ai = createAI({model: 'test', reserveCall: async () => {}, client: {models: {
    generateContent: async request => {requests.push(request); return {text: '{"puzzles":[]}', candidates: [{finishReason: 'STOP'}]};},
  }}});
  await ai.generate([]);
  await ai.solve(Buffer.from('image fixture'));
  assert.match(requests[0].contents[0].parts[0].text, /Design 5 distinct/);
  assert.equal(requests[0].config.thinkingConfig.thinkingLevel, 'LOW');
  assert.equal(requests[1].contents[0].parts[1].inlineData.mimeType, 'image/png');
});
