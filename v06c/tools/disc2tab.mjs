// Таблицы закрашенного круга для ядра: для каждого радиуса из игры — полуширина строки dy = 0..r
// (наибольшее |x| точек внешнего кольца ellipsePoints(r, r) в этой строке). Источник — эталон web/tankwars.js.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import * as TW from '../../web/tankwars.js';
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
export const DISC_RADII = [2, 10, 15, 30, 60];           // взрывы 11, 1, 2, 3, 4 и шары грязи 13..16
let out = '; Сгенерировано v06c/tools/disc2tab.mjs из ellipsePoints эталона. Не править руками.\n';
out += 'dk_tabs:\n' + DISC_RADII.map((r) => `\tdb\t${r}\n\tdw\tdk_t${r}\n`).join('') + '\tdb\t0xFF\n';
for (const r of DISC_RADII) {
  const w = new Array(r + 1).fill(0);
  for (const [x, y] of TW.ellipsePoints(0, 0, r, r)) if (y >= 0 && Math.abs(x) > w[y]) w[y] = Math.abs(x);
  out += `dk_t${r}:\n\tdb\t${w.join(', ')}\n`;
}
fs.writeFileSync(path.join(ROOT, 'v06c/src/disc_tab.inc'), out);
