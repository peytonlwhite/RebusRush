import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { create } from 'fontkit';
import { Resvg } from '@resvg/resvg-js';
import { validatePuzzle, digest, normalize } from './domain.js';

const require = createRequire(import.meta.url);
const font = create(readFileSync(require.resolve('@fontsource/noto-sans/files/noto-sans-latin-700-normal.woff')));
const logo = readFileSync(new URL('../assets/logo.png', import.meta.url)).toString('base64');
export const STYLE_VERSION = 'varied-gradients-v2';
export const PALETTES = [
  {id: 'blue-purple', colors: ['#102950', '#344cad', '#8a46bb']},
  {id: 'teal-ocean', colors: ['#103b47', '#087c86', '#286aa0']},
  {id: 'purple-coral', colors: ['#412b72', '#89518e', '#b95b70']},
  {id: 'forest-teal', colors: ['#173e36', '#287958', '#26858a']},
  {id: 'midnight-cyan', colors: ['#152e59', '#285d8c', '#238698']},
  {id: 'berry-rose', colors: ['#452857', '#803d7e', '#ae4d78']},
  {id: 'amber-rust', colors: ['#503325', '#986033', '#ac503e']},
  {id: 'indigo-lavender', colors: ['#272e60', '#535a99', '#8163aa']},
];

// Stable per answer: retries and local previews use exactly the same artwork.
export const paletteFor = answer => PALETTES[parseInt(digest(normalize(answer)).slice(0, 8), 16) % PALETTES.length];

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
  const palette = paletteFor(puzzle.answer);
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
    <defs><linearGradient id="bg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="${palette.colors[0]}"/><stop offset="0.48" stop-color="${palette.colors[1]}"/><stop offset="1" stop-color="${palette.colors[2]}"/></linearGradient></defs>
    <rect width="1080" height="1080" fill="url(#bg)"/>
    <image href="data:image/png;base64,${logo}" x="948" y="948" width="98" height="98" opacity="0.18"/>
    <g fill="none" stroke="#fff" stroke-width="7">${shapes}</g>${words.map(w => w.svg).join('')}
  </svg>`;
  const png = Buffer.from(new Resvg(svg, {font: {loadSystemFonts: false}}).render().asPng());
  return {puzzle, svg, png, paletteId: palette.id};
}
