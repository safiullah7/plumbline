#!/usr/bin/env node
// Compares each prototype screenshot with the same screen in the built app:
// prototypes/shots/<screen>-<width>.png against qa/shots/<screen>-<width>.png in
// the active phase folder (or the folder given). It compares 8x8 blocks two ways,
// by average colour and by whether the block holds ink (text), so different words
// and data don't count but layout, colour, missing elements and missing text do.
// Writes qa/diff/<screen>-<width>.png and qa/visual.tsv, and prints a table.
// A screen above the threshold is "review": the UX engineer looks at the diff.
// Uses only Node built-ins. Usage:
//   node visual-diff.mjs [phase-dir]          (PLUMBLINE_VISUAL_THRESHOLD=20 = 20%, the default)
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import { pathToFileURL } from 'node:url';

const SIG = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);

export class UnsupportedPng extends Error {}

function paeth(a, b, c) {
  const p = a + b - c, pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c);
  return pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
}

// Decodes a PNG to { width, height, rgb } with alpha blended onto white.
// Supports colour types 0, 2, 3, 4 and 6 at 8 bits (16 bits keep the high byte)
// and palette transparency. Rejects interlaced images and bit depths below 8.
export function decodePng(buf) {
  if (buf.length < 8 || !buf.subarray(0, 8).equals(SIG)) throw new UnsupportedPng('not a PNG file');
  let pos = 8, ihdr = null, plte = null, trns = null;
  const idat = [];
  while (pos + 8 <= buf.length) {
    const len = buf.readUInt32BE(pos);
    const type = buf.toString('latin1', pos + 4, pos + 8);
    const data = buf.subarray(pos + 8, pos + 8 + len);
    pos += 12 + len;
    if (type === 'IHDR') ihdr = data;
    else if (type === 'PLTE') plte = data;
    else if (type === 'tRNS') trns = data;
    else if (type === 'IDAT') idat.push(data);
    else if (type === 'IEND') break;
  }
  if (!ihdr) throw new UnsupportedPng('no IHDR chunk');
  const width = ihdr.readUInt32BE(0), height = ihdr.readUInt32BE(4);
  const [depth, ctype, comp, filt, interlace] = ihdr.subarray(8, 13);
  if (comp !== 0 || filt !== 0) throw new UnsupportedPng('unknown compression or filter method');
  if (interlace !== 0) throw new UnsupportedPng('interlaced PNGs are not supported');
  const channels = { 0: 1, 2: 3, 3: 1, 4: 2, 6: 4 }[ctype];
  if (!channels) throw new UnsupportedPng(`colour type ${ctype} is not supported`);
  if (depth !== 8 && !(depth === 16 && ctype !== 3)) throw new UnsupportedPng(`bit depth ${depth} is not supported`);
  if (ctype === 3 && !plte) throw new UnsupportedPng('palette image without PLTE');

  const bpp = (channels * depth) / 8;
  const stride = width * bpp;
  const raw = zlib.inflateSync(Buffer.concat(idat));
  if (raw.length < height * (stride + 1)) throw new UnsupportedPng('truncated image data');
  const px = Buffer.alloc(height * stride);
  let prev = Buffer.alloc(stride);
  for (let y = 0; y < height; y++) {
    const ft = raw[y * (stride + 1)];
    const line = raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1));
    const cur = px.subarray(y * stride, (y + 1) * stride);
    for (let i = 0; i < stride; i++) {
      const a = i >= bpp ? cur[i - bpp] : 0, b = prev[i], c = i >= bpp ? prev[i - bpp] : 0;
      let v = line[i];
      if (ft === 1) v += a;
      else if (ft === 2) v += b;
      else if (ft === 3) v += (a + b) >> 1;
      else if (ft === 4) v += paeth(a, b, c);
      else if (ft !== 0) throw new UnsupportedPng(`bad filter type ${ft} on row ${y}`);
      cur[i] = v & 0xff;
    }
    prev = cur;
  }

  const step = depth / 8; // 16-bit samples: take the high byte
  const rgb = Buffer.alloc(width * height * 3);
  for (let p = 0; p < width * height; p++) {
    const o = p * bpp;
    const s = (k) => px[o + k * step];
    let r, g, b, al = 255;
    if (ctype === 0) {
      r = g = b = s(0);
      if (trns && depth === 8 && trns.length >= 2 && s(0) === trns[1]) al = 0;
    } else if (ctype === 2) {
      r = s(0); g = s(1); b = s(2);
      if (trns && depth === 8 && trns.length >= 6 && r === trns[1] && g === trns[3] && b === trns[5]) al = 0;
    } else if (ctype === 3) {
      const idx = px[o];
      r = plte[idx * 3]; g = plte[idx * 3 + 1]; b = plte[idx * 3 + 2];
      if (trns && idx < trns.length) al = trns[idx];
    } else if (ctype === 4) {
      r = g = b = s(0); al = s(1);
    } else {
      r = s(0); g = s(1); b = s(2); al = s(3);
    }
    rgb[p * 3] = Math.round((r * al + 255 * (255 - al)) / 255);
    rgb[p * 3 + 1] = Math.round((g * al + 255 * (255 - al)) / 255);
    rgb[p * 3 + 2] = Math.round((b * al + 255 * (255 - al)) / 255);
  }
  return { width, height, rgb };
}

