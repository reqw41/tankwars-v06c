// Таблицы арифметики для 8080 из web/fixmath.js: синус 0..90° (слова; sin 90° = 65536 хранится как 0) и тангенс 0..89°.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import * as FX from '../../web/fixmath.js';
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
let out = '; Сгенерировано v06c/tools/fx2tab.mjs из web/fixmath.js. Не править руками.\n';
out += 'fx_sin_tab:\t; sin(0..90°)·65536, слова; элемент 90 = 0 означает 65536\n';
for (let d = 0; d <= 90; d += 10) out += '\tdw\t' + Array.from({ length: Math.min(10, 91 - d) }, (_, i) => FX.SIN[d + i] & 0xffff).join(', ') + '\n';
out += 'fx_tan_tab:\t; tan(0..89°) в Q16.16, двойные слова\n';
for (let d = 0; d < 90; d++) { const t = FX.div(FX.SIN[d], FX.SIN[90 - d]); out += `\tdw\t${t & 0xffff}, ${t >>> 16}\n`; }
fs.writeFileSync(path.join(ROOT, 'v06c/src/fx_tab.inc'), out);
