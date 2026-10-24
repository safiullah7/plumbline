// Self-test for visual-diff.mjs and capture.mjs; run by tests/scripts-selftest.sh.
// Prints "ok    <name>" or "FAIL  <name>" per check. The browser test runs only
// with PLUMBLINE_BROWSER_TEST=1 and PLUMBLINE_BROWSER_FROM=<folder with
// playwright-core and axe-core installed>.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import zlib from 'node:zlib';
import { execFileSync, spawnSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const SCRIPTS = path.join(ROOT, 'plugins', 'plumbline', 'scripts');
const { decodePng, encodePng, compareImages, pngChunk, UnsupportedPng } =
  await import(pathToFileURL(path.join(SCRIPTS, 'visual-diff.mjs')).href);

const check = (name, cond) => console.log(`${cond ? 'ok   ' : 'FAIL '} ${name}`);
const throws = (fn, cls) => { try { fn(); return false; } catch (e) { return e instanceof cls; } };
const SIG = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);

// A PNG from raw (already filtered) scanlines, for formats our encoder doesn't write.
function rawPng(width, height, depth, ctype, rows, { interlace = 0, extra = [] } = {}) {
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0); ihdr.writeUInt32BE(height, 4);
  ihdr[8] = depth; ihdr[9] = ctype; ihdr[12] = interlace;
  return Buffer.concat([SIG, pngChunk('IHDR', ihdr), ...extra,
    pngChunk('IDAT', zlib.deflateSync(Buffer.concat(rows))), pngChunk('IEND', Buffer.alloc(0))]);
}
const pixel = (img, x, y) => Array.from(img.rgb.subarray((y * img.width + x) * 3, (y * img.width + x) * 3 + 3));
const same = (a, b) => a.length === b.length && a.every((v, i) => v === b[i]);

// Encoder/decoder round trip through every filter type.
{
  const w = 37, h = 23, rgb = Buffer.alloc(w * h * 3);
  for (let i = 0; i < rgb.length; i++) rgb[i] = (i * 7919 + (i >> 3) * 31) & 255;
  const back = decodePng(encodePng(w, h, rgb, { filters: [0, 1, 2, 3, 4] }));
  check('visual-diff: PNG round trip through filters 0-4', back.width === w && back.height === h && back.rgb.equals(rgb));
}

// A real browser screenshot (headless Edge) with known colours.
{
  const img = decodePng(fs.readFileSync(path.join(ROOT, 'tests', 'fixtures', 'chromium-sample.png')));
  check('visual-diff: decodes a real browser screenshot',
    same(pixel(img, 20, 20), [255, 0, 0]) && same(pixel(img, 60, 20), [0, 170, 85])
    && same(pixel(img, 40, 50), [0x12, 0x34, 0x56]) && same(pixel(img, 100, 70), [255, 255, 255]));
}

// Palette with transparency, 16-bit RGB, grey + alpha.
{
  const plte = pngChunk('PLTE', Buffer.from([255, 0, 0, 0, 0, 255]));
  const trns = pngChunk('tRNS', Buffer.from([255, 0]));
  const pal = decodePng(rawPng(2, 1, 8, 3, [Buffer.from([0, 0, 1])], { extra: [plte, trns] }));
  check('visual-diff: palette image with transparency', same(pixel(pal, 0, 0), [255, 0, 0]) && same(pixel(pal, 1, 0), [255, 255, 255]));
  const deep = decodePng(rawPng(1, 1, 16, 2, [Buffer.from([0, 0x12, 0xff, 0x34, 0x00, 0x56, 0x00])]));
  check('visual-diff: 16-bit image keeps the high byte', same(pixel(deep, 0, 0), [0x12, 0x34, 0x56]));
  const ga = decodePng(rawPng(1, 1, 8, 4, [Buffer.from([0, 0, 0])]));
  check('visual-diff: transparent pixels blend onto white', same(pixel(ga, 0, 0), [255, 255, 255]));
  check('visual-diff: rejects interlaced images', throws(() => decodePng(rawPng(1, 1, 8, 2, [Buffer.from([0, 1, 2, 3])], { interlace: 1 })), UnsupportedPng));
  check('visual-diff: rejects bit depth 4', throws(() => decodePng(rawPng(2, 1, 4, 0, [Buffer.from([0, 0x12])])), UnsupportedPng));
}

