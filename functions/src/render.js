import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { create } from 'fontkit';
import { Resvg } from '@resvg/resvg-js';
import { validatePuzzle } from './domain.js';

const require = createRequire(import.meta.url);
const font = create(readFileSync(require.resolve('@fontsource/noto-sans/files/noto-sans-latin-700-normal.woff')));
const logo = readFileSync(new URL('../assets/logo.png', import.meta.url)).toString('base64');
export const STYLE_VERSION = 'blue-purple-v1';

// Font outlines make the image identical locally and in Cloud Run, with no system-font dependency.
export function wordPaths(w) {
  const run = font.layout(w.text);
  const scale = w.size / font.unitsPerEm;
  const width = run.positions.reduce((sum, p) => sum + p.xAdvance, 0) * scale;
  let pen = -width / (2 * scale);
  const paths = [];
  const bounds = {minX: Infinity, minY: Infinity, maxX: -Infinity, maxY: -Infinity};
  const radians = w.rotation * Math.PI / 180;
  run.glyphs.forEach((glyph, i) => {
    const pos = run.positions[i];
    const gx = pen + pos.xOffset;
    // y is the visual vertical center of capital letters.
    const gy = pos.yOffset - font.capHeight / 2;
    if (glyph.path.commands.length) {
      paths.push(`<path d="${glyph.path.toSVG()}" transform="translate(${gx} ${gy})"/>`);
      for (const x of [glyph.bbox.minX, glyph.bbox.maxX]) for (const y of [glyph.bbox.minY, glyph.bbox.maxY]) {
        const px = (x + gx) * scale, py = -(y + gy) * scale;
        const rx = w.x + px * Math.cos(radians) - py * Math.sin(radians);
        const ry = w.y + px * Math.sin(radians) + py * Math.cos(radians);
        bounds.minX = Math.min(bounds.minX, rx); bounds.maxX = Math.max(bounds.maxX, rx);
        bounds.minY = Math.min(bounds.minY, ry); bounds.maxY = Math.max(bounds.maxY, ry);
      }
    }
    pen += pos.xAdvance;
  });
  if (bounds.minX < 60 || bounds.maxX > 1020 || bounds.minY < 200 || bounds.maxY > 940) {
    throw new Error(`Text would be clipped: ${w.text}`);
  }
  return {bounds, svg: `<g transform="translate(${w.x} ${w.y}) rotate(${w.rotation}) scale(${scale} ${-scale})" fill="#ffffff">${paths.join('')}</g>`};
}

export function renderPuzzle(input) {
  const puzzle = validatePuzzle(input);
  const words = puzzle.words.map(wordPaths);
  for (let i = 0; i < words.length; i++) for (let j = i + 1; j < words.length; j++) {
    const a = words[i].bounds, b = words[j].bounds;
    if (Math.min(a.maxX, b.maxX) - Math.max(a.minX, b.minX) > 3 &&
        Math.min(a.maxY, b.maxY) - Math.max(a.minY, b.minY) > 3) throw new Error('Text overlaps');
  }
  const shapes = puzzle.shapes.map(s => {
    if (s.type === 'rect') return `<rect x="${s.x}" y="${s.y}" width="${s.width}" height="${s.height}"/>`;
    if (s.type === 'ellipse') return `<ellipse cx="${s.x + s.width/2}" cy="${s.y + s.height/2}" rx="${s.width/2}" ry="${s.height/2}"/>`;
    return `<line x1="${s.x}" y1="${s.y}" x2="${s.x+s.width}" y2="${s.y+s.height}"/>`;
  }).join('');
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="1080" height="1080" viewBox="0 0 1080 1080">
    <defs><linearGradient id="bg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#102950"/><stop offset="0.48" stop-color="#344cad"/><stop offset="1" stop-color="#8a46bb"/></linearGradient></defs>
    <rect width="1080" height="1080" fill="url(#bg)"/>
    <image href="data:image/png;base64,${logo}" x="930" y="34" width="116" height="116" opacity="0.18"/>
    <g fill="none" stroke="#fff" stroke-width="7">${shapes}</g>${words.map(w => w.svg).join('')}
  </svg>`;
  const png = Buffer.from(new Resvg(svg, {font: {loadSystemFonts: false}}).render().asPng());
  return {puzzle, svg, png};
}
