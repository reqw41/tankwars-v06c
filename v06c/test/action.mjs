// Действия хода (8080) против applyCode / autoSwitchWeapon / needsWeaponSwitch эталона. node v06c/test/action.mjs [N]
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
const L = parseSym(path.join(ROOT, 'v06c/build/tw.sym'));
const rom = new Uint8Array(fs.readFileSync(path.join(ROOT, 'v06c/build/tw.rom')));
const machine = createMachine();
const PARAM = 0x80, LIST = 0x8400, RESULT = 0x9600, MODE_ACTION = 27;
const N = +process.argv[2] || 250;
const master = new TW.TPRandom(606);
for (const n of ['apply_code', 'auto_switch', 'needs_switch', 'action_end', 'ac_place']) if (L[n] === undefined) { console.error('FAIL нет метки ' + n); process.exit(1); }
let cases = 0, steps = 0; const seen = new Set();
for (let i = 0; i < N; i++) {
  const n = 2 + master.word(3);
  const rng0 = new TW.TPRandom(master._next());
  const ps = Array.from({ length: n }, (_, k) => { const p = TW.newPlayer(k + 1, 10); p.ctrl = 1; return p; });
  const r0 = TW.roundStart(rng0, ps, 1, 0, 2);
  const v = r0.v, bg = r0.bg;
  for (const p of ps) TW.drawTankBarrel(v, p);
  const place = 1 + master.word(n), p = ps[place - 1];
  p.men = [100, 100, 37, 1, 100][master.word(5)]; p.power = master.word(4) === 0 ? [0, 1, 10 * p.men, 10 * p.men - 1][master.word(4)] : master.word(1001);
  p.angle = master.word(4) === 0 ? [0, 1, 89, 90][master.word(4)] : master.word(91); p.facing = master.word(2) ? 1 : -1;
  for (let k = 0; k < 18; k++) p.ammo[k] = master.word(3) === 0 ? [1, 5, 99, 100, 101, 300][master.word(6)] : 0;
  if (master.word(3)) p.ammo[0] = 100;
  p.weapon = master.word(18); p.herb = master.word(2) * 5; p.vick = master.word(2) * 5; p.guided = master.word(4);
  // перерисовать ствол под новый угол, чтобы экран соответствовал записи
  TW.eraseTankBarrel(v, bg, { ...p, angle: [75, 90][+(place !== 1 && place !== n)], facing: place === n ? -1 : 1 }); TW.drawTankBarrel(v, p);
  const kinds = [[1, 2], [1, 1, 1, 2], [3, 4], [4, 4, 4], [3, 3, 3], [7], [8], [6], [9, 10], [20], [21], [1, 2, 3, 4, 6, 7, 8, 9, 10, 20, 21]];
  const pool = kinds[master.word(kinds.length)], cnt = 1 + master.word(40), codes = Array.from({ length: cnt }, () => pool[master.word(pool.length)]);
  const list = new Uint8Array(MAX_PLAYERS * PL_SIZE); ps.forEach((q, k) => list.set(packPlayer(q), k * PL_SIZE));
  loadRom(machine, rom);
  const mem0 = new Uint8Array(0x10000); screenToPlanes(v, mem0); poke(machine, 0xA000, mem0.subarray(0xA000));
  const hdr = new Uint8Array(16); hdr[0] = MODE_ACTION; hdr[2] = cnt & 255; hdr[3] = cnt >> 8; hdr[8] = n; hdr[14] = place;
  poke(machine, PARAM, hdr); poke(machine, LIST, list); poke(machine, RESULT, codes);
  const wantNeed = [];
  for (const c of codes) { seen.add(c); if (c === 20) TW.autoSwitchWeapon(p); else if (c === 21) wantNeed.push(TW.needsWeaponSwitch(p) ? 1 : 0); else TW.applyCode(v, bg, p, c); }
  const r = runUntil(machine, { haltPc: null, maxInsns: 200_000_000 });
  const tag = `#${i} игрок=${place} из ${n}, коды=[${codes.slice(0, 24).join(',')}${cnt > 24 ? ',…' : ''}]`;
  const gotNeed = codes.map((c, k) => (c === 21 ? r.mem[RESULT + k] : null)).filter((x) => x !== null);
  if (gotNeed.join() !== wantNeed.join()) { console.error(`FAIL ${tag}: needs_switch 8080=${gotNeed} эталон=${wantNeed}`); process.exit(1); }
  for (let k = 0; k < n; k++) {
    const g = r.mem.slice(LIST + k * PL_SIZE, LIST + (k + 1) * PL_SIZE), w = packPlayer(ps[k]);
    if (viewKey(g) !== viewKey(w)) { const a = viewPlayer(g), b = viewPlayer(w), diff = Object.keys(b).filter((q) => String(a[q]) !== String(b[q]));
      console.error(`FAIL ${tag}: игрок ${k + 1}, поля ${diff.map((q) => `${q}: 8080=${a[q]} эталон=${b[q]}`).join('; ')}`); process.exit(1); }
  }
  const d = firstPixelDiff(planesToScreen(r.mem), v);
  if (d) { console.error(`FAIL ${tag}: точка (${d.x},${d.y}) на экране 8080=${d.got} эталон=${d.exp}`); process.exit(1); }
  cases++; steps += cnt;
}
console.log(`OK  действия: ${cases} случаев, ${steps} кодов (записи, экран, ответы needs_switch) совпали; встретились коды ${[...seen].sort((a, b) => a - b).join(',')}; байт ${L.action_end - L.apply_code}`);
