import { randomUUID } from 'node:crypto';
import { FieldValue, Timestamp } from 'firebase-admin/firestore';
import { TARGET, MAX_CANDIDATES, MAX_MODEL_CALLS, normalize, puzzleId, layoutHash, digest, passesReview } from './domain.js';
import { renderPuzzle, STYLE_VERSION } from './render.js';
import { createAI } from './ai.js';

const LEASE_MS = 35 * 60 * 1000;

export async function runWeekly({db, bucket, project, model, week, aiFactory = createAI, logger = console}) {
  const runRef = db.collection('riddleGenerationRuns').doc(week);
  const owner = randomUUID();
  const claim = await db.runTransaction(async tx => {
    const old = (await tx.get(runRef)).data() ?? {};
    if (old.status === 'published') return 'published';
    if (old.leaseUntil?.toMillis() > Date.now()) return 'busy';
    if ((old.modelCalls ?? 0) >= MAX_MODEL_CALLS) throw new Error('Weekly model-call budget exhausted');
    tx.set(runRef, {status: 'working', owner, leaseUntil: Timestamp.fromMillis(Date.now() + LEASE_MS),
      startedAt: old.startedAt ?? Timestamp.now(), updatedAt: Timestamp.now(), model,
      modelCalls: old.modelCalls ?? 0, candidateCount: old.candidateCount ?? 0, target: TARGET,
    }, {merge: true});
    return 'claimed';
  });
  if (claim !== 'claimed') return {status: claim};

  const assertOwner = data => {
    if (data?.owner !== owner || data?.status !== 'working') throw new Error('Generation lease lost');
  };
  const reserveCall = () => db.runTransaction(async tx => {
    const data = (await tx.get(runRef)).data(); assertOwner(data);
    if (data.modelCalls >= MAX_MODEL_CALLS) throw new Error('Weekly model-call budget exhausted');
    tx.update(runRef, {modelCalls: data.modelCalls + 1, updatedAt: Timestamp.now()});
  });
  try {
    const current = await db.collection('riddles').get();
    const excluded = new Set(current.docs.map(d => d.data().answer).filter(Boolean));
    const usedAnswers = new Set([...excluded].map(normalize));
    const usedLayouts = new Set(current.docs.map(d => d.data().layoutHash).filter(Boolean));
    const candidates = await runRef.collection('candidates').get();
    const accepted = [];
    const mechanicCounts = {};
    for (const doc of candidates.docs) {
      const candidate = doc.data();
      excluded.add(candidate.puzzle.answer);
      if (candidate.status === 'accepted' && !usedAnswers.has(normalize(candidate.puzzle.answer))) {
        const rendered = renderPuzzle(candidate.puzzle);
        accepted.push({...rendered, id: doc.id, hash: layoutHash(rendered.puzzle)});
        usedAnswers.add(normalize(rendered.puzzle.answer));
        usedLayouts.add(layoutHash(rendered.puzzle));
        mechanicCounts[rendered.puzzle.mechanic] = (mechanicCounts[rendered.puzzle.mechanic] ?? 0) + 1;
      }
    }
    let candidateCount = (await runRef.get()).data().candidateCount;
    const ai = aiFactory({project, model, reserveCall});
    while (accepted.length < TARGET && candidateCount < MAX_CANDIDATES) {
      const requested = Math.min(5, MAX_CANDIDATES - candidateCount);
      const generated = await ai.generate([...excluded], requested, mechanicCounts);
      if (!Array.isArray(generated) || generated.length === 0 || generated.length > requested) throw new Error('Invalid generated batch size');
      // Model-call attempts are already counted before the network request. Count
      // candidate slots only when an actual response exists, before processing it.
      await db.runTransaction(async tx => {
        const data = (await tx.get(runRef)).data(); assertOwner(data);
        if (data.candidateCount + generated.length > MAX_CANDIDATES) throw new Error('Weekly candidate budget exhausted');
        tx.update(runRef, {candidateCount: data.candidateCount + generated.length});
      });
      candidateCount += generated.length;
      for (const raw of generated) {
        if (accepted.length >= TARGET) break;
        let rendered;
        try { rendered = renderPuzzle(raw); }
        catch (error) { logger.warn('Rejected invalid puzzle', {reason: error.message}); continue; }
        const {puzzle, png} = rendered;
        const answerKey = normalize(puzzle.answer), hash = layoutHash(puzzle), id = puzzleId(puzzle.answer);
        if (usedAnswers.has(answerKey) || usedLayouts.has(hash) || [...excluded].some(a => normalize(a) === answerKey)) continue;
        excluded.add(puzzle.answer);
        // More than five of the same mechanism would make the weekly batch repetitive.
        if ((mechanicCounts[puzzle.mechanic] ?? 0) >= 5) continue;
        const solution = await ai.solve(png);
        const review = normalize(solution.answer) === answerKey && solution.ambiguous === false && solution.confidence >= 0.85
          ? await ai.review(puzzle, png, [...excluded].filter(answer => normalize(answer) !== answerKey)) : null;
        const approved = passesReview(puzzle, solution, review);
        await runRef.collection('candidates').doc(id).set({puzzle, status: approved ? 'accepted' : 'rejected',
          solution, review, checkedAt: Timestamp.now(), layoutHash: hash, styleVersion: STYLE_VERSION});
        if (!approved) continue;
        accepted.push({...rendered, id, hash});
        usedAnswers.add(answerKey); usedLayouts.add(hash);
        mechanicCounts[puzzle.mechanic] = (mechanicCounts[puzzle.mechanic] ?? 0) + 1;
        logger.info('Puzzle passed checks', {week, accepted: accepted.length, target: TARGET});
      }
    }
    if (accepted.length < TARGET) throw new Error(`Only ${accepted.length}/${TARGET} puzzles passed. Nothing published; accepted candidates saved for inspection.`);
    const selected = accepted.slice(0, TARGET);
    const documents = [];
    for (const {puzzle, png, id, hash} of selected) {
      const objectPath = `riddles/generated/${week}/${id}.png`;
      const file = bucket.file(objectPath);
      const token = randomUUID();
      const imageHash = digest(png);
      let actualToken = token;
      try {
        await file.save(png, {resumable: false, validation: 'crc32c', preconditionOpts: {ifGenerationMatch: 0}, metadata: {
          contentType: 'image/png', cacheControl: 'public,max-age=31536000,immutable',
          metadata: {firebaseStorageDownloadTokens: token, sha256: imageHash, generationWeek: week},
        }});
      } catch (error) {
        if (Number(error.code) !== 412) throw error;
        const [metadata] = await file.getMetadata();
        if (metadata.metadata?.sha256 !== imageHash || !metadata.metadata?.firebaseStorageDownloadTokens) {
          throw new Error('Existing generated image differs; refusing overwrite');
        }
        actualToken = metadata.metadata.firebaseStorageDownloadTokens;
      }
      const photoUrl = `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(objectPath)}?alt=media&token=${actualToken}`;
      documents.push({id, answer: puzzle.answer, hints: puzzle.hints, explanation: puzzle.explanation, photoUrl,
        difficulty: puzzle.difficulty, mechanic: puzzle.mechanic, normalizedAnswer: normalize(puzzle.answer),
        layoutHash: hash, generationWeek: week, styleVersion: STYLE_VERSION, generatorModel: model,
        provenance: 'Generated from common English phrases; original rendered layout and authored clues',
      });
    }
    // All 20 become visible atomically, only after every image exists. Never overwrite an existing puzzle.
    await db.runTransaction(async tx => {
      const run = (await tx.get(runRef)).data(); assertOwner(run);
      const settings = (await tx.get(db.collection('adminSettings').doc('weeklyPuzzles'))).data();
      if (settings?.enabled === false) throw new Error('Publication paused by adminSettings/weeklyPuzzles');
      const live = await tx.get(db.collection('riddles'));
      const existing = new Set(live.docs.map(d => normalize(d.data().answer ?? '')));
      for (const doc of documents) if (existing.has(normalize(doc.answer))) throw new Error('A duplicate was added during generation; publishing aborted');
      const createdAt = Timestamp.now();
      for (const {id, ...data} of documents) tx.create(db.collection('riddles').doc(id), {...data, createdAt});
      tx.update(runRef, {status: 'published', publishedAt: createdAt, updatedAt: createdAt,
        publishedIds: documents.map(d => d.id), publishedCount: documents.length, leaseUntil: FieldValue.delete()});
    });
    logger.info('Weekly batch published', {week, count: documents.length});
    return {status: 'published', count: documents.length, week};
  } catch (error) {
    await db.runTransaction(async tx => {
      const data = (await tx.get(runRef)).data();
      if (data?.owner === owner && data.status !== 'published') tx.update(runRef, {
        status: 'failed', lastError: String(error.message).slice(0, 700), updatedAt: Timestamp.now(), leaseUntil: FieldValue.delete(),
      });
    });
    throw error;
  }
}
