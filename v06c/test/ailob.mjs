// plan_lobber (8080) против planLobber эталона. node v06c/test/ailob.mjs [N]
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import * as TW from '../../web/tankwars.js';
import { createMachine, loadRom, poke, runUntil, parseSym } from '../tools/run.mjs';
import { screenToPlanes } from '../tools/screen.mjs';
import { packPlayer, viewKey, viewPlayer, PL_SIZE, MAX_PLAYERS } from '../tools/player.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const json = (p) => JSON.parse(fs.readFileSync(path.join(ROOT, p), 'utf8'));
TW.init({ barrel: json('web/data/barrel.json'), trig: json('web/data/trig.json') });
TW.setProfile(TW.PROFILE_V06C);
const L = parseSym(path.join(ROOT, 'v06c/build/tw.sym'));
const rom = new Uint8Array(fs.readFileSync(path.join(ROOT, 'v06c/build/tw.rom')));
const machine = createMachine();
const PARAM = 0x80, LIST = 0x8400, MODE_AIPLAN = 33, PL_AI_S1 = 98;
const N = +process.argv[2] || 600;
let s = 4242; const rnd = (n) => { s = (Math.imul(s, 1103515245) + 12345) >>> 0; return Math.floor(s / 4294967296 * n); };
const u32 = (v) => [v & 255, (v >>> 8) & 255, (v >>> 16) & 255, (v >>> 24) & 255];
const w16 = (v) => [v & 255, (v >> 8) & 255];
let nTry = 0, nFit = 0, nReset = 0, cyc = 0, worst = 0;
for (let t = 0; t < N; t++) {
  const n = 2 + rnd(3), xs = [];
  const ps = Array.from({ length: n }, (_, i) => {
    const p = TW.newPlayer(i + 1, 10); p.ctrl = 3; p.name = 'Lobber';
    do { p.x = 10 + rnd(236); } while (xs.includes(p.x)); xs.push(p.x);
    p.men = [100, 100, 37, 5, 1][rnd(5)]; p.alive = rnd(5) > 0; p.power = rnd(1001);
    for (let k = 0; k < 18; k++) p.ammo[k] = rnd(2) ? 0 : [1, 3, 99, -2][rnd(4)]; p.ammo[0] = 100;
    return p;
  });
  const place = 1 + rnd(n), p = ps[place - 1]; p.alive = true;
  if (!ps.some((q) => q.alive && q !== p)) ps[place % n].alive = true;
  const hn = [1, 2, 3, 3, 4, 7, 60][rnd(7)];
  const far = rnd(6) === 0, sx = () => (far ? [-40, 300, 600, -300, 1000][rnd(5)] : 3 + rnd(250)), sp = () => (rnd(8) ? 50 + rnd(900) : [0, 1000, 5000][rnd(3)]);
  const s1 = { power: sp(), x: sx() }, s2 = rnd(10) ? { power: sp(), x: sx() } : { power: rnd(2) ? s1.power : sp(), x: s1.x };
  p.hist = { n: hn, planned: 0, power: rnd(1001), angle: rnd(91), facing: [1, -1, 0][rnd(3)], weapon: rnd(13), target: 1 + rnd(n), shots: { [hn - 1]: s1, [hn - 2]: s2 } };
  const seed = (rnd(65536) * 65536 + rnd(65536)) >>> 0;
  const list = new Uint8Array(MAX_PLAYERS * PL_SIZE); ps.forEach((q, i) => list.set(packPlayer(q), i * PL_SIZE));
  list.set([...w16(s1.power), ...w16(s1.x), ...w16(s2.power), ...w16(s2.x)], (place - 1) * PL_SIZE + PL_AI_S1);
  loadRom(machine, rom);
  const hdr = new Uint8Array(16); hdr[0] = MODE_AIPLAN; hdr[1] = 4; hdr.set(u32(seed), 4); hdr[8] = n; hdr[14] = place;
  poke(machine, PARAM, hdr); poke(machine, LIST, list);
  const r = runUntil(machine, { haltPc: null, maxInsns: 20_000_000 });
  const tag = `plan_lobber #${t}: игроков=${n} место=${place} n=${hn} напр=${p.hist.facing} x=${ps.map((q) => q.x + (q.alive ? '' : '†')).join(',')} S1=${s1.power}/${s1.x} S2=${s2.power}/${s2.x} запасы0..4,11=${p.ammo.slice(0, 5).join(',')},${p.ammo[11]} seed=0x${seed.toString(16)}`;
  const rng = new TW.TPRandom(seed);
  TW.plan(null, null, ps, p, p.hist, rng, false, 'Lobber');
  if (p.hist.n !== hn) nReset++; if (p.hist.n >= 3) nFit++; else nTry++;
  for (let i = 0; i < n; i++) { const g = r.mem.slice(LIST + i * PL_SIZE, LIST + (i + 1) * PL_SIZE), w = packPlayer(ps[i]);
    if (viewKey(g) !== viewKey(w)) { const a = viewPlayer(g), b = viewPlayer(w), diff = Object.keys(b).filter((k) => String(a[k]) !== String(b[k]));
      console.error(`FAIL ${tag}: игрок ${i + 1}, поля ${diff.map((k) => `${k}: 8080=${a[k]} эталон=${b[k]}`).join('; ')}`); process.exit(1); } }
  const sg = (r.mem[PARAM + 4] | (r.mem[PARAM + 5] << 8) | (r.mem[PARAM + 6] << 16) | (r.mem[PARAM + 7] << 24)) >>> 0;
  if (sg !== rng.seed) { console.error(`FAIL ${tag}: RandSeed 8080=0x${sg.toString(16)} эталон=0x${rng.seed.toString(16)}`); process.exit(1); }
  cyc += r.vcycles; worst = Math.max(worst, r.vcycles);
}
// --- Windless Wit ---
let wc = 0, ww = 0;
for (let t = 0; t < N; t++) {
  const n = 2 + rnd(3), xs = [];
  const ps = Array.from({ length: n }, (_, i) => {
    const p = TW.newPlayer(i + 1, 10); p.ctrl = 3; p.name = 'Windless Wit';
    do { p.x = 3 + rnd(250); } while (xs.some((x) => Math.abs(x - p.x) < (rnd(8) ? 12 : 1))); xs.push(p.x); p.y = 27 + rnd(226);
    p.men = [100, 100, 37, 5, 1, 0][rnd(6)]; p.alive = rnd(5) > 0; p.power = rnd(1001);
    for (let k = 0; k < 18; k++) p.ammo[k] = rnd(2) ? 0 : [1, 3, 99, -2][rnd(4)]; p.ammo[0] = 100;
    return p;
  });
  const place = 1 + rnd(n), p = ps[place - 1]; p.alive = true;
  if (!ps.some((q) => q.alive && q !== p)) ps[place % n].alive = true;
  p.hist = { n: 1 + rnd(20), planned: 0, power: rnd(1001), angle: rnd(91), facing: [1, -1, 0][rnd(3)], weapon: rnd(13), target: 1 + rnd(n), shots: {} };
  const seed = (rnd(65536) * 65536 + rnd(65536)) >>> 0;
  const list = new Uint8Array(MAX_PLAYERS * PL_SIZE); ps.forEach((q, i) => list.set(packPlayer(q), i * PL_SIZE));
  const tag = `plan_wit #${t}: игроков=${n} место=${place} танки=${ps.map((q) => q.x + ':' + q.y + (q.alive ? '' : '†')).join(' ')} men=${p.men} seed=0x${seed.toString(16)}`;
  const rng = new TW.TPRandom(seed);
  try { TW.plan(null, null, ps, p, p.hist, rng, false, 'Windless Wit'); } catch (e) { if (/переполнение/.test(e.message)) { t--; continue; } throw e; }
  loadRom(machine, rom);
  const hdr = new Uint8Array(16); hdr[0] = MODE_AIPLAN; hdr[1] = 5; hdr.set(u32(seed), 4); hdr[8] = n; hdr[14] = place;
  poke(machine, PARAM, hdr); poke(machine, LIST, list);
  const r = runUntil(machine, { haltPc: null, maxInsns: 60_000_000 });
  for (let i = 0; i < n; i++) { const g = r.mem.slice(LIST + i * PL_SIZE, LIST + (i + 1) * PL_SIZE), w = packPlayer(ps[i]);
    if (viewKey(g) !== viewKey(w)) { const a = viewPlayer(g), b = viewPlayer(w), diff = Object.keys(b).filter((k) => String(a[k]) !== String(b[k]));
      console.error(`FAIL ${tag}: игрок ${i + 1}, поля ${diff.map((k) => `${k}: 8080=${a[k]} эталон=${b[k]}`).join('; ')}`); process.exit(1); } }
  const sg = (r.mem[PARAM + 4] | (r.mem[PARAM + 5] << 8) | (r.mem[PARAM + 6] << 16) | (r.mem[PARAM + 7] << 24)) >>> 0;
  if (sg !== rng.seed) { console.error(`FAIL ${tag}: RandSeed 8080=0x${sg.toString(16)} эталон=0x${rng.seed.toString(16)}`); process.exit(1); }
  wc += r.vcycles; ww = Math.max(ww, r.vcycles);
}
// --- планировщики с трассой по экрану: Rifleman (6), Twanger (7) ---
function traced(name, kind, label, count) {
  if (L[label] === undefined) return;
  let c = 0, w = 0, low = 0, big = 0;
  const master = new TW.TPRandom(kind * 1000 + 7);
  for (let t = 0; t < count; t++) {
    const n = 2 + rnd(3), rebound = kind === 7 ? 1 : rnd(2);     // Twanger без отражающих стен играет как Rifleman
    const ps = Array.from({ length: n }, (_, i) => { const p = TW.newPlayer(i + 1, 10); p.ctrl = 3; p.name = name; return p; });
    const r0 = TW.roundStart(new TW.TPRandom(master._next()), ps, 1, 0, 2), v = r0.v;
    for (const p of ps) { TW.drawTankBarrel(v, p); p.men = [100, 100, 37, 5][rnd(4)]; p.alive = rnd(6) > 0; p.power = rnd(1001);
      for (let k = 0; k < 18; k++) p.ammo[k] = rnd(2) ? 0 : [1, 3, 99, 150][rnd(4)]; p.ammo[0] = 100; if (rnd(3)) p.ammo[5] = 0; }
    const place = 1 + rnd(n), p = ps[place - 1]; p.alive = true;
    if (!ps.some((q) => q.alive && q !== p)) ps[place % n].alive = true;
    p.hist = { n: 1 + rnd(20), planned: 0, power: rnd(1001), angle: rnd(91), facing: [1, -1, 0][rnd(3)], weapon: rnd(13), target: 1 + rnd(n), shots: {} };
    const seed = (rnd(65536) * 65536 + rnd(65536)) >>> 0;
    const list = new Uint8Array(MAX_PLAYERS * PL_SIZE); ps.forEach((q, i) => list.set(packPlayer(q), i * PL_SIZE));
    const tag = `${label} #${t}: игроков=${n} место=${place} стены=${rebound} танки=${ps.map((q) => q.x + ':' + q.y + (q.alive ? '' : '†')).join(' ')} запасы1..5=${p.ammo.slice(1, 6).join(',')} seed=0x${seed.toString(16)}`;
    loadRom(machine, rom);
    const mem0 = new Uint8Array(0x10000); screenToPlanes(v, mem0); poke(machine, 0xA000, mem0.subarray(0xA000));
    const hdr = new Uint8Array(16); hdr[0] = MODE_AIPLAN; hdr[1] = kind; hdr.set(u32(seed), 4); hdr[8] = n; hdr[10] = rebound; hdr[14] = place;
    poke(machine, PARAM, hdr); poke(machine, LIST, list);
    const rng = new TW.TPRandom(seed), v0 = new Uint8Array(v);
    TW.plan(v, r0.bg, ps, p, p.hist, rng, !!rebound, name);
    for (let k = 0; k < 65536; k++) if (v[k] !== v0[k]) { console.error(`FAIL ${tag}: эталон изменил экран`); process.exit(1); }
    const r = runUntil(machine, { haltPc: null, maxInsns: 200_000_000 });
    for (let i = 0; i < n; i++) { const g = r.mem.slice(LIST + i * PL_SIZE, LIST + (i + 1) * PL_SIZE), wv = packPlayer(ps[i]);
      if (viewKey(g) !== viewKey(wv)) { const a = viewPlayer(g), b = viewPlayer(wv), diff = Object.keys(b).filter((k) => String(a[k]) !== String(b[k]));
        console.error(`FAIL ${tag}: игрок ${i + 1}, поля ${diff.map((k) => `${k}: 8080=${a[k]} эталон=${b[k]}`).join('; ')}`); process.exit(1); } }
    const sg = (r.mem[PARAM + 4] | (r.mem[PARAM + 5] << 8) | (r.mem[PARAM + 6] << 16) | (r.mem[PARAM + 7] << 24)) >>> 0;
    if (sg !== rng.seed) { console.error(`FAIL ${tag}: RandSeed 8080=0x${sg.toString(16)} эталон=0x${rng.seed.toString(16)}`); process.exit(1); }
    c += r.vcycles; w = Math.max(w, r.vcycles); if (p.hist.weapon > 1 && p.hist.weapon < 6) big++; if (p.hist.power < 1000 && name === 'Rifleman') low++;
  }
  console.log(`OK  ${name}: ${count} планов — записи и RandSeed совпали (крупное оружие или лазер ${big}${name === 'Rifleman' ? ', навесом ' + low : ''}); в среднем ${(c / count / 3e6).toFixed(2)} с, худший ${(w / 3e6).toFixed(2)} с`);
}
traced('Rifleman', 6, 'plan_rifle', Math.min(N, 300));
traced('Twanger', 7, 'plan_twang', Math.min(N, 300));
console.log(`OK  Windless Wit: ${N} планов — записи и RandSeed совпали; байт ${L.aiwit_end - L.plan_wit}; в среднем ${(wc / N / 3000).toFixed(0)} мс, худший ${(ww / 3000).toFixed(0)} мс`);
console.log(`OK  Lobber: ${N} планов (пристрелка ${nTry}, поправка ${nFit}, сброс счётчика ${nReset}) — записи и RandSeed совпали; байт ${L.ailob_end - L.plan_lobber}; в среднем ${(cyc / N / 3000).toFixed(0)} мс, худший ${(worst / 3000).toFixed(0)} мс`);
