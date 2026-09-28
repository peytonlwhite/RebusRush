import {readFile, mkdir, writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {parseArgs} from 'node:util';
import {initializeApp, applicationDefault} from 'firebase-admin/app';
import {getFirestore} from 'firebase-admin/firestore';
import {getStorage} from 'firebase-admin/storage';
import {renderPuzzle} from '../src/render.js';
import {weekId} from '../src/domain.js';
import {prepareManualBatch} from '../src/manual.js';
import {runWeekly} from '../src/pipeline.js';

const {values} = parseArgs({options: {
  file: {type: 'string'}, week: {type: 'string'}, publish: {type: 'boolean', default: false},
  output: {type: 'string', default: 'output/manual'},
}});
if (!values.file) throw new Error('Usage: npm run puzzles:import -- --file batch.json [--week YYYY-MM-DD --publish]');
const batch = JSON.parse(await readFile(resolve(values.file), 'utf8'));
if (!Array.isArray(batch.puzzles) || !batch.puzzles.length) throw new Error('Expected a puzzles array');
const output = resolve(values.output); await mkdir(output, {recursive: true});
const cards = [];
const escape = value => String(value).replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('"', '&quot;');
for (const [index, input] of batch.puzzles.entries()) {
  const {puzzle, png} = renderPuzzle(input);
  const filename = `${index + 1}.png`; await writeFile(resolve(output, filename), png);
  cards.push(`<article><img src="${filename}" alt="Rebus puzzle"><h2>${escape(puzzle.answer)}</h2><p>${escape(puzzle.explanation)}</p><ol>${puzzle.hints.map(h => `<li>${escape(h)}</li>`).join('')}</ol></article>`);
}
await writeFile(resolve(output, 'index.html'), `<!doctype html><meta charset="utf-8"><title>Manual puzzle review</title><style>body{background:#14213b;color:white;font:16px system-ui;margin:32px}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:24px}img{width:100%}p,li{line-height:1.5}</style><h1>Review every puzzle before publishing</h1><main>${cards.join('')}</main>`);
console.log(`Rendered ${cards.length} puzzles: ${resolve(output, 'index.html')}`);
if (values.publish) {
  prepareManualBatch(batch);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(values.week ?? '') || weekId(new Date(`${values.week}T18:00:00Z`)) !== values.week) throw new Error('--week must be a valid Monday date');
  const project = 'puzzle-time-72ad9';
  const app = initializeApp({credential: applicationDefault(), projectId: project, storageBucket: `${project}.firebasestorage.app`});
  console.log(await runWeekly({db: getFirestore(app), bucket: getStorage(app).bucket(), project,
    model: 'manual-reviewed', week: values.week, manualBatch: batch}));
} else console.log('Preview only. No Firebase access or model calls. Review all images and clues before setting reviewed: true and reviewedBy.');
