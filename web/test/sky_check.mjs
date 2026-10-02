import { readFileSync } from 'node:fs'; import { inflateSync } from 'node:zlib';
import * as TW from '../tankwars.js';
const idx = JSON.parse(readFileSync('tests/fixtures/t03/placement/index.json', 'utf8'));
for (const c of idx) {
  const bg = new Uint8Array(inflateSync(readFileSync(`tests/fixtures/t03/placement/${c.name}.bg.z`)));
  const sky = TW.skyBackground(); let d = 0; for (let i = 0; i < 64000; i++) if (bg[i] !== sky[i]) d++;
  console.log(c.name, 'отличий неба от буфера фона игры:', d);
}