const CRC_TABLE = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return t;
})();

function crc32(buf) {
  let c = 0xffffffff;
  for (const byte of buf) c = CRC_TABLE[(c ^ byte) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

export function pngChunk(type, data) {
  const head = Buffer.alloc(8);
  head.writeUInt32BE(data.length, 0);
  head.write(type, 4, 'latin1');
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(Buffer.concat([head.subarray(4), data])), 0);
  return Buffer.concat([head, data, crc]);
}

// Encodes 8-bit RGB pixels as a PNG. `filters` lists the filter type per row,
// cycling; the default (0) is fine for output, the self-test cycles all five.
export function encodePng(width, height, rgb, { filters = [0] } = {}) {
  const bpp = 3, stride = width * 3;
  const raw = Buffer.alloc(height * (stride + 1));
  let prev = Buffer.alloc(stride);
  for (let y = 0; y < height; y++) {
    const ft = filters[y % filters.length];
    raw[y * (stride + 1)] = ft;
    const cur = rgb.subarray(y * stride, (y + 1) * stride);
    for (let i = 0; i < stride; i++) {
      const a = i >= bpp ? cur[i - bpp] : 0, b = prev[i], c = i >= bpp ? prev[i - bpp] : 0;
      const pred = ft === 1 ? a : ft === 2 ? b : ft === 3 ? (a + b) >> 1 : ft === 4 ? paeth(a, b, c) : 0;
      raw[y * (stride + 1) + 1 + i] = (cur[i] - pred) & 0xff;
    }
    prev = cur;
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8; ihdr[9] = 2; // 8-bit RGB, deflate, no interlace
  return Buffer.concat([SIG, pngChunk('IHDR', ihdr), pngChunk('IDAT', zlib.deflateSync(raw)), pngChunk('IEND', Buffer.alloc(0))]);
}

// YIQ distance between two colours, as a fraction of the largest possible.
function yiqDelta(r1, g1, b1, r2, g2, b2) {
  const dr = r1 - r2, dg = g1 - g2, db = b1 - b2;
  const y = dr * 0.29889531 + dg * 0.58662247 + db * 0.11448223;
  const i = dr * 0.59597799 - dg * 0.2741761 - db * 0.32180189;
  const q = dr * 0.21147017 - dg * 0.52261711 + db * 0.31114694;
  return Math.sqrt((0.5053 * y * y + 0.299 * i * i + 0.1957 * q * q) / 35215);
}

// The colour most blocks share in an image: its page background.
function background(img, block) {
  const counts = new Map();
  for (let y = 0; y < img.height; y += block) {
    for (let x = 0; x < img.width; x += block) {
      const o = (y * img.width + x) * 3;
      const key = (img.rgb[o] >> 3) << 10 | (img.rgb[o + 1] >> 3) << 5 | (img.rgb[o + 2] >> 3);
      counts.set(key, (counts.get(key) || 0) + 1);
    }
  }
  let best = 0, bestCount = -1;
  for (const [k, c] of counts) if (c > bestCount) { best = k; bestCount = c; }
  return [((best >> 10) & 31) * 8 + 4, ((best >> 5) & 31) * 8 + 4, (best & 31) * 8 + 4];
}

// A block "has ink" when the standard deviation of its luma is above this (of
// 255). Flat fills, soft gradients and shadows sit well under it; a few glyph
// strokes on a background sit well over it.
const INK_SD = 12;

// Compares two decoded images by two signals per 8x8 block. The first is the
// block's average colour, which catches moved, recoloured and missing boxes but
// barely sees thin text. The second is ink presence (luma spread above INK_SD),
// which catches a missing text column. A block whose ink flips between the two
// images counts only when at least 2 of its 8 neighbours flip as well, so a lone
// speck doesn't. Returns the fraction of content blocks (not plain background in
// either image) that differ by either signal, so empty space doesn't dilute a
// layout change, plus a per-block mask; or size-mismatch.
export function compareImages(a, b, { block = 8, tolerance = 0.1 } = {}) {
  if (a.width !== b.width || a.height !== b.height) return { sizeMismatch: true };
  const bw = Math.ceil(a.width / block), bh = Math.ceil(a.height / block);
  const mask = new Uint8Array(bw * bh);
  const content = new Uint8Array(bw * bh);
  const flip = new Uint8Array(bw * bh);
  const bgA = background(a, block), bgB = background(b, block);
  for (let by = 0; by < bh; by++) {
    for (let bx = 0; bx < bw; bx++) {
      const sum = [0, 0, 0, 0, 0, 0];
      let n = 0, ya = 0, yaa = 0, yb = 0, ybb = 0;
      for (let y = by * block; y < Math.min((by + 1) * block, a.height); y++) {
        for (let x = bx * block; x < Math.min((bx + 1) * block, a.width); x++) {
          const o = (y * a.width + x) * 3;
          sum[0] += a.rgb[o]; sum[1] += a.rgb[o + 1]; sum[2] += a.rgb[o + 2];
          sum[3] += b.rgb[o]; sum[4] += b.rgb[o + 1]; sum[5] += b.rgb[o + 2];
          const la = 0.299 * a.rgb[o] + 0.587 * a.rgb[o + 1] + 0.114 * a.rgb[o + 2];
          const lb = 0.299 * b.rgb[o] + 0.587 * b.rgb[o + 1] + 0.114 * b.rgb[o + 2];
          ya += la; yaa += la * la; yb += lb; ybb += lb * lb;
          n++;
        }
      }
      const m = sum.map((v) => v / n);
      const inkA = Math.sqrt(Math.max(0, yaa / n - (ya / n) ** 2)) > INK_SD;
      const inkB = Math.sqrt(Math.max(0, ybb / n - (yb / n) ** 2)) > INK_SD;
      const i = by * bw + bx;
      flip[i] = inkA !== inkB ? 1 : 0;
      if (yiqDelta(m[0], m[1], m[2], bgA[0], bgA[1], bgA[2]) > 0.03
        || yiqDelta(m[3], m[4], m[5], bgB[0], bgB[1], bgB[2]) > 0.03) {
        content[i] = 1;
        if (yiqDelta(m[0], m[1], m[2], m[3], m[4], m[5]) > tolerance) mask[i] = 1;
      }
    }
  }
  let differing = 0, contentCount = 0;
  for (let by = 0; by < bh; by++) {
    for (let bx = 0; bx < bw; bx++) {
      const i = by * bw + bx;
      if (!content[i]) continue;
      contentCount++;
      if (flip[i] && !mask[i]) {
        let near = 0; // flipped neighbours, of up to 8
        for (let dy = -1; dy <= 1; dy++) {
          for (let dx = -1; dx <= 1; dx++) {
            const x = bx + dx, y = by + dy;
            if ((dx || dy) && x >= 0 && x < bw && y >= 0 && y < bh) near += flip[y * bw + x];
          }
        }
        if (near >= 2) mask[i] = 1;
      }
      if (mask[i]) differing++;
    }
  }
  return { sizeMismatch: false, different: contentCount ? differing / contentCount : 0, mask, bw, bh, block };
}

// The app shot, faded, with differing blocks tinted red.
export function diffImage(app, cmp) {
  const out = Buffer.alloc(app.rgb.length);
  for (let p = 0; p < app.width * app.height; p++) {
    const x = p % app.width, y = (p / app.width) | 0;
    const hit = cmp.mask[((y / cmp.block) | 0) * cmp.bw + ((x / cmp.block) | 0)];
    const gray = 0.299 * app.rgb[p * 3] + 0.587 * app.rgb[p * 3 + 1] + 0.114 * app.rgb[p * 3 + 2];
    const faded = 255 - (255 - gray) * 0.35;
    out[p * 3] = hit ? Math.round(faded * 0.4 + 255 * 0.6) : Math.round(faded);
    out[p * 3 + 1] = hit ? Math.round(faded * 0.4) : Math.round(faded);
    out[p * 3 + 2] = hit ? Math.round(faded * 0.4) : Math.round(faded);
  }
  return out;
}

function activePhaseDir() {
  const root = process.env.CLAUDE_PROJECT_DIR || process.cwd();
  const pointer = path.join(root, '.claude', 'current-phase');
  if (!fs.existsSync(pointer)) return null;
  return path.join(root, fs.readFileSync(pointer, 'utf8').split(/\r?\n/)[0].trim());
}

function main() {
  const dir = process.argv[2] ? path.resolve(process.argv[2]) : activePhaseDir();
  if (!dir || !fs.existsSync(dir)) {
    console.error('visual-diff: no phase folder (pass one, or set .claude/current-phase)');
    process.exit(1);
  }
  const threshold = Number(process.env.PLUMBLINE_VISUAL_THRESHOLD || 20);
  const protoDir = path.join(dir, 'prototypes', 'shots');
  const appDir = path.join(dir, 'qa', 'shots');
  const diffDir = path.join(dir, 'qa', 'diff');
  const shots = fs.existsSync(protoDir) ? fs.readdirSync(protoDir).filter((f) => /-\d+\.png$/i.test(f)).sort() : [];
  if (!shots.length) {
    console.log('visual-diff: no prototype screenshots in prototypes/shots; nothing to compare.');
    return;
  }
  fs.mkdirSync(diffDir, { recursive: true });
  const rows = [];
  let unreadable = false;
  for (const file of shots) {
    const [, screen, width] = file.match(/^(.*)-(\d+)\.png$/i);
    const appFile = path.join(appDir, file);
    const row = { screen, width, different: '', result: 'missing', diff: '' };
    if (fs.existsSync(appFile)) {
      try {
        const proto = decodePng(fs.readFileSync(path.join(protoDir, file)));
        const app = decodePng(fs.readFileSync(appFile));
        const cmp = compareImages(proto, app);
        if (cmp.sizeMismatch) {
          row.result = 'size-mismatch';
          row.different = `${proto.width}x${proto.height} vs ${app.width}x${app.height}`;
        } else {
          const pct = cmp.different * 100;
          row.different = `${pct.toFixed(1)}%`;
          row.result = pct > threshold ? 'review' : 'ok';
          fs.writeFileSync(path.join(diffDir, file), encodePng(app.width, app.height, diffImage(app, cmp)));
          row.diff = `qa/diff/${file}`;
        }
      } catch (err) {
        if (!(err instanceof UnsupportedPng)) throw err;
        row.result = 'unreadable';
        row.different = err.message;
        unreadable = true;
      }
    }
    rows.push(row);
  }
  const tsv = rows.map((r) => [r.screen, r.width, r.different, `${threshold}%`, r.result, r.diff].join('\t')).join('\n');
  fs.writeFileSync(path.join(dir, 'qa', 'visual.tsv'), tsv + '\n');
  console.log('| Screen | Width | Different | Threshold | Result | Diff |');
  console.log('| --- | --- | --- | --- | --- | --- |');
  for (const r of rows) console.log(`| ${r.screen} | ${r.width} | ${r.different} | ${threshold}% | ${r.result} | ${r.diff} |`);
  if (unreadable) process.exit(2);
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) main();
