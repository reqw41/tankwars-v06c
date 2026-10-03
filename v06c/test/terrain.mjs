// Сравнение gen_terrain (8080) с generateTerrain эталона. node v06c/test/terrain.mjs
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import * as TW from '../../web/tankwars.js';
import { createMachine, loadRom, poke, runUntil, parseSym } from '../tools/run.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const json = (p) => JSON.parse(fs.readFileSync(path.join(ROOT, p), 'utf8'));
TW.init({ barrel: json('web/data/barrel.json'), trig: json('web/data/trig.json') });
TW.setProfile(TW.PROFILE_V06C);
const P = TW.PROFILE_V06C, L = parseSym(path.join(ROOT, 'v06c/build/tw.sym'));
const rom = new Uint8Array(fs.readFileSync(path.join(ROOT, 'v06c/build/tw.rom')));
const machine = createMachine();
const PARAM = 0x80, MODE_TERRAIN = 19;
const u32 = (v) => [v & 255, (v >>> 8) & 255, (v >>> 16) & 255, (v >>> 24) & 255];
for (const n of ['gen_terrain', 'terr_top', 'terr_h']) if (L[n] === undefined) { console.error('FAIL нет метки ' + n); process.exit(1); }

let cases = 0, worst = 0;
const seeds = [1, 2, 3, 31337, 487264648, 0xDEADBEEF, 0xFFFFFFFF, 0, 0x80000000, 77];
for (let i = 0; i < 90; i++) seeds.push((0x9E3779B1 * (i + 11)) >>> 0);
for (const seed of seeds) for (const players of [2, 3, 4]) {
  const rng = new TW.TPRandom(seed), t = TW.generateTerrain(rng, players);
  const want = new Uint8Array(256).fill(0xff);
  for (const [x, top] of t.cols) if (x >= 0 && x < 256 && top < want[x]) want[x] = top;
  loadRom(machine, rom);
  const hdr = new Uint8Array(16); hdr[0] = MODE_TERRAIN; hdr[1] = players; hdr.set(u32(seed), 4);
  poke(machine, PARAM, hdr);
  const r = runUntil(machine, { haltPc: null, maxInsns: 5_000_000 });
  const got = r.mem.subarray(L.terr_top, L.terr_top + 256);
  const hGot = (r.mem[L.terr_h] | (r.mem[L.terr_h + 1] << 8)) << 16 >> 16;
  const seedGot = (r.mem[PARAM + 4] | (r.mem[PARAM + 5] << 8) | (r.mem[PARAM + 6] << 16) | (r.mem[PARAM + 7] << 24)) >>> 0;
  const tag = `seed=0x${seed.toString(16)} игроков=${players}`;
  for (let x = 0; x < 256; x++) if (got[x] !== want[x]) { console.error(`FAIL ${tag}: столбец x=${x} top 8080=${got[x]} эталон=${want[x]}`); process.exit(1); }
  if (hGot !== t.hFinal) { console.error(`FAIL ${tag}: итоговая высота 8080=${hGot} эталон=${t.hFinal}`); process.exit(1); }
  if (seedGot !== rng.seed) { console.error(`FAIL ${tag}: RandSeed 8080=0x${seedGot.toString(16)} эталон=0x${rng.seed.toString(16)}`); process.exit(1); }
  cases++; if (r.vcycles > worst) worst = r.vcycles;
}
console.log(`OK  рельеф: ${cases} случаев (столбцы, высота, RandSeed) совпали; байт ${L.gen_terrain_end - L.gen_terrain}; такты до ${worst} vcycles`);
