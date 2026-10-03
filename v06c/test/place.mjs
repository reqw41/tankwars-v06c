// Сравнение render_terrain + place_tanks (8080) с эталоном. node v06c/test/place.mjs
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import * as TW from '../../web/tankwars.js';
import { createMachine, loadRom, poke, runUntil, parseSym } from '../tools/run.mjs';
import { planesToScreen, firstPixelDiff } from '../tools/screen.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const json = (p) => JSON.parse(fs.readFileSync(path.join(ROOT, p), 'utf8'));
TW.init({ barrel: json('web/data/barrel.json'), trig: json('web/data/trig.json') });
TW.setProfile(TW.PROFILE_V06C);
const L = parseSym(path.join(ROOT, 'v06c/build/tw.sym'));
const rom = new Uint8Array(fs.readFileSync(path.join(ROOT, 'v06c/build/tw.rom')));
const machine = createMachine();
const PARAM = 0x80, MODE_PLACE = 21;
const u32 = (v) => [v & 255, (v >>> 8) & 255, (v >>> 16) & 255, (v >>> 24) & 255];
for (const n of ['render_terrain', 'place_tanks', 'place_end', 'tk_x', 'tk_y', 'tk_angle', 'tk_facing', 'pl_rebound']) if (L[n] === undefined) { console.error('FAIL нет метки ' + n); process.exit(1); }

let cases = 0, worst = 0;
const seeds = [1, 2, 3, 31337, 487264648, 0xDEADBEEF, 0xFFFFFFFF, 0, 0x80000000, 77];
for (let i = 0; i < 60; i++) seeds.push((0x9E3779B1 * (i + 5)) >>> 0);
for (const seed of seeds) for (const players of [2, 3, 4]) {
  const rebound = (seed + players) & 1;
  // эталон: экран с рамкой, рельеф, расстановка
  const rng = new TW.TPRandom(seed);
  const v = TW.drawBackground(0, rng), bg = new Uint8Array(65536);
  TW.renderTerrain(TW.generateTerrain(rng, players), v);
  const ts = TW.placeTanks(rng, players, v, bg, !!rebound);
  loadRom(machine, rom);
  const hdr = new Uint8Array(16); hdr[0] = MODE_PLACE; hdr[1] = players; hdr.set(u32(seed), 4); hdr[14] = rebound;
  poke(machine, PARAM, hdr);
  const r = runUntil(machine, { haltPc: null, maxInsns: 30_000_000 });
  const tag = `seed=0x${seed.toString(16)} игроков=${players} стены=${rebound}`;
  for (let i = 0; i < players; i++) {
    const got = [r.mem[L.tk_x + i], r.mem[L.tk_y + i], r.mem[L.tk_angle + i], (r.mem[L.tk_facing + i] << 24) >> 24];
    const want = [ts[i].x, ts[i].y, ts[i].angle, ts[i].facing];
    if (got.join() !== want.join()) { console.error(`FAIL ${tag}: танк ${i + 1} [x,y,угол,направление] 8080=${got} эталон=${want}`); process.exit(1); }
  }
  const seedGot = (r.mem[PARAM + 4] | (r.mem[PARAM + 5] << 8) | (r.mem[PARAM + 6] << 16) | (r.mem[PARAM + 7] << 24)) >>> 0;
  if (seedGot !== rng.seed) { console.error(`FAIL ${tag}: RandSeed 8080=0x${seedGot.toString(16)} эталон=0x${rng.seed.toString(16)}`); process.exit(1); }
  const d = firstPixelDiff(planesToScreen(r.mem), v);
  if (d) { console.error(`FAIL ${tag}: точка (${d.x},${d.y}) на экране 8080=${d.got} эталон=${d.exp}`); process.exit(1); }
  cases++; if (r.vcycles > worst) worst = r.vcycles;
}
const LIMIT = 6_000_000;      // расстановка без пошаговой перерисовки танка, рельеф столбцами прямо в плоскость
if (worst > LIMIT) { console.error(`FAIL скорость: худший случай ${worst} vcycles, надо не больше ${LIMIT} (экран и числа при этом совпали)`); process.exit(1); }
console.log(`OK  расстановка: ${cases} случаев (танки, RandSeed, весь экран) совпали; байт ${L.place_end - L.render_terrain}; такты до ${worst} vcycles`);
