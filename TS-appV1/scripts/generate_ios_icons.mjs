#!/usr/bin/env node
/**
 * Tạo bộ icon iOS placeholder — chỉ dùng Node (zlib), chạy được trên Windows + GitHub Actions.
 * node scripts/generate_ios_icons.mjs
 */
import { deflateSync } from 'zlib';
import { mkdir, writeFile, access } from 'fs/promises';
import { constants } from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ICONSET = path.join(__dirname, '..', 'ios', 'Runner', 'Assets.xcassets', 'AppIcon.appiconset');

const SIZES = {
  'Icon-App-20x20@2x.png': [40, 40],
  'Icon-App-20x20@3x.png': [60, 60],
  'Icon-App-29x29@1x.png': [29, 29],
  'Icon-App-29x29@2x.png': [58, 58],
  'Icon-App-29x29@3x.png': [87, 87],
  'Icon-App-40x40@1x.png': [40, 40],
  'Icon-App-40x40@2x.png': [80, 80],
  'Icon-App-40x40@3x.png': [120, 120],
  'Icon-App-60x60@2x.png': [120, 120],
  'Icon-App-60x60@3x.png': [180, 180],
  'Icon-App-20x20@1x.png': [20, 20],
  'Icon-App-76x76@1x.png': [76, 76],
  'Icon-App-76x76@2x.png': [152, 152],
  'Icon-App-83.5x83.5@2x.png': [167, 167],
  'Icon-App-1024x1024@1x.png': [1024, 1024],
};

function crc32(buf) {
  let c = 0xffffffff;
  for (let i = 0; i < buf.length; i++) {
    c ^= buf[i];
    for (let k = 0; k < 8; k++) c = c & 1 ? (0xedb88320 ^ (c >>> 1)) : c >>> 1;
  }
  return (c ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const t = Buffer.from(type);
  const body = Buffer.concat([t, data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body));
  return Buffer.concat([len, body, crc]);
}

function pixel(x, y, w, h) {
  const bg = [0, 102, 153];
  const margin = Math.max(2, Math.floor(Math.min(w, h) / 16));
  if (x < margin || y < margin || x >= w - margin || y >= h - margin) return bg;
  const cx = w / 2;
  const cy = h / 2;
  const dx = Math.abs(x - cx);
  const dy = Math.abs(y - cy);
  if (dx < w * 0.22 && dy < h * 0.18) return [255, 255, 255];
  return bg;
}

function makePng(width, height) {
  const rows = [];
  for (let y = 0; y < height; y++) {
    const row = [0];
    for (let x = 0; x < width; x++) {
      const [r, g, b] = pixel(x, y, width, height);
      row.push(r, g, b);
    }
    rows.push(Buffer.from(row));
  }
  const raw = Buffer.concat(rows);
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8;
  ihdr[9] = 2;
  ihdr[10] = 0;
  ihdr[11] = 0;
  ihdr[12] = 0;
  return Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    chunk('IHDR', ihdr),
    chunk('IDAT', deflateSync(raw)),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

async function exists(p) {
  try {
    await access(p, constants.F_OK);
    return true;
  } catch {
    return false;
  }
}

async function main() {
  await mkdir(ICONSET, { recursive: true });
  let created = 0;
  for (const [name, [w, h]] of Object.entries(SIZES)) {
    const out = path.join(ICONSET, name);
    if (await exists(out)) continue;
    await writeFile(out, makePng(w, h));
    console.log('created', name);
    created++;
  }
  console.log(created ? `Done: ${created} icon(s).` : 'All icons already present.');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
