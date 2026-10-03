// choose_code, turn_begin, next_alive, round_winner (8080) против эталона. node v06c/test/aistep.mjs [N]
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
const PARAM = 0x80, LIST = 0x7800, RESULT = 0x8C00, MODE_AISTEP = 31;
const N = +process.argv[2] || 400;
for (const n of ['choose_code', 'turn_begin', 'next_alive', 'round_winner', 'aistep_end']) if (L[n] === undefined) { console.error('FAIL нет метки ' + n); process.exit(1); }
let s = 808; const rnd = (n) => { s = (Math.imul(s, 1103515245) + 12345) >>> 0; return Math.floor(s / 4294967296 * n); };
function mk(n) {
  return Array.from({ length: n }, (_, i) => {
    const p = TW.newPlayer(i + 1, 10); p.ctrl = 3;
    p.men = [100, 100, 37, 5, 1, 0, -3][rnd(7)]; p.alive = rnd(4) > 0; p.angle = rnd(91); p.facing = rnd(2) ? 1 : -1; p.power = rnd(1001); p.weapon = rnd(13);
    for (let k = 0; k < 18; k++) p.ammo[k] = rnd(3) ? 0 : [1, 3, 99, 100, 101, 500][rnd(6)]; p.ammo[0] = 100;
    const near = rnd(3) === 0;
    p.hist = { n: rnd(250), planned: 1, power: near ? p.power + rnd(31) - 15 : [rnd(1001), rnd(1400) - 200, p.power][rnd(3)], angle: near ? Math.max(0, Math.min(90, p.angle + rnd(5) - 2)) : rnd(91),
      facing: rnd(4) ? p.facing : -p.facing, weapon: rnd(3) ? p.weapon : rnd(13), target: 1 + rnd(n) };
    return p;
  });
}
function run(kind, ps, c) {
  const list = new Uint8Array(MAX_PLAYERS * PL_SIZE); ps.forEach((p, i) => list.set(packPlayer(p), i * PL_SIZE));
  loadRom(machine, rom);
  const hdr = new Uint8Array(16); hdr[0] = MODE_AISTEP; hdr[1] = kind; hdr[8] = ps.length; hdr[14] = c;
  poke(machine, PARAM, hdr); poke(machine, LIST, list);
  const r = runUntil(machine, { haltPc: null, maxInsns: 20_000_000 });
  return { res: [r.mem[RESULT], r.mem[RESULT + 1]], recs: ps.map((_, i) => r.mem.slice(LIST + i * PL_SIZE, LIST + (i + 1) * PL_SIZE)) };
}
function same(tag, got, ps) {
  for (let i = 0; i < ps.length; i++) { const w = packPlayer(ps[i]);
    if (viewKey(got.recs[i]) !== viewKey(w)) { const a = viewPlayer(got.recs[i]), b = viewPlayer(w), diff = Object.keys(b).filter((k) => String(a[k]) !== String(b[k]));
      console.error(`FAIL ${tag}: игрок ${i + 1}, поля ${diff.map((k) => `${k}: 8080=${a[k]} эталон=${b[k]}`).join('; ')}`); process.exit(1); } }
}
const codes = new Set(); let nC = 0, nT = 0, nA = 0, nW = 0;
for (let t = 0; t < N; t++) {
  const n = 2 + rnd(3);
  { const ps = mk(n), place = 1 + rnd(n), p = ps[place - 1]; p.alive = true;
    if (t % 5 === 0) { const w = [0, 1, 3, 5][rnd(4)]; p.ammo[w] = 300; p.weapon = w; p.men = 100; p.hist = { ...p.hist, power: p.power, angle: p.angle, facing: p.facing, weapon: w }; if (w === 5 && rnd(2)) p.ammo[5] = Math.max(1, p.power - rnd(3)); }   // план уже достигнут — код 5
    const before = { pw: p.power, an: p.angle, fa: p.facing, we: p.weapon, men: p.men, h: JSON.stringify(p.hist), ammo: p.ammo.join('.') };
    const got = run(1, ps, place); const code = TW.chooseCode(p, p.hist);
    const tag = `choose_code #${t} место=${place}: было power=${before.pw} angle=${before.an} facing=${before.fa} weapon=${before.we} men=${before.men} ammo=${before.ammo} план=${before.h}`;
    if (got.res[0] !== code) { console.error(`FAIL ${tag}: код 8080=${got.res[0]} эталон=${code}`); process.exit(1); }
    same(tag, got, ps); codes.add(code); nC++; }
  { const ps = mk(n), place = 1 + rnd(n); ps[place - 1].hist.n = [0, 1, 7, 254][rnd(4)]; const got = run(2, ps, place); TW.turnBegin(ps[place - 1].hist); same(`turn_begin #${t} место=${place}`, got, ps); nT++; }
  { const ps = mk(n); ps[rnd(n)].alive = true; const cur = rnd(n + 1); const got = run(3, ps, cur); const want = TW.nextAlive(ps, cur);
    if (got.res[0] !== want) { console.error(`FAIL next_alive #${t}: текущее=${cur} живые=${ps.map((p) => +p.alive).join('')} 8080=${got.res[0]} эталон=${want}`); process.exit(1); } same(`next_alive #${t}`, got, ps); nA++; }
  { const ps = mk(n); if (t % 3 === 0) ps.forEach((p, i) => { p.alive = i === (t % n); }); if (t % 7 === 0) ps.forEach((p) => { p.alive = false; });
    const got = run(4, ps, 0); const alive = ps.filter((p) => p.alive), over = alive.length <= 1 ? 1 : 0, win = over && alive[0] ? alive[0].idx : 0;
    if (got.res[0] !== over || (over && got.res[1] !== win)) { console.error(`FAIL round_winner #${t}: живые=${ps.map((p) => +p.alive).join('')} 8080: окончен=${got.res[0]} победитель=${got.res[1]}; эталон: окончен=${over} победитель=${win}`); process.exit(1); }
    same(`round_winner #${t}`, got, ps); nW++; }
}
console.log(`OK  шаг ИИ: choose_code ${nC} (коды ${[...codes].sort((a, b) => a - b).join(',')}), turn_begin ${nT}, next_alive ${nA}, round_winner ${nW} случаев совпали; байт ${L.aistep_end - L.choose_code}`);