// Block comparison: identical, a glyph-sized speck, a moved box, a size mismatch.
const W = 160, H = 120;
const canvas = () => Buffer.alloc(W * H * 3, 255);
const box = (img, x0, y0, bw, bh, c) => {
  for (let y = y0; y < y0 + bh; y++) for (let x = x0; x < x0 + bw; x++) img.set(c, (y * W + x) * 3);
  return img;
};
const a = box(canvas(), 10, 10, 60, 30, [30, 60, 200]);
{
  const img = (rgb) => ({ width: W, height: H, rgb });
  check('visual-diff: identical images differ by 0%', compareImages(img(a), img(Buffer.from(a))).different === 0);
  check('visual-diff: a glyph-sized change is ignored', compareImages(img(a), img(box(Buffer.from(a), 120, 90, 2, 2, [0, 0, 0]))).different === 0);
  const moved = compareImages(img(a), img(box(canvas(), 80, 60, 60, 30, [30, 60, 200])));
  check('visual-diff: a moved element is flagged', moved.different > 0.2);
  check('visual-diff: different sizes are a size mismatch', compareImages(img(a), { width: W, height: 8, rgb: a.subarray(0, W * 8 * 3) }).sizeMismatch);
}

// Text presence (PL-104): a page with a header and two columns of thin text
// (cells of random 1px marks, 18% ink, with word gaps). The colour average alone
// scores a missing column at about 4% here; the ink signal brings it over 20%.
{
  const TW = 320, TH = 200;
  const textPage = ({ seed = 1, columns = [0, 1], speck = false } = {}) => {
    let s = seed >>> 0;
    const rnd = () => { s = (Math.imul(s, 1664525) + 1013904223) >>> 0; return s / 4294967296; };
    const rgb = Buffer.alloc(TW * TH * 3, 255);
    const px = (x, y, c) => rgb.set(c, (y * TW + x) * 3);
    for (let y = 0; y < 24; y++) for (let x = 0; x < TW; x++) px(x, y, [31, 42, 68]);
    for (const col of columns) {
      for (let line = 0; line < 11; line++) {
        for (let cell = 0; cell < 22; cell++) {
          if (rnd() < 0.15) continue; // word gap
          for (let y = 0; y < 9; y++) {
            for (let x = 0; x < 5; x++) if (rnd() < 0.18) px(16 + col * 156 + cell * 6 + x, 40 + line * 14 + y, [95, 95, 95]);
          }
        }
      }
    }
    if (speck) for (const [x, y] of [[300, 190], [301, 190], [300, 191], [301, 191]]) px(x, y, [0, 0, 0]);
    return { width: TW, height: TH, rgb };
  };
  const score = (x, y) => compareImages(x, y).different;
  const page = textPage();
  check('visual-diff: identical text pages differ by 0%', score(page, textPage()) === 0);
  check('visual-diff: a missing text column is flagged', score(page, textPage({ columns: [0] })) >= 0.2);
  check('visual-diff: a lone speck on a text page is ignored', score(page, textPage({ speck: true })) < 0.2);
  check('visual-diff: different wording in the same layout stays under 20%',
    [2, 3, 4].every((seed) => score(page, textPage({ seed })) < 0.2));
}

