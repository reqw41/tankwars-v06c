// Сравнение round_start (8080) с roundStart эталона. node v06c/test/round.mjs
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import * as TW from '../../web/tankwars.js';
import { createMachine, loadRom, poke, runUntil, parseSym } from '../tools/run.mjs';
import { planesToScreen, firstPixelDiff } from '../tools/screen.mjs';
import { packPlayer, viewKey, viewPlayer, PL_SIZE, MAX_PLAYERS } from '../tools/player.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const json = (p) => JSON.parse(fs.readFileSync(path.join(ROOT, p), 'utf8'));
TW.init({ barrel: json('web/data/barrel.json'), trig: json('web/data/trig.json') });
TW.setProfile(TW.PROFILE_V06C);
const L = parseSym(path.join(ROOT, 'v06c/build/tw.sym'));
const rom = new Uint8Array(fs.readFileSync(path.join(ROOT, 'v06c/build/tw.rom')));
const machine = createMachine();
const PARAM = 0x80, LIST = 0x6400, RESULT = 0x7C00, MODE_ROUND = 24;
const u32 = (v) => [v & 255, (v >>> 8) & 255, (v >>> 16) & 255, (v >>> 24) & 255];
for (const n of ['round_start', 'round_end', 'rs_walls', 'rs_windmode', 'rs_rebound', 'rs_first', 'rs_wind']) if (L[n] === undefined) { console.error('FAIL нет метки ' + n); process.exit(1); }
let s = 77; const rnd = (n) => { s = (Math.imul(s, 1103515245) + 12345) >>> 0; return Math.floor(s / 4294967296 * n); };
let cases = 0; const windSeen = new Set(), rebSeen = new Set();
for (let t = 0; t < 180; t++) {
  const n = 2 + (t % 3), seed = (0x9E3779B1 * (t + 17)) >>> 0, walls = t % 3 === 0 ? rnd(3) : 1, mode = t % 6;
  const ps = Array.from({ length: n }, (_, i) => { const p = TW.newPlayer(i + 1, 10); p.ctrl = 3; p.men = rnd(100) - 20; p.alive = rnd(2) === 1; p.power = rnd(900); p.score = rnd(50000); p.wins = rnd(4);
    p.hist = { n: rnd(9), planned: 0, power: rnd(500), angle: rnd(90), facing: 1, weapon: 1, target: 1 + rnd(n) }; return p; });
  const list = new Uint8Array(MAX_PLAYERS * PL_SIZE); ps.forEach((p, i) => list.set(packPlayer(p), i * PL_SIZE));
  const rng = new TW.TPRandom(seed), r0 = TW.roundStart(rng, ps, walls, 0, mode);
  loadRom(machine, rom);
  const hdr = new Uint8Array(16); hdr[0] = MODE_ROUND; hdr[1] = walls; hdr.set(u32(seed), 4); hdr[8] = n; hdr[14] = mode;
  poke(machine, PARAM, hdr); poke(machine, LIST, list);
  const r = runUntil(machine, { haltPc: null, maxInsns: 60_000_000 });
  const tag = `seed=0x${seed.toString(16)} игроков=${n} стены=${walls} ветер-режим=${mode}`;
  const got = { rebound: r.mem[RESULT], first: r.mem[RESULT + 1], wind: ((r.mem[RESULT + 2] | (r.mem[RESULT + 3] << 8)) << 16) >> 16 };
  const want = { rebound: r0.rebound ? 1 : 0, first: r0.first, wind: r0.wind };
  if (JSON.stringify(got) !== JSON.stringify(want)) { console.error(`FAIL ${tag}: 8080=${JSON.stringify(got)} эталон=${JSON.stringify(want)}`); process.exit(1); }
  for (let i = 0; i < n; i++) {
    const g = r.mem.slice(LIST + i * PL_SIZE, LIST + (i + 1) * PL_SIZE), w = packPlayer(ps[i]);
    if (viewKey(g) !== viewKey(w)) { const a = viewPlayer(g), b = viewPlayer(w), diff = Object.keys(b).filter((k) => String(a[k]) !== String(b[k]));
      console.error(`FAIL ${tag}: игрок ${i + 1}, поля ${diff.map((k) => `${k}: 8080=${a[k]} эталон=${b[k]}`).join('; ')}`); process.exit(1); }
  }
  const seedGot = (r.mem[PARAM + 4] | (r.mem[PARAM + 5] << 8) | (r.mem[PARAM + 6] << 16) | (r.mem[PARAM + 7] << 24)) >>> 0;
  if (seedGot !== rng.seed) { console.error(`FAIL ${tag}: RandSeed 8080=0x${seedGot.toString(16)} эталон=0x${rng.seed.toString(16)}`); process.exit(1); }
  const d = firstPixelDiff(planesToScreen(r.mem), r0.v);
  if (d) { console.error(`FAIL ${tag}: точка (${d.x},${d.y}) на экране 8080=${d.got} эталон=${d.exp}`); process.exit(1); }
  cases++; windSeen.add(Math.sign(r0.wind)); rebSeen.add(want.rebound);
}
console.log(`OK  начало раунда: ${cases} случаев (стены, первый игрок, ветер, записи, RandSeed, экран) совпали; байт ${L.round_end - L.round_start}`);
