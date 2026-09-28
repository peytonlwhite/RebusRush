import {createServer} from 'node:http';
import {randomBytes} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {resolve} from 'node:path';
import {Firestore, FieldValue} from 'firebase-admin/firestore';
import {authorizedRequest, validatePuzzleEdit, revisionOf} from '../src/admin-review.js';

const projectId = 'puzzle-time-72ad9';
let credentials;
let actor = 'local-admin';
// Optional reuse of the owner's official Firebase CLI login, without exporting
// refresh tokens or sending any administrator credential to the browser.
if (process.env.FIREBASE_CLI_ROOT) {
  const require = createRequire(import.meta.url);
  const auth = require(resolve(process.env.FIREBASE_CLI_ROOT, 'lib/auth.js'));
  const api = require(resolve(process.env.FIREBASE_CLI_ROOT, 'lib/api.js'));
  const account = auth.getGlobalDefaultAccount();
  if (!account?.tokens?.refresh_token) throw Error('Run firebase login first');
  actor = account.user.email;
  credentials = {type: 'authorized_user', client_id: api.clientId(), client_secret: api.clientSecret(), refresh_token: account.tokens.refresh_token};
}
const db = new Firestore({projectId, ...(credentials ? {credentials} : {})});
const port = Number(process.env.ADMIN_PORT || 8787);
const host = `127.0.0.1:${port}`;
const token = randomBytes(32).toString('hex');
const assets = new Map([
  ['/', ['index.html', 'text/html']], ['/app.js', ['app.js', 'text/javascript']], ['/style.css', ['style.css', 'text/css']]
]);
async function bodyOf(request) {
  let body = '';
  for await (const chunk of request) {
    body += chunk;
    if (body.length > 16000) throw Error('Request too large');
  }
  return JSON.parse(body);
}
const server = createServer(async (request, response) => {
  response.setHeader('Cache-Control', 'no-store');
  response.setHeader('X-Content-Type-Options', 'nosniff');
  response.setHeader('Referrer-Policy', 'no-referrer');
  response.setHeader('Content-Security-Policy', "default-src 'self'; img-src 'self' https://firebasestorage.googleapis.com https://storage.googleapis.com; frame-ancestors 'none'; base-uri 'none'; form-action 'none'");
  const reply = (status, data) => { response.writeHead(status, {'Content-Type': 'application/json'}); response.end(JSON.stringify(data)); };
  try {
    if (request.headers.host !== host) return reply(403, {error: 'Invalid host'});
    const url = new URL(request.url, `http://${host}`);
    const asset = assets.get(url.pathname);
    if (request.method === 'GET' && asset) {
      response.writeHead(200, {'Content-Type': asset[1]});
      return response.end(await readFile(new URL(`../admin/${asset[0]}`, import.meta.url)));
    }
    if (!authorizedRequest(request, host, token)) return reply(403, {error: 'Reopen the local URL printed by the admin server.'});
    if (request.method === 'GET' && url.pathname === '/api/data') {
      const [puzzles, reports] = await Promise.all([
        db.collection('riddles').get(), db.collection('puzzleReports').orderBy('createdAt', 'desc').limit(500).get()
      ]);
      return reply(200, {
        puzzles: puzzles.docs.map(doc => ({...doc.data(), id: doc.id, revision: revisionOf(doc)})),
        reports: reports.docs.map(doc => ({...doc.data(), id: doc.id})),
        reportLimit: 500
      });
    }
    if (request.method === 'POST' && url.pathname === '/api/puzzle') {
      const input = await bodyOf(request);
      if (typeof input.id !== 'string' || input.id.includes('/') || !input.id) throw Error('Invalid puzzle ID');
      const patch = validatePuzzleEdit(input);
      const ref = db.collection('riddles').doc(input.id);
      await db.runTransaction(async tx => {
        const previous = await tx.get(ref);
        if (!previous.exists || revisionOf(previous) !== input.revision) throw Error('Puzzle changed. Reload before saving.');
        tx.create(db.collection('puzzleReviewAudit').doc(), {riddleId: input.id, before: previous.data(), after: patch, actor, at: FieldValue.serverTimestamp()});
        tx.update(ref, {...patch, reviewedAt: FieldValue.serverTimestamp()});
      });
      return reply(200, {saved: true});
    }
    if (request.method === 'POST' && url.pathname === '/api/report') {
      const input = await bodyOf(request);
      if (typeof input.id !== 'string' || input.id.includes('/') || !input.id || !['open', 'resolved'].includes(input.status)) throw Error('Invalid report');
      await db.collection('puzzleReports').doc(input.id).update({status: input.status, reviewedAt: FieldValue.serverTimestamp(), reviewedBy: actor});
      return reply(200, {saved: true});
    }
    return reply(404, {error: 'Not found'});
  } catch (error) { return reply(400, {error: error.message}); }
});
server.listen(port, '127.0.0.1', () => console.log(`RebusRush private review: http://${host}/#${token}\nStop this process when finished. Changes save to ${projectId}.`));
