// plan_stupid, plan_birdy, record_shot (8080) против planStupid / planBirdy / recordShot эталона. node v06c/test/aiplan.mjs [N]
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import * as TW from '../../web/tankwars.js';
import { createMachine, loadRom, poke, runUntil, parseSym } from '../tools/run.mjs';
import { packPlayer, viewKey, viewPlayer, PL_SIZE, MAX_PLAYERS } from '../tools/player.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const json = (p) => JSON.parse(fs.readFileSync(path.join(ROOT, p), 'utf8'));
TW.init({ barrel: json('web/data/barrel.json'), trig: json('web/data/trig.json') });
TW.setProfile(TW.PROFILE_V06C);
const L = parseSym(path.join(ROOT, 'v06c/build/tw.sym'));
const rom = new Uint8Array(fs.readFileSync(path.join(ROOT, 'v06c/build/tw.rom')));
const machine = createMachine();
const PARAM = 0x80, LIST = 0x8800, RESULT = 0x9600, MODE_AIPLAN = 33, PL_AI_S1 = 98, PL_AI_S2 = 102, PL_POWER = 4;
const N = +process.argv[2] || 300;
for (const n of ['plan_stupid', 'plan_birdy', 'record_shot', 'aiplan_end', 'ap_rebound']) if (L[n] === undefined) { console.error('FAIL нет метки ' + n); process.exit(1); }
let s = 1010; const rnd = (n) => { s = (Math.imul(s, 1103515245) + 12345) >>> 0; return Math.floor(s / 4294967296 * n); };
const u32 = (v) => [v & 255, (v >>> 8) & 255, (v >>> 16) & 255, (v >>> 24) & 255];
function mk(n) {
  return Array.from({ length: n }, (_, i) => {
    const p = TW.newPlayer(i + 1, 10); p.ctrl = 3;
    p.men = [100, 100, 37, 5, 1, 0, -3][rnd(7)]; p.angle = rnd(91); p.facing = rnd(2) ? 1 : -1; p.power = rnd(1001); p.weapon = rnd(13);
    for (let k = 0; k < 18; k++) p.ammo[k] = rnd(2) ? 0 : [1, 3, 99, -2][rnd(4)]; p.ammo[0] = 100; p.ammo[11] = 100;
    p.hist = { n: rnd(250), planned: 0, power: rnd(1001), angle: rnd(91), facing: rnd(2) ? 1 : -1, weapon: rnd(13), target: 1 + rnd(n) };
    return p;
  });
}
function run(kind, ps, place, seed, x, extra) {
  const list = new Uint8Array(MAX_PLAYERS * PL_SIZE); ps.forEach((p, i) => list.set(packPlayer(p), i * PL_SIZE));
  if (extra) extra(list);
  loadRom(machine, rom);
  const hdr = new Uint8Array(16); hdr[0] = MODE_AIPLAN; hdr[1] = kind; hdr.set(u32(seed), 4); hdr[8] = ps.length; hdr[10] = x; hdr[14] = place;
  poke(machine, PARAM, hdr); poke(machine, LIST, list);
  return (res) => { if (res) poke(machine, RESULT, res); const r = runUntil(machine, { haltPc: null, maxInsns: 20_000_000 });
    return { seed: (r.mem[PARAM + 4] | (r.mem[PARAM + 5] << 8) | (r.mem[PARAM + 6] << 16) | (r.mem[PARAM + 7] << 24)) >>> 0,
      recs: ps.map((_, i) => r.mem.slice(LIST + i * PL_SIZE, LIST + (i + 1) * PL_SIZE)), list }; };
}
function same(tag, got, ps) {
  for (let i = 0; i < ps.length; i++) { const w = packPlayer(ps[i]);
    if (viewKey(got.recs[i]) !== viewKey(w)) { const a = viewPlayer(got.recs[i]), b = viewPlayer(w), diff = Object.keys(b).filter((k) => String(a[k]) !== String(b[k]));
      console.error(`FAIL ${tag}: игрок ${i + 1}, поля ${diff.map((k) => `${k}: 8080=${a[k]} эталон=${b[k]}`).join('; ')}`); process.exit(1); } }
}
let nS = 0, nB = 0, nR = 0;
for (let t = 0; t < N; t++) {
  const n = 2 + rnd(3);
  { // plan_stupid
    const ps = mk(n), place = 1 + rnd(n), rebound = rnd(2), seed = (rnd(65536) * 65536 + rnd(65536)) >>> 0, p = ps[place - 1];
    const tag = `plan_stupid #${t}: игроков=${n} место=${place} стены=${rebound} men=${p.men} запасы1..4=${p.ammo.slice(1, 5).join(',')} seed=0x${seed.toString(16)}`;
    const got = run(1, ps, place, seed, rebound)();
    const rng = new TW.TPRandom(seed); TW.plan(null, null, ps, p, p.hist, rng, !!rebound, 'Mr. Stupid');
    same(tag, got, ps);
    if (got.seed !== rng.seed) { console.error(`FAIL ${tag}: RandSeed 8080=0x${got.seed.toString(16)} эталон=0x${rng.seed.toString(16)}`); process.exit(1); }
    nS++;
  }
  { // plan_birdy
    const ps = mk(n), place = 1 + rnd(n), p = ps[place - 1];
    const tag = `plan_birdy #${t}: игроков=${n} место=${place} men=${p.men}`;
    const got = run(2, ps, place, 1, 0)();
    TW.plan(null, null, ps, p, p.hist, new TW.TPRandom(1), false, 'Birdy Bonker');
    same(tag, got, ps);
    if (got.seed !== 1) { console.error(`FAIL ${tag}: RandSeed изменён`); process.exit(1); }
    nB++;
  }
  { // record_shot: S2 := S1; S1 := (PL_POWER, целая часть fl_x с усечением к нулю)
    const ps = mk(n), place = 1 + rnd(n), o = (place - 1) * PL_SIZE;
    const old = [rnd(256), rnd(256), rnd(256), rnd(256), rnd(256), rnd(256), rnd(256), rnd(256)];
    const xi = [5, 252, 0, -1, -7, 300, 127, 128][rnd(8)], fr = [0, 0, 1, 0x8000, 0xffff][rnd(5)];
    const x = xi + fr / 65536, q = Math.round(x * 65536) | 0;
    const run1 = run(3, ps, place, 1, 0, (list) => list.set(old, o + PL_AI_S1));
    const got = run1(u32(q >>> 0)), rec = got.recs[place - 1];
    const tx = Math.trunc(x) & 0xffff, pw = ps[place - 1].power;
    const want = [pw & 255, pw >> 8, tx & 255, tx >> 8, ...old.slice(0, 4)], have = [...rec.subarray(PL_AI_S1, PL_AI_S1 + 8)];
    const tag = `record_shot #${t}: место=${place} power=${pw} fl_x=${x} (0x${(q >>> 0).toString(16)}) было S1=${old.slice(0, 4)} S2=${old.slice(4)}`;
    if (have.join() !== want.join()) { console.error(`FAIL ${tag}: S1,S2 8080=${have} надо=${want}`); process.exit(1); }
    same(tag + ' (остальные поля)', got, ps);
    for (let i = 0; i < n; i++) if (i !== place - 1) for (let k = PL_AI_S1; k < PL_SIZE; k++) if (got.recs[i][k] !== got.list[i * PL_SIZE + k]) { console.error(`FAIL ${tag}: испорчена запись игрока ${i + 1}`); process.exit(1); }
    nR++;
  }
}
console.log(`OK  планировщики: plan_stupid ${nS}, plan_birdy ${nB}, record_shot ${nR} случаев — записи и RandSeed совпали; байт ${L.aiplan_end - L.plan_stupid}`);
