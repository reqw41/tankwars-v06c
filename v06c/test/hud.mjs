// Панель хода и результаты по записям игроков (8080) против drawPanel / drawResults эталона. node v06c/test/hud.mjs [N]
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import * as TW from '../../web/tankwars.js';
import { createMachine, loadRom, poke, runUntil, parseSym } from '../tools/run.mjs';
import { planesToScreen, screenToPlanes } from '../tools/screen.mjs';
import { packPlayer, PL_SIZE, MAX_PLAYERS } from '../tools/player.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const json = (p) => JSON.parse(fs.readFileSync(path.join(ROOT, p), 'utf8'));
TW.init({ barrel: json('web/data/barrel.json'), trig: json('web/data/trig.json') });
TW.setProfile(TW.PROFILE_V06C);
const L = parseSym(path.join(ROOT, 'v06c/build/tw.sym'));
const rom = new Uint8Array(fs.readFileSync(path.join(ROOT, 'v06c/build/tw.rom')));
const machine = createMachine();
const PARAM = 0x80, LIST = 0x8800, MODE_HUD = 32;
const N = +process.argv[2] || 120;
for (const n of ['show_panel', 'show_results', 'hud_end', 'hd_round', 'hd_rounds', 'hd_pack']) if (L[n] === undefined) { console.error('FAIL нет метки ' + n); process.exit(1); }
let s = 1234; const rnd = (n) => { s = (Math.imul(s, 1103515245) + 12345) >>> 0; return Math.floor(s / 4294967296 * n); };
const NAMES = ['Lobber', 'Rifleman', 'Twanger', 'Windless Wit', 'Mr. Stupid', 'Lob & Shoot', 'Player 1', 'Player 4', 'Birdy Bonker', 'A'];
function mk(n) {
  return Array.from({ length: n }, (_, i) => { const p = TW.newPlayer(i + 1, 10); p.name = NAMES[rnd(NAMES.length)];
    p.angle = rnd(91); p.facing = rnd(2) ? 1 : -1; p.power = [0, 5, 200, 999, 1000][rnd(5)]; p.men = [100, 37, 5, 0, -12][rnd(5)]; p.weapon = rnd(18);
    for (let k = 0; k < 18; k++) p.ammo[k] = [0, 1, 30, 100, 999, 1000][rnd(6)];
    p.herb = rnd(2) * 5; p.vick = rnd(2) * 5; p.guided = rnd(4); p.wins = rnd(12); p.score = [0, 50, 9490, 45700, 123456][rnd(5)]; p.spent = rnd(3) ? 0 : rnd(Math.max(1, p.score)); return p; });
}
function run(kind, ps, fields) {
  const list = new Uint8Array(MAX_PLAYERS * PL_SIZE); ps.forEach((p, i) => list.set(packPlayer(p), i * PL_SIZE));
  loadRom(machine, rom);
  const junk = new Uint8Array(65536); for (let k = 0; k < 65536; k++) junk[k] = k >= 24 * 256 ? [0, 1, 1, 2, 4][(k * 7 + (k >> 8)) % 5] : (k % 3 ? 2 : 5);
  const mem0 = new Uint8Array(0x10000); screenToPlanes(junk, mem0); poke(machine, 0xA000, mem0.subarray(0xA000));
  const hdr = new Uint8Array(16); hdr[0] = MODE_HUD; hdr[1] = kind; hdr[8] = ps.length; Object.entries(fields).forEach(([k, v]) => { hdr[+k] = v; });
  poke(machine, PARAM, hdr); poke(machine, LIST, list);
  return { got: planesToScreen(runUntil(machine, { haltPc: null, maxInsns: 60_000_000 }).mem), junk };
}
function cmp(tag, got, want) { const all = []; for (let k = 0; k < 65536 && all.length < 8; k++) if (got[k] !== want[k]) all.push(`(${k & 255},${k >> 8}) 8080=${got[k]} эталон=${want[k]}`);
  if (all.length) { console.error(`FAIL ${tag}: экран: ${all.join(' ')}`); process.exit(1); } }
let nP = 0, nR = 0;
for (let t = 0; t < N; t++) {
  const n = 2 + rnd(3);
  { const ps = mk(n), place = 1 + rnd(n), wind = [0, 22, -22, 30000, -30000, rnd(601) - 300][rnd(6)];
    const r = run(1, ps, { 14: place, 4: wind & 255, 5: (wind >> 8) & 255 }); const want = new Uint8Array(r.junk); TW.drawPanel(want, ps[place - 1], wind);
    cmp(`панель #${t}: место=${place} имя=${ps[place - 1].name} ветер=${wind}`, r.got, want); nP++; }
  { const ps = mk(n), round = 1 + rnd(10), rounds = [round, 10, 99][rnd(3)];
    const r = run(2, ps, { 10: round, 11: rounds }); const want = new Uint8Array(r.junk); TW.drawResults(want, ps, round, rounds);
    cmp(`результаты #${t}: игроков=${n} раунд=${round} из ${rounds}`, r.got, want); nR++; }
}
console.log(`OK  панель и результаты по записям: панель ${nP}, результаты ${nR} случаев — экран совпал; байт ${L.hud_end - L.show_panel}`);
