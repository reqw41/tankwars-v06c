// Обычный взрыв на 8080 против explode() эталона. node v06c/test/explode.mjs [N]
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
const PARAM = 0x80, LIST = 0x7800, RESULT = 0x8C00, MODE_EXPLODE = 25;
const N = +process.argv[2] || 300;
const master = new TW.TPRandom(777);
const le = (v) => [v & 255, (v >>> 8) & 255, (v >>> 16) & 255, (v >>> 24) & 255];
let cases = 0, hurt = 0, direct = 0, cyc = 0;
for (let i = 0; i < N; i++) {
  const n = 2 + master.word(3);
  const rng = new TW.TPRandom(master._next());
  const ps = Array.from({ length: n }, (_, k) => { const p = TW.newPlayer(k + 1, 10); p.ctrl = 3; return p; });
  const r0 = TW.roundStart(rng, ps, 1, 0, 2);
  for (const p of ps) { p.shield = master.word(3) ? 0 : master.word(400); p.men = 1 + master.word(100); p.score = master.word(50000); if (master.word(8) === 0) p.alive = false; }
  const weapon = [1, 2, 3, 4, 11][master.word(5)], shooter = master.word(6) === 0 ? 0 : 1 + master.word(n);
  // точка: рядом с танком, на танке или случайная в поле; дробная часть случайная
  const t = ps[master.word(n)], k = master.word(3);
  const xi = k === 0 ? t.x : k === 1 ? Math.max(P.X0 + 1, Math.min(P.X1 - 1, t.x + master.word(41) - 20)) : P.X0 + 1 + master.word(P.X1 - P.X0 - 1);
  const yi = k === 0 ? t.y : k === 1 ? Math.max(P.Y0 + 3, Math.min(P.Y1 - 1, t.y + master.word(41) - 20)) : P.Y0 + 3 + master.word(P.Y1 - P.Y0 - 3);
  const x = xi * 65536 + master.word(65536), y = yi * 65536 + master.word(65536);
  const c = r0.v[yi * 256 + xi], hit = master.word(4) === 0 ? 4 + master.word(n) : c >= 4 ? c : 1;
  const list = new Uint8Array(MAX_PLAYERS * PL_SIZE); ps.forEach((p, k2) => list.set(packPlayer(p), k2 * PL_SIZE));
  loadRom(machine, rom);
  const mem0 = new Uint8Array(0x10000); screenToPlanes(r0.v, mem0); poke(machine, 0xA000, mem0.subarray(0xA000));
  const hdr = new Uint8Array(16); hdr[0] = MODE_EXPLODE; hdr[8] = n;
  poke(machine, PARAM, hdr); poke(machine, LIST, list); poke(machine, RESULT, [...le(x), ...le(y), hit, shooter, weapon]);
  const before = ps.map((p) => p.men);
  TW.explode(r0.v, r0.bg, ps, x, y, hit, shooter, weapon, rng, false);
  const r = runUntil(machine, { haltPc: null, maxInsns: 200_000_000 });
  const tag = `#${i} оружие=${weapon} точка=(${(x / 65536).toFixed(3)},${(y / 65536).toFixed(3)}) hit=${hit} стрелок=${shooter} игроков=${n}`;
  for (let k2 = 0; k2 < n; k2++) {
    const g = r.mem.slice(LIST + k2 * PL_SIZE, LIST + (k2 + 1) * PL_SIZE), w = packPlayer(ps[k2]);
    if (viewKey(g) !== viewKey(w)) { const a = viewPlayer(g), b = viewPlayer(w), diff = Object.keys(b).filter((q) => String(a[q]) !== String(b[q]));
      console.error(`FAIL ${tag}: игрок ${k2 + 1} (x=${ps[k2].x}, y=${ps[k2].y}), поля ${diff.map((q) => `${q}: 8080=${a[q]} эталон=${b[q]}`).join('; ')}`); process.exit(1); }
  }
  const d = firstPixelDiff(planesToScreen(r.mem), r0.v);
  if (d) { console.error(`FAIL ${tag}: точка (${d.x},${d.y}) на экране 8080=${d.got} эталон=${d.exp}`); process.exit(1); }
  cases++; cyc += r.vcycles; if (ps.some((p, k2) => p.men !== before[k2])) hurt++; if (hit >= 4) direct++;
}
console.log(`OK  взрыв: ${cases} случаев совпали (записи игроков, экран); с уроном ${hurt}, прямых попаданий ${direct}; байт ${L.explode_end - L.explode}; в среднем ${Math.round(cyc / cases)} vcycles`);
