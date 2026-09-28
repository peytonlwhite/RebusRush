import test from 'node:test';
import assert from 'node:assert/strict';
import {validatePuzzleEdit, authorizedRequest} from '../src/admin-review.js';
const valid = {answer: 'Head over heels', explanation: 'Head is above heels.', hints: ['One', 'Two', 'Three'], difficulty: 'easy', retired: false,
  photoUrl: 'https://firebasestorage.googleapis.com/v0/b/puzzle-time-72ad9.firebasestorage.app/o/test.png?alt=media'};
test('review edits cannot change generated IDs, dates, or server fields', () => {
  assert.deepEqual(validatePuzzleEdit({...valid, createdAt: 'fake', id: 'new', admin: true}), valid);
});
test('review rejects invalid hints, metadata and image destinations', () => {
  for (const patch of [{hints: []}, {answer: ''}, {difficulty: 'impossible'}, {retired: 'false'},
    {photoUrl: 'javascript:alert(1)'}, {photoUrl: 'https://example.com/image.png'},
    {photoUrl: 'https://firebasestorage.googleapis.com/v0/b/another-project/o/test.png'}]) {
    assert.throws(() => validatePuzzleEdit({...valid, ...patch}));
  }
});
test('local review rejects cross-origin, DNS rebinding and missing session tokens', () => {
  const headers = {host: '127.0.0.1:8787', origin: 'http://127.0.0.1:8787', authorization: 'Bearer secret'};
  assert.equal(authorizedRequest({headers}, headers.host, 'secret'), true);
  for (const patch of [{host: 'evil.example'}, {origin: 'https://evil.example'}, {authorization: undefined}]) {
    assert.equal(authorizedRequest({headers: {...headers, ...patch}}, headers.host, 'secret'), false);
  }
});
