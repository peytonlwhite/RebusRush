import { mkdir, writeFile } from 'node:fs/promises';
import { renderPuzzle } from '../src/render.js';
import { samples } from './samples.js';

const output = new URL('../output/', import.meta.url);
await mkdir(output, {recursive: true});
const escape = s => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('"', '&quot;');
const cards = [];
for (const sample of samples) {
  const {png} = renderPuzzle(sample);
  const name = sample.answer.replaceAll(' ', '-');
  await writeFile(new URL(`${name}.png`, output), png);
  cards.push(`<article data-search="${escape(`${sample.answer} ${sample.mechanic} ${sample.difficulty}`)}"><img src="${name}.png" alt="Rebus puzzle"><details><summary>Reveal answer</summary><h2>${escape(sample.answer)}</h2><p>${escape(sample.explanation)}</p><ol>${sample.hints.map(h=>`<li>${escape(h)}</li>`).join('')}</ol></details></article>`);
}
await writeFile(new URL('index.html', output), `<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>RebusRush — Style preview</title><style>*{box-sizing:border-box}body{margin:0;background:#0d1224;color:#eef0ff;font-family:system-ui}header{max-width:1240px;margin:auto;padding:36px 24px 20px}h1{margin:0 0 10px}p{line-height:1.55;color:#c7cce5}input{padding:14px;border:1px solid #6470a1;border-radius:10px;background:#171f3a;color:white;width:min(100%,440px);font-size:16px}main{max-width:1240px;margin:auto;padding:0 24px 40px;display:grid;grid-template-columns:repeat(auto-fit,minmax(290px,1fr));gap:22px}article{background:#19213a;border-radius:16px;overflow:hidden}img{display:block;width:100%}details{padding:18px}summary{cursor:pointer}li{margin-bottom:9px;line-height:1.4}[hidden]{display:none}</style><header><h1>RebusRush · Puzzle style preview</h1><p>Six locally rendered examples. Varied gradient backgrounds, white lettering, and your logo at 18% opacity in the bottom-right corner. These are style samples, not a published batch.</p><input type="search" placeholder="Search answers, difficulty, or mechanic" aria-label="Search puzzles"></header><main>${cards.join('')}</main><script>document.querySelector('input').addEventListener('input',e=>{const q=e.target.value.toLowerCase();document.querySelectorAll('article').forEach(c=>c.hidden=!c.dataset.search.toLowerCase().includes(q))})</script></html>`);
console.log(`Rendered ${samples.length} style samples in functions/output`);
