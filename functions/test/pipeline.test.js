import test from 'node:test';
import assert from 'node:assert/strict';
import { runWeekly } from '../src/pipeline.js';
import { MECHANICS, MAX_CANDIDATES, puzzleId } from '../src/domain.js';
import { samples } from '../scripts/samples.js';

// An in-memory transactional adapter exercises orchestration and failures without touching live Firebase.
function fakeDB(initial = {}) {
  const records = new Map(Object.entries(initial));
  const snapshot = path => ({id: path.split('/').at(-1), data: () => records.get(path)});
  const query = path => ({docs: [...records.keys()].filter(k => k.startsWith(`${path}/`) && k.split('/').length === path.split('/').length + 1).map(snapshot)});
  const collection = path => ({path, doc: id => doc(`${path}/${id}`), get: async () => query(path)});
  const doc = path => ({path, collection: name => collection(`${path}/${name}`), get: async () => snapshot(path),
    set: async data => records.set(path, data)});
  return {records, collection, async runTransaction(fn) {
    const writes = [];
    const result = await fn({
      get: async ref => ref.doc ? query(ref.path) : snapshot(ref.path),
      set: (ref, data, options) => writes.push(() => records.set(ref.path, options?.merge ? {...records.get(ref.path), ...data} : data)),
      update: (ref, data) => writes.push(() => records.set(ref.path, {...records.get(ref.path), ...data})),
      create: (ref, data) => {if (records.has(ref.path)) throw new Error('Already exists'); writes.push(() => records.set(ref.path, data));},
    });
    writes.forEach(write => write());
    return result;
  }};
}
function fakeBucket({failAt = Infinity} = {}) {
  const objects = new Map(); let attempts = 0;
  return {name:'test-bucket', objects, file: path => ({
    async save(bytes, options) {
      attempts++;
      if (attempts === failAt) throw new Error('Injected upload failure');
      if (objects.has(path)) throw Object.assign(new Error('Already uploaded'), {code:412});
      objects.set(path, {bytes, ...options.metadata});
    },
    async getMetadata() {return [objects.get(path)];},
  })};
}
function fakeAI({reject = false, duplicate = false} = {}) {
  let serial = 0, last;
  return ({reserveCall}) => ({
    async generate(excluded, count) {
      await reserveCall();
      return Array.from({length:count}, () => {
        const n = serial++;
        return {...samples[0], answer: duplicate ? 'existing-answer' : `fixture answer ${n}`, mechanic: MECHANICS[n % MECHANICS.length],
          words: [{text:`CLUE ${n}`,x:540,y:540,size:100,rotation:0}]};
      });
    },
    async solve(png) {
      await reserveCall();
      // Tests attach an accepted answer based on solve order; fixtures are deliberately not real puzzles.
      last = (last ?? -1) + 1;
      return {answer:`fixture answer ${last}`,confidence:0.95,ambiguous:reject};
    },
    async review() {await reserveCall(); return {valid:true,hintsAccurate:true,explanationAccurate:true,familyFriendly:true,distinctFromLibrary:true};},
  });
}
const logger = {info(){},warn(){}};
const args = extra => ({project:'test',model:'fake',week:'2026-09-28',logger,verifyImage:async()=>{},...extra});
const published = db => [...db.records.keys()].filter(k=>k.startsWith('riddles/'));

test('publishes exactly 20 with all required app fields and no second batch on retry', async () => {
  const db = fakeDB(), bucket = fakeBucket();
  const result = await runWeekly(args({db,bucket,aiFactory:fakeAI()}));
  assert.equal(result.count, 20);
  assert.equal(bucket.objects.size, 20);
  for (const image of bucket.objects.values()) assert.equal(image.metadata.resizedImage, 'true');
  assert.equal(published(db).length, 20);
  for (const key of published(db)) {
    const value = db.records.get(key);
    assert.equal(value.hints.length,3); assert.ok(value.createdAt.toMillis());
    assert.match(value.photoUrl,/alt=media&token=/);
  }
  const rerun = await runWeekly(args({db,bucket,aiFactory:()=>{throw new Error('Must not generate twice');}}));
  assert.equal(rerun.status,'published'); assert.equal(published(db).length,20);
});

