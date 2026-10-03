#!/usr/bin/env node
// Перекодировка FONT эталона (5 столбцов, бит 0 сверху) в 8 байт-строк на знак.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import * as TW from '../../web/tankwars.js';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const out = path.join(ROOT, 'v06c/src/font.inc');
const FONT = TW.FONT;
const lines = ['; 64 знака × 8 рядов; бит 7 — левая точка знакоместа (столбец 0 пуст, глиф в 1..5).'];
for (let g = 0; g < 64; g++) {
  const src = FONT.subarray(g * 5, g * 5 + 5);
  const row = [];
  for (let y = 0; y < 8; y++) {
    let b = 0;
    if (y < 7) {
      for (let col = 0; col < 5; col++) {
        if ((src[col] >> y) & 1) b |= 0x40 >> col;
      }
    }
    row.push('0x' + b.toString(16).padStart(2, '0'));
  }
  lines.push('\tdb\t' + row.join(', '));
}
fs.writeFileSync(out, lines.join('\n') + '\n');
console.log('OK: v06c/src/font.inc (64×8)');
