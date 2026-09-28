export function validatePuzzleEdit(input) {
  const text = (value, max, name) => {
    if (typeof value !== 'string' || !value.trim() || value.length > max) throw Error(`Invalid ${name}`);
    return value.trim();
  };
  const answer = text(input.answer, 200, 'answer');
  const explanation = text(input.explanation, 2000, 'explanation');
  if (!Array.isArray(input.hints) || input.hints.length !== 3) throw Error('Exactly three hints are required');
  const hints = input.hints.map(h => text(h, 500, 'hint'));
  if (![null, 'easy', 'medium', 'hard'].includes(input.difficulty)) throw Error('Invalid difficulty');
  if (typeof input.retired !== 'boolean') throw Error('Invalid retired state');
  const url = new URL(text(input.photoUrl, 2000, 'image URL'));
  if (url.protocol !== 'https:' || url.username || url.password || url.port ||
      !((url.hostname === 'firebasestorage.googleapis.com' && url.pathname.startsWith('/v0/b/puzzle-time-72ad9.firebasestorage.app/o/')) ||
        (url.hostname === 'storage.googleapis.com' && url.pathname.startsWith('/puzzle-time-72ad9.firebasestorage.app/')))) {
    throw Error('Image must be in the RebusRush Firebase Storage bucket');
  }
  return {answer, explanation, hints, difficulty: input.difficulty, retired: input.retired, photoUrl: url.href};
}

export const revisionOf = snapshot => `${snapshot.updateTime.seconds}:${snapshot.updateTime.nanoseconds}`;

export function authorizedRequest(request, host, token) {
  return request.headers.host === host &&
    (!request.headers.origin || request.headers.origin === `http://${host}`) &&
    request.headers.authorization === `Bearer ${token}`;
}
