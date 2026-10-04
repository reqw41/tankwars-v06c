// Ход целиком на 8080 против turn() эталона. node v06c/test/turn.mjs [N]
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import * as TW from '../../web/tankwars.js';
import { createMachine, loadRom, poke, runUntil, parseSym, printProf } from '../tools/run.mjs';
import { planesToScreen, screenToPlanes } from '../tools/screen.mjs';
import { packPlayer, viewKey, viewPlayer, PL_SIZE, MAX_PLAYERS } from '../tools/player.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const json = (p) => JSON.parse(fs.readFileSync(path.join(ROOT, p), 'utf8'));
TW.init({ barrel: json('web/data/barrel.json'), trig: json('web/data/trig.json') });
TW.setProfile(TW.PROFILE_V06C);
const L = parseSym(path.join(ROOT, 'v06c/build/tw.sym'));
const rom = new Uint8Array(fs.readFileSync(path.join(ROOT, 'v06c/build/tw.rom')));
const machine = createMachine();
const PARAM = 0x80, LIST = 0x8400, RESULT = 0x9600, MODE_TURN = 30;
const N = +process.argv[2] || 150;
const master = new TW.TPRandom(31415);
const u32 = (v) => [v & 255, (v >>> 8) & 255, (v >>> 16) & 255, (v >>> 24) & 255];
const STOP = { max: 0, terrain: 1, tank: 2, bounds: 3 };
const PROF = process.env.PROF ? new Float64Array(0x10000) : null;      // PROF=1 — профиль по меткам
let cases = 0, deaths = 0, hits = 0, cyc = 0, worst = 0;
for (let i = 0; i < N; i++) {
  const n = 2 + master.word(3);
  const rng0 = new TW.TPRandom(master._next());
  const ps = Array.from({ length: n }, (_, k) => { const p = TW.newPlayer(k + 1, 10); p.ctrl = 3; return p; });
  const r0 = TW.roundStart(rng0, ps, master.word(3), 0, [0, 2, 3, 4][master.word(4)]);
  const v = r0.v, bg = r0.bg;
  for (const p of ps) { TW.drawTankBarrel(v, p); p.men = [100, 60, 12, 3, 100][master.word(5)]; p.shield = master.word(5) ? 0 : master.word(250); p.score = master.word(30000); p.damp = master.word(4) ? 0 : master.word(30);
    for (const w of [2, 3, 4]) p.ammo[w] = 3; }
  const shooter = 1 + master.word(n), s = ps[shooter - 1];
  s.weapon = process.env.LASER ? 5 : process.env.W ? process.env.W.split(',').map(Number)[master.word(process.env.W.split(',').length)] : [1, 1, 2, 3, 4, 11, 0, 5][master.word(8)];
  if (s.weapon > 5) s.ammo[s.weapon] = 3;
  if (s.weapon === 5) s.ammo[5] = [1000, 300, 150, 101][master.word(4)];
  // прицел: часть выстрелов — в сторону соседа с подходящей мощностью, часть — случайные
  const tgt = ps[(shooter % n)];
  if (master.word(3)) { s.facing = tgt.x > s.x ? 1 : -1; s.angle = 30 + master.word(50); s.power = Math.min(1000, 60 + Math.abs(tgt.x - s.x) * 2 + master.word(60)); }
  else { s.facing = master.word(2) ? 1 : -1; s.angle = master.word(91); s.power = master.word(1001); }
  if (s.power > 10 * s.men) s.power = 10 * s.men;
  TW.eraseTankBarrel(v, bg, { ...s, angle: shooter === 1 || shooter === n ? 75 : 90, facing: shooter === n ? -1 : 1 }); TW.drawTankBarrel(v, s);
  const fl = { rebound: r0.rebound, crumble: [0, 50, 100][master.word(3)], fall: master.word(4) > 0, xkill: master.word(4) > 0, sound: false, wind: r0.wind, ballVisible: true, trail: false };
  const seed = master._next();
  const list = new Uint8Array(MAX_PLAYERS * PL_SIZE); ps.forEach((p, k) => list.set(packPlayer(p), k * PL_SIZE));
  loadRom(machine, rom);
  const mem0 = new Uint8Array(0x10000); screenToPlanes(v, mem0); poke(machine, 0xA000, mem0.subarray(0xA000));
  const hdr = new Uint8Array(16); hdr[0] = MODE_TURN; hdr.set(u32(seed), 4); hdr[8] = n;
  poke(machine, PARAM, hdr); poke(machine, LIST, list);
  poke(machine, RESULT, [shooter, fl.xkill ? 1 : 0, fl.rebound ? 1 : 0, fl.wind & 255, (fl.wind >> 8) & 255, fl.crumble, fl.fall ? 1 : 0]);
  const rng = new TW.TPRandom(seed), alive0 = ps.filter((p) => p.alive).length;
  const res = TW.turn(v, bg, ps, shooter, rng, fl);
  const r = runUntil(machine, { haltPc: null, maxInsns: 3_000_000_000, prof: PROF });
  const tag = `#${i} игроков=${n} стрелок=${shooter} оружие=${s.weapon} угол=${s.angle} мощность=${s.power} напр=${s.facing} ветер=${fl.wind} стены=${+fl.rebound} осыпание=${fl.crumble} падение=${+fl.fall} xkill=${+fl.xkill} seed=0x${seed.toString(16)}`;
  if (res && r.mem[RESULT] !== STOP[res.stop]) { console.error(`FAIL ${tag}: остановка 8080=${r.mem[RESULT]} эталон=${STOP[res.stop]} (${res.stop})`); process.exit(1); }
  for (let k = 0; k < n; k++) {
    const g = r.mem.slice(LIST + k * PL_SIZE, LIST + (k + 1) * PL_SIZE), w = packPlayer(ps[k]);
    if (viewKey(g) !== viewKey(w)) { const a = viewPlayer(g), b = viewPlayer(w), diff = Object.keys(b).filter((q) => String(a[q]) !== String(b[q]));
      console.error(`FAIL ${tag}: игрок ${k + 1}, поля ${diff.map((q) => `${q}: 8080=${a[q]} эталон=${b[q]}`).join('; ')}`); process.exit(1); }
  }
  const seedGot = (r.mem[PARAM + 4] | (r.mem[PARAM + 5] << 8) | (r.mem[PARAM + 6] << 16) | (r.mem[PARAM + 7] << 24)) >>> 0;
  if (seedGot !== rng.seed) { console.error(`FAIL ${tag}: RandSeed 8080=0x${seedGot.toString(16)} эталон=0x${rng.seed.toString(16)}`); process.exit(1); }
  const g = planesToScreen(r.mem), all = []; for (let k = 0; k < 65536 && all.length < 10; k++) if (g[k] !== v[k]) all.push(`(${k & 255},${k >> 8}) 8080=${g[k]} эталон=${v[k]}`);
  if (all.length) { console.error(`FAIL ${tag}: экран: ${all.join(' ')}`); process.exit(1); }
  cases++; cyc += r.vcycles; worst = Math.max(worst, r.vcycles); deaths += alive0 - ps.filter((p) => p.alive).length; if (res && (res.stop === 'tank' || res.stop === 'terrain')) hits++;
}
console.log(`OK  ход целиком: ${cases} ходов (остановка, записи, RandSeed, экран) совпали; попаданий ${hits}, гибелей ${deaths}; байт ${L.turn_end - L.turn}; в среднем ${(cyc / cases / 3e6).toFixed(2)} с, худший ${(worst / 3e6).toFixed(2)} с при 3 МГц`);
if (PROF) printProf(PROF, L);
