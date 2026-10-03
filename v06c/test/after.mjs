// Перерисовка танков, осыпание и падение после выстрела (8080) против эталона. node v06c/test/after.mjs [N]
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import * as TW from '../../web/tankwars.js';
import { createMachine, loadRom, poke, runUntil, parseSym } from '../tools/run.mjs';
import { planesToScreen, firstPixelDiff, screenToPlanes } from '../tools/screen.mjs';
import { packPlayer, viewKey, viewPlayer, PL_SIZE, MAX_PLAYERS } from '../tools/player.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const json = (p) => JSON.parse(fs.readFileSync(path.join(ROOT, p), 'utf8'));
TW.init({ barrel: json('web/data/barrel.json'), trig: json('web/data/trig.json') });
TW.setProfile(TW.PROFILE_V06C);
const P = TW.PROFILE_V06C, L = parseSym(path.join(ROOT, 'v06c/build/tw.sym'));
const rom = new Uint8Array(fs.readFileSync(path.join(ROOT, 'v06c/build/tw.rom')));
const machine = createMachine();
const PARAM = 0x80, LIST = 0x4000, MODE_AFTER = 26;
const N = +process.argv[2] || 200;
const master = new TW.TPRandom(4242);
const u32 = (v) => [v & 255, (v >>> 8) & 255, (v >>> 16) & 255, (v >>> 24) & 255];
for (const n of ['after_shot', 'after_end', 'rnd_le_pct', 'as_crumble', 'as_fall', 'as_rebound']) if (L[n] === undefined) { console.error('FAIL нет метки ' + n); process.exit(1); }
let cases = 0, fell = 0, crumbled = 0, worst = 0;
for (let i = 0; i < N; i++) {
  const n = 2 + master.word(3);
  const rng0 = new TW.TPRandom(master._next());
  const ps = Array.from({ length: n }, (_, k) => { const p = TW.newPlayer(k + 1, 10); p.ctrl = 3; return p; });
  const r0 = TW.roundStart(rng0, ps, master.word(3), 0, 2);
  const v = r0.v, bg = r0.bg;
  // воронки под танками и рядом: танки повисают, земля нависает
  for (let k = 0; k < 1 + master.word(3); k++) { const t = ps[master.word(n)]; TW.disc(v, bg, t.x - P.X0 + master.word(31) - 15, t.y - P.Y0 + master.word(21) - 4, [10, 15, 30][master.word(3)], null); }
  for (const p of ps) { p.men = 1 + master.word(100); p.damp = master.word(3) ? 0 : master.word(40); p.angle = master.word(91); p.facing = master.word(2) ? 1 : -1; if (master.word(7) === 0) p.alive = false; }
  const crumblePct = [0, 50, 100, 10][master.word(4)], fall = master.word(5) ? 1 : 0, rebound = r0.rebound ? 1 : 0, seed = master._next();
  const list = new Uint8Array(MAX_PLAYERS * PL_SIZE); ps.forEach((p, k) => list.set(packPlayer(p), k * PL_SIZE));
  loadRom(machine, rom);
  const mem0 = new Uint8Array(0x10000); screenToPlanes(v, mem0); poke(machine, 0xA000, mem0.subarray(0xA000));
  const hdr = new Uint8Array(16); hdr[0] = MODE_AFTER; hdr[1] = crumblePct; hdr.set(u32(seed), 4); hdr[8] = n; hdr[13] = rebound; hdr[14] = fall;
  poke(machine, PARAM, hdr); poke(machine, LIST, list);
  // эталон: то же, что в начале afterShot
  const rng = new TW.TPRandom(seed), y0 = ps.map((p) => p.y), before = new Uint8Array(v);
  for (const p of ps) TW.drawTankBarrel(v, p);
  if (crumblePct > 0) { if (TW.crumbleGate(v, bg, rng, crumblePct, !!rebound)) crumbled++; }
  if (fall) TW.tanksFall(v, bg, ps, rng, !!rebound);
  const r = runUntil(machine, { haltPc: null, maxInsns: 400_000_000 });
  const tag = `#${i} игроков=${n} осыпание=${crumblePct}% падение=${fall} стены=${rebound} seed=0x${seed.toString(16)}`;
  for (let k = 0; k < n; k++) {
    const g = r.mem.slice(LIST + k * PL_SIZE, LIST + (k + 1) * PL_SIZE), w = packPlayer(ps[k]);
    if (viewKey(g) !== viewKey(w)) { const a = viewPlayer(g), b = viewPlayer(w), diff = Object.keys(b).filter((q) => String(a[q]) !== String(b[q]));
      console.error(`FAIL ${tag}: игрок ${k + 1}, поля ${diff.map((q) => `${q}: 8080=${a[q]} эталон=${b[q]}`).join('; ')}`); process.exit(1); }
  }
  const seedGot = (r.mem[PARAM + 4] | (r.mem[PARAM + 5] << 8) | (r.mem[PARAM + 6] << 16) | (r.mem[PARAM + 7] << 24)) >>> 0;
  if (seedGot !== rng.seed) { console.error(`FAIL ${tag}: RandSeed 8080=0x${seedGot.toString(16)} эталон=0x${rng.seed.toString(16)}`); process.exit(1); }
  const d = firstPixelDiff(planesToScreen(r.mem), v);
  if (d) { console.error(`FAIL ${tag}: точка (${d.x},${d.y}) на экране 8080=${d.got} эталон=${d.exp}`); process.exit(1); }
  cases++; if (ps.some((p, k) => p.y !== y0[k])) fell++; if (r.vcycles > worst) worst = r.vcycles;
}
console.log(`OK  после выстрела: ${cases} случаев (записи, RandSeed, экран) совпали; с падением танков ${fell}, с осыпанием ${crumbled}; байт ${L.after_end - L.after_shot}; такты до ${worst} vcycles`);
