import { createHash } from 'node:crypto';

export const TARGET = 20;
export const MAX_CANDIDATES = 60;
export const MAX_MODEL_CALLS = 140;
export const MECHANICS = ['position', 'containment', 'repetition', 'reversal', 'size', 'spacing', 'missing-letters', 'direction'];
export const normalize = value => String(value).normalize('NFKD').toLowerCase().replace(/[^a-z0-9]/g, '');
export const digest = value => createHash('sha256').update(value).digest('hex');
export const puzzleId = answer => `weekly_${digest(normalize(answer)).slice(0, 24)}`;

// A Monday date in the product timezone is stable across retries and year/DST changes.
export function weekId(date = new Date()) {
  const parts = Object.fromEntries(new Intl.DateTimeFormat('en-US', {
    timeZone: 'America/Chicago', year: 'numeric', month: '2-digit', day: '2-digit',
  }).formatToParts(date).map(p => [p.type, p.value]));
  const local = new Date(`${parts.year}-${parts.month}-${parts.day}T12:00:00Z`);
  local.setUTCDate(local.getUTCDate() - ((local.getUTCDay() + 6) % 7));
  return local.toISOString().slice(0, 10);
}

function requireThat(condition, message) {
  if (!condition) throw new Error(message);
}
function text(value, name, min, max) {
  requireThat(typeof value === 'string' && value.trim().length >= min && value.length <= max, `Invalid ${name}`);
  return value.trim();
}

export function validatePuzzle(raw) {
  requireThat(raw && typeof raw === 'object', 'Missing puzzle');
  const answer = text(raw.answer, 'answer', 3, 70);
  requireThat(/^[a-zA-Z0-9 '\-?!,]+$/.test(answer), 'Answer must be plain English');
  const explanation = text(raw.explanation, 'explanation', 35, 700);
  requireThat(Array.isArray(raw.hints) && raw.hints.length === 3, 'Exactly three hints required');
  const hints = raw.hints.map(h => text(h, 'hint', 10, 170));
  requireThat(new Set(hints.map(normalize)).size === 3, 'Hints must differ');
  requireThat(hints.every(h => !normalize(h).includes(normalize(answer))), 'Hint reveals full answer');
  requireThat(['easy', 'medium', 'hard'].includes(raw.difficulty), 'Invalid difficulty');
  requireThat(MECHANICS.includes(raw.mechanic), 'Invalid mechanic');
  requireThat(Array.isArray(raw.words) && raw.words.length >= 1 && raw.words.length <= 16, 'Invalid word count');
  const words = raw.words.map(w => {
    const value = text(w.text, 'visible text', 1, 24);
    requireThat(/^[A-Za-z0-9 ?!.,'&+\-=\/]+$/.test(value), 'Unsupported characters');
    for (const key of ['x', 'y', 'size', 'rotation']) requireThat(Number.isFinite(w[key]), `Invalid ${key}`);
    requireThat(w.size >= 36 && w.size <= 180, 'Font size outside 36–180');
    requireThat(w.x >= 80 && w.x <= 1000 && w.y >= 220 && w.y <= 900, 'Text outside puzzle area');
    requireThat([0, -90, 90, 180].includes(w.rotation), 'Invalid text rotation');
    return {text: value, x: w.x, y: w.y, size: w.size, rotation: w.rotation};
  });
  requireThat(!words.some(w => normalize(w.text) === normalize(answer)), 'Image directly reveals answer');
  requireThat(Array.isArray(raw.shapes) && raw.shapes.length <= 4, 'Invalid shapes');
  const shapes = raw.shapes.map(s => {
    requireThat(['rect', 'ellipse', 'line'].includes(s.type), 'Unsupported shape');
    for (const key of ['x', 'y', 'width', 'height']) requireThat(Number.isFinite(s[key]), `Invalid shape ${key}`);
    requireThat(s.width >= 0 && s.height >= 0 && s.width + s.height > 0, 'Empty shape');
    requireThat(s.x >= 60 && s.y >= 200 && s.x + s.width <= 1020 && s.y + s.height <= 940, 'Shape outside safe area');
    return {type: s.type, x: s.x, y: s.y, width: s.width, height: s.height};
  });
  return {answer, explanation, hints, difficulty: raw.difficulty, mechanic: raw.mechanic, words, shapes};
}

export function layoutHash(puzzle) {
  return digest(JSON.stringify({words: puzzle.words, shapes: puzzle.shapes}));
}

export function passesReview(puzzle, solution, review) {
  return solution?.ambiguous === false && Number.isFinite(solution?.confidence) && solution.confidence >= 0.85 &&
    normalize(solution.answer) === normalize(puzzle.answer) &&
    review?.valid === true && review?.hintsAccurate === true && review?.explanationAccurate === true &&
    review?.familyFriendly === true && review?.distinctFromLibrary === true;
}

export const puzzleSchema = {
  type: 'object', required: ['answer', 'hints', 'explanation', 'difficulty', 'mechanic', 'words', 'shapes'],
  properties: {
    answer: {type: 'string'}, hints: {type: 'array', items: {type: 'string'}, minItems: 3, maxItems: 3},
    explanation: {type: 'string'}, difficulty: {type: 'string', enum: ['easy', 'medium', 'hard']},
    mechanic: {type: 'string', enum: MECHANICS},
    words: {type: 'array', minItems: 1, maxItems: 16, items: {
      type: 'object', required: ['text', 'x', 'y', 'size', 'rotation'], properties: {
        text: {type: 'string'}, x: {type: 'number'}, y: {type: 'number'}, size: {type: 'number'}, rotation: {type: 'number'},
      },
    }},
    shapes: {type: 'array', maxItems: 4, items: {
      type: 'object', required: ['type', 'x', 'y', 'width', 'height'], properties: {
        type: {type: 'string', enum: ['rect', 'ellipse', 'line']}, x: {type: 'number'}, y: {type: 'number'},
        width: {type: 'number'}, height: {type: 'number'},
      },
    }},
  },
};
