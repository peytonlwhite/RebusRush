import test from 'node:test';
import assert from 'node:assert/strict';
import { weekId, normalize, puzzleId, validatePuzzle, passesReview } from '../src/domain.js';
import { renderPuzzle } from '../src/render.js';
import { samples } from '../scripts/samples.js';

test('week boundaries use Chicago time, including year and DST boundaries', () => {
  assert.equal(weekId(new Date('2026-09-28T04:59:59Z')), '2026-09-21');
  assert.equal(weekId(new Date('2026-09-28T05:00:00Z')), '2026-09-28');
  assert.equal(weekId(new Date('2027-01-01T12:00:00Z')), '2026-12-28');
  assert.equal(weekId(new Date('2026-11-02T05:59:59Z')), '2026-10-26');
  assert.equal(weekId(new Date('2026-11-02T06:00:00Z')), '2026-11-02');
});
test('answer identity ignores case, punctuation and spacing', () => {
  assert.equal(normalize('Head-over HEELS!'), normalize('head over heels'));
  assert.equal(puzzleId('Head-over HEELS!'), puzzleId('head over heels'));
});
test('reject malformed payloads, missing hints and hints revealing the answer', () => {
  assert.throws(() => validatePuzzle({...samples[0], hints: ['short']}));
  assert.throws(() => validatePuzzle({...samples[0], hints: ['It means head over heels.', ...samples[0].hints.slice(1)]}));
  assert.throws(() => validatePuzzle({...samples[0], words: [{...samples[0].words[0], text: '<script>bad</script>'}]}));
});
test('render actual glyph bounds and reject clipping or overlapping words', () => {
  assert.throws(() => renderPuzzle({...samples[0], words: [{text:'VERY LONG TEXT HERE', x:540,y:540,size:180,rotation:0}]}), /clipped/);
  assert.throws(() => renderPuzzle({...samples[0], words: [samples[0].words[0], samples[0].words[0]]}), /overlaps/);
});
test('all six sample images are stable 1080px PNGs with specified logo placement', () => {
  for (const sample of samples) {
    const a = renderPuzzle(sample), b = renderPuzzle(sample);
    assert.deepEqual(a.png, b.png);
    assert.equal(a.png.readUInt32BE(16), 1080);
    assert.equal(a.png.readUInt32BE(20), 1080);
    assert.match(a.svg, /x="930" y="34".*opacity="0.18"/);
  }
});
test('publishing requires independent agreement and all editorial checks', () => {
  const solution = {answer: samples[0].answer, confidence:0.95, ambiguous:false};
  const review = {valid:true,hintsAccurate:true,explanationAccurate:true,familyFriendly:true,distinctFromLibrary:true};
  assert.equal(passesReview(samples[0], solution, review), true);
  assert.equal(passesReview(samples[0], {...solution, answer:'something else'}, review), false);
  assert.equal(passesReview(samples[0], {...solution, ambiguous:true}, review), false);
  assert.equal(passesReview(samples[0], solution, {...review,hintsAccurate:false}), false);
  assert.equal(passesReview(samples[0], {...solution,confidence:0.5}, review), false);
  assert.equal(passesReview(samples[0], solution, {...review,distinctFromLibrary:false}), false);
});