// The command line on a phase folder: rows, diff images and visual.tsv.
{
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'plumbline-visual-'));
  for (const d of ['prototypes/shots', 'qa/shots']) fs.mkdirSync(path.join(dir, d), { recursive: true });
  const write = (rel, rgb) => fs.writeFileSync(path.join(dir, rel), encodePng(W, H, rgb));
  write('prototypes/shots/rooms-list-390.png', a);
  write('qa/shots/rooms-list-390.png', a);
  write('prototypes/shots/rooms-list-1280.png', a);
  write('qa/shots/rooms-list-1280.png', box(canvas(), 80, 60, 60, 30, [30, 60, 200]));
  write('prototypes/shots/add-room-390.png', a);
  const run = spawnSync(process.execPath, [path.join(SCRIPTS, 'visual-diff.mjs'), dir], { encoding: 'utf8' });
  const tsv = fs.readFileSync(path.join(dir, 'qa', 'visual.tsv'), 'utf8');
  check('visual-diff: command exits 0', run.status === 0);
  check('visual-diff: unchanged screen is ok', /rooms-list\t390\t0\.0%\t20%\tok\tqa\/diff\/rooms-list-390\.png/.test(tsv));
  check('visual-diff: changed screen is review', /rooms-list\t1280\t[\d.]+%\t20%\treview/.test(tsv));
  check('visual-diff: screen without an app shot is missing', /add-room\t390\t\t20%\tmissing/.test(tsv));
  check('visual-diff: writes diff images', fs.existsSync(path.join(dir, 'qa', 'diff', 'rooms-list-1280.png')));
  fs.rmSync(dir, { recursive: true, force: true });
}

// capture.mjs without Playwright says SKIPPED and exits 0.
{
  const empty = fs.mkdtempSync(path.join(os.tmpdir(), 'plumbline-nopw-'));
  const env = { ...process.env };
  delete env.CLAUDE_PLUGIN_DATA;
  const run = spawnSync(process.execPath, [path.join(SCRIPTS, 'capture.mjs'), '--out', path.join(empty, 'shots'), 'x=https://example.com'],
    { encoding: 'utf8', cwd: empty, env });
  check('capture: without Playwright prints SKIPPED and exits 0', run.status === 0 && /^SKIPPED: Playwright not found/m.test(run.stdout));
  fs.rmSync(empty, { recursive: true, force: true });
}

// Opt-in: a real browser run on fixture pages.
if (process.env.PLUMBLINE_BROWSER_TEST === '1') {
  const from = process.env.PLUMBLINE_BROWSER_FROM || process.cwd();
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'plumbline-browser-'));
  const page = (body, extraCss = '') => `<!doctype html><html lang="en"><head><meta charset="utf-8"><title>Rooms</title><style>body{font-family:sans-serif;margin:0}header{background:#1f2a44;color:#fff;padding:16px}main{padding:16px}.row{padding:12px;border-bottom:1px solid #ddd}${extraCss}</style></head><body>${body}</body></html>`;
  const content = '<header><h1>Rooms</h1></header><main><button>Add room</button><div class="row">Room 1</div><div class="row">Room 2</div></main>';
  fs.mkdirSync(path.join(dir, 'prototypes'), { recursive: true });
  fs.writeFileSync(path.join(dir, 'prototypes', 'rooms.html'), page(content));
  fs.writeFileSync(path.join(dir, 'app.html'), page(`<img src="logo.png">${content}`, 'header,main{margin-left:240px}'));
  const cap = (args) => execFileSync(process.execPath, [path.join(SCRIPTS, 'capture.mjs'), '--from', from, ...args], { encoding: 'utf8', cwd: dir });
  const out1 = cap(['--out', path.join(dir, 'prototypes', 'shots'), `rooms=${path.join(dir, 'prototypes', 'rooms.html')}`]);
  const out2 = cap(['--out', path.join(dir, 'qa', 'shots'), '--a11y', path.join(dir, 'qa', 'a11y'), `rooms=${path.join(dir, 'app.html')}`]);
  check('browser: captures both widths', /ok rooms-390/.test(out1) && /ok rooms-1280/.test(out2));
  check('browser: axe finds the image without alt text', /critical [1-9]/.test(out2));
  spawnSync(process.execPath, [path.join(SCRIPTS, 'visual-diff.mjs'), dir], { encoding: 'utf8' });
  const tsv = fs.readFileSync(path.join(dir, 'qa', 'visual.tsv'), 'utf8');
  check('browser: shifted layout is review at both widths', (tsv.match(/\treview\t/g) || []).length === 2);
  fs.rmSync(dir, { recursive: true, force: true });
}
