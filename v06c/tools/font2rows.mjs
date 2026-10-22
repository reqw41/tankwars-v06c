#!/usr/bin/env node
// Перекодировка FONT эталона (5 столбцов, бит 0 сверху) в 8 байт-строк на знак.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import * as TW from '../../web/tankwars.js';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const out = path.join(ROOT, 'v06c/src/font.inc');
const FONT = TW.FONT;
const N = FONT.length / 5;      // 96: знаки 20h..5Fh и русские А..Я
const lines = [
  `; ${N} знаков × 8 рядов; бит 7 — левая точка знакоместа (столбец 0 пуст, глиф в 1..5).`,
  '; Файл делает v06c/tools/font2rows.mjs из таблицы FONT эталона web/tankwars.js (5 байт-столбцов на знак, бит 0 —',
  '; верхняя строка); руками не править. Знаки 0..63 — коды 20h..5Fh, 64..95 — русские А..Я (CP866 80h..9Fh).',
  '; Строка 7 знакоместа пуста: межстрочный промежуток. Выводит text.asm.',
];
for (let g = 0; g < N; g++) {
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
console.log(`OK: v06c/src/font.inc (${N}×8)`);
