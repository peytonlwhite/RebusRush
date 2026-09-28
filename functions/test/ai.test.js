import test from 'node:test';
import assert from 'node:assert/strict';
import {createAI} from '../src/ai.js';

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