test('a broken public image URL prevents publication of the entire batch', async () => {
  const db = fakeDB(), bucket = fakeBucket();
  let checked = 0;
  const verifyImage = async () => {if (++checked === 7) throw new Error('Image URL returned 404');};
  await assert.rejects(runWeekly(args({db,bucket,aiFactory:fakeAI(),verifyImage})), /Image URL returned 404/);
  assert.equal(published(db).length, 0);
  assert.equal(db.records.get('riddleGenerationRuns/2026-09-28').status, 'failed');
});
test('partial Storage failure publishes zero puzzles; retry reuses accepted candidates and uploads', async () => {
  const db = fakeDB(), bucket = fakeBucket({failAt:7});
  await assert.rejects(runWeekly(args({db,bucket,aiFactory:fakeAI()})),/Injected upload failure/);
  assert.equal(published(db).length,0); assert.equal(bucket.objects.size,6);
  const priorTokens = [...bucket.objects.values()].map(x=>x.metadata.firebaseStorageDownloadTokens);
  // The failed run releases its lease; the mock resolves FieldValue.delete explicitly here.
  db.records.get('riddleGenerationRuns/2026-09-28').leaseUntil = undefined;
  const result = await runWeekly(args({db,bucket,aiFactory:()=>({generate(){throw new Error('Should reuse saved candidates');}})}));
  assert.equal(result.count,20); assert.equal(bucket.objects.size,20);
  assert.deepEqual([...bucket.objects.values()].slice(0,6).map(x=>x.metadata.firebaseStorageDownloadTokens),priorTokens);
});
test('ambiguous puzzles never publish and generation stops at the candidate budget', async () => {
  const db = fakeDB(), bucket = fakeBucket();
  await assert.rejects(runWeekly(args({db,bucket,aiFactory:fakeAI({reject:true})})),/Only 0\/20/);
  assert.equal(published(db).length,0); assert.equal(bucket.objects.size,0);
  assert.equal(db.records.get('riddleGenerationRuns/2026-09-28').candidateCount,MAX_CANDIDATES);
});
test('existing answers are not overwritten even when punctuation differs', async () => {
  const existing = {answer:'Existing answer', marker:'original'};
  const db = fakeDB({'riddles/legacy-id':existing}), bucket = fakeBucket();
  await assert.rejects(runWeekly(args({db,bucket,aiFactory:fakeAI({duplicate:true})})),/Only 0\/20/);
  assert.deepEqual(db.records.get('riddles/legacy-id'), existing);
  assert.equal(published(db).length,1); assert.equal(bucket.objects.size,0);
});

test('corrected puzzle answers keep their original IDs reserved during generation', async () => {
  const path = `riddles/${puzzleId('existing-answer')}`;
  const original = {answer:'corrected answer',retired:true};
  const db = fakeDB({[path]:original}), bucket = fakeBucket();
  const aiFactory = options => ({...fakeAI({duplicate:true})(options),
    solve:async()=>{throw Error('Must skip published IDs before reviewing an image');}});
  await assert.rejects(runWeekly(args({db,bucket,aiFactory})),/Only 0\/20/);
  assert.deepEqual(db.records.get(path), original);
  assert.equal(bucket.objects.size,0);
});
test('a live lease prevents concurrent writers before any model or storage work', async () => {
  const db = fakeDB({'riddleGenerationRuns/2026-09-28':{status:'working',owner:'another-worker',leaseUntil:{toMillis:()=>Date.now()+60000}}});
  const result = await runWeekly(args({db,bucket:fakeBucket(),aiFactory:()=>{throw new Error('Should not start');}}));
  assert.equal(result.status,'busy');
});

test('the publication transaction honors an admin pause even after images have been uploaded', async () => {
  const db = fakeDB({'adminSettings/weeklyPuzzles':{enabled:false}}), bucket = fakeBucket();
  await assert.rejects(runWeekly(args({db,bucket,aiFactory:fakeAI()})),/Publication paused/);
  assert.equal(bucket.objects.size,20);
  assert.equal(published(db).length,0);
  assert.equal(db.records.get('riddleGenerationRuns/2026-09-28').status,'failed');
});

test('failed model requests consume the call budget but not nonexistent candidate slots', async () => {
  const db = fakeDB(), bucket = fakeBucket();
  const aiFactory = ({reserveCall}) => ({async generate(){await reserveCall(); throw new Error('Model unavailable');}});
  await assert.rejects(runWeekly(args({db,bucket,aiFactory})),/Model unavailable/);
  const run = db.records.get('riddleGenerationRuns/2026-09-28');
  assert.equal(run.modelCalls,1); assert.equal(run.candidateCount,0); assert.equal(run.status,'failed');
  assert.equal(published(db).length,0);
});

const manualFixture = () => ({reviewed: true, reviewedBy: 'Test reviewer', puzzles: Array.from({length:20}, (_, n) => ({
  ...samples[0], answer: `manual fixture ${n}`, words: [{text:`CLUE ${n}`,x:540,y:540,size:100,rotation:0}],
}))});
test('reviewed local batches publish without model calls and share the weekly duplicate guard', async () => {
  const db = fakeDB(), bucket = fakeBucket();
  const options = args({db,bucket,manualBatch:manualFixture(),model:'manual-reviewed',aiFactory:()=>{throw new Error('Must not call a model');}});
  const result = await runWeekly(options);
  assert.equal(result.count, 20); assert.equal(published(db).length, 20);
  assert.equal(db.records.get('riddleGenerationRuns/2026-09-28').modelCalls, 0);
  for (const key of published(db)) assert.equal(db.records.get(key).reviewMethod, 'manual');
  await runWeekly(args({db,bucket,aiFactory:()=>{throw new Error('Must not regenerate a manually published week');}}));
  assert.equal(published(db).length, 20);
});
test('manual imports require recorded review and reject duplicate answers before upload', async () => {
  const db = fakeDB(), bucket = fakeBucket();
  await assert.rejects(runWeekly(args({db,bucket,manualBatch:{...manualFixture(),reviewed:false}})), /must record/);
  const duplicate = manualFixture(); duplicate.puzzles[1] = duplicate.puzzles[0];
  await assert.rejects(runWeekly(args({db,bucket,manualBatch:duplicate})), /Duplicate manual answers/);
  const live = fakeDB({'riddles/existing':{answer:'manual fixture 0'}});
  await assert.rejects(runWeekly(args({db:live,bucket,manualBatch:manualFixture()})), /duplicates the live library/);
  assert.equal(bucket.objects.size, 0);
});
