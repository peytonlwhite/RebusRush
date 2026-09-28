import {TARGET, normalize, layoutHash, digest} from './domain.js';
import {renderPuzzle} from './render.js';

export function prepareManualBatch(batch) {
  if (!batch || batch.reviewed !== true || typeof batch.reviewedBy !== 'string' || !batch.reviewedBy.trim()) {
    throw new Error('Manual batch must record reviewed: true and reviewedBy after reviewing every image, answer, hint and explanation');
  }
  if (!Array.isArray(batch.puzzles) || batch.puzzles.length !== TARGET) throw new Error(`Manual batch requires exactly ${TARGET} puzzles`);
  const rendered = batch.puzzles.map(renderPuzzle);
  if (new Set(rendered.map(r => normalize(r.puzzle.answer))).size !== TARGET) throw new Error('Duplicate manual answers');
  if (new Set(rendered.map(r => layoutHash(r.puzzle))).size !== TARGET) throw new Error('Duplicate manual layouts');
  return {rendered, reviewedBy: batch.reviewedBy.trim(), hash: digest(JSON.stringify(rendered.map(r => r.puzzle)))};
}
