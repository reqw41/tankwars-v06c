// Гибель танка на 8080 против death() эталона. node v06c/test/death.mjs [варианты через запятую] [N на вариант]
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import * as TW from '../../web/tankwars.js';
import { createMachine, loadRom, poke, runUntil, parseSym } from '../tools/run.mjs';
import { planesToScreen, screenToPlanes } from '../tools/screen.mjs';
import { packPlayer, viewKey, viewPlayer, PL_SIZE, MAX_PLAYERS } from '../tools/player.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const json = (p) => JSON.parse(fs.readFileSync(path.join(ROOT, p), 'utf8'));
TW.init({ barrel: json('web/data/barrel.json'), trig: json('web/data/trig.json') });
TW.setProfile(TW.PROFILE_V06C);
const L = parseSym(path.join(ROOT, 'v06c/build/tw.sym'));
const rom = new Uint8Array(fs.readFileSync(path.join(ROOT, 'v06c/build/tw.rom')));
const machine = createMachine();
const PARAM = 0x80, LIST = 0x8800, RESULT = 0x9600, MODE_DEATH = 28;
const variants = (process.argv[2] || '0,1,2,3,4,5,6').split(',').map(Number), N = +process.argv[3] || 30;
const u32 = (v) => [v & 255, (v >>> 8) & 255, (v >>> 16) & 255, (v >>> 24) & 255];
for (const variant of variants) {
  const master = new TW.TPRandom(9000 + variant);
  let cases = 0, cyc = 0, worst = 0, hurt = 0;
  for (let i = 0; i < N; i++) {
    const n = 2 + master.word(3);
    const rng0 = new TW.TPRandom(master._next());
    const ps = Array.from({ length: n }, (_, k) => { const p = TW.newPlayer(k + 1, 10); p.ctrl = 3; return p; });
    const r0 = TW.roundStart(rng0, ps, master.word(3), 0, 2);
    const v = r0.v, bg = r0.bg;
    for (const p of ps) { TW.drawTankBarrel(v, p); p.men = 1 + master.word(100); p.shield = master.word(4) ? 0 : master.word(300); p.score = master.word(30000); }
    const victim = 1 + master.word(n); ps[victim - 1].men = -master.word(40); ps[victim - 1].alive = false;
    const wind = [0, master.word(601) - 300, master.word(8001) - 4000][master.word(3)], xkill = master.word(4) ? 1 : 0, seed = master._next();
    const list = new Uint8Array(MAX_PLAYERS * PL_SIZE); ps.forEach((p, k) => list.set(packPlayer(p), k * PL_SIZE));
    loadRom(machine, rom);
    const mem0 = new Uint8Array(0x10000); screenToPlanes(v, mem0); poke(machine, 0xA000, mem0.subarray(0xA000));
    const hdr = new Uint8Array(16); hdr[0] = MODE_DEATH; hdr.set(u32(seed), 4); hdr[8] = n;
    poke(machine, PARAM, hdr); poke(machine, LIST, list); poke(machine, RESULT, [variant, victim, wind & 255, (wind >> 8) & 255, xkill]);
    const rng = new TW.TPRandom(seed), men0 = ps.map((p) => p.men);
    TW.death(variant, v, bg, ps, victim, rng, false, wind, !!xkill);
    const r = runUntil(machine, { haltPc: null, maxInsns: 2_000_000_000 });
    const tag = `вариант ${variant} #${i} игроков=${n} жертва=${victim} ветер=${wind} xkill=${xkill} seed=0x${seed.toString(16)}`;
    for (let k = 0; k < n; k++) {
      const g = r.mem.slice(LIST + k * PL_SIZE, LIST + (k + 1) * PL_SIZE), w = packPlayer(ps[k]);
      if (viewKey(g) !== viewKey(w)) { const a = viewPlayer(g), b = viewPlayer(w), diff = Object.keys(b).filter((q) => String(a[q]) !== String(b[q]));
        console.error(`FAIL ${tag}: игрок ${k + 1}, поля ${diff.map((q) => `${q}: 8080=${a[q]} эталон=${b[q]}`).join('; ')}`); process.exit(1); }
    }
    const seedGot = (r.mem[PARAM + 4] | (r.mem[PARAM + 5] << 8) | (r.mem[PARAM + 6] << 16) | (r.mem[PARAM + 7] << 24)) >>> 0;
    if (seedGot !== rng.seed) { console.error(`FAIL ${tag}: RandSeed 8080=0x${seedGot.toString(16)} эталон=0x${rng.seed.toString(16)}`); process.exit(1); }
    const g = planesToScreen(r.mem), all = []; for (let k = 0; k < 65536 && all.length < 10; k++) if (g[k] !== v[k]) all.push(`(${k & 255},${k >> 8}) 8080=${g[k]} эталон=${v[k]}`);
    if (all.length) { console.error(`FAIL ${tag}: экран: ${all.join(' ')}`); process.exit(1); }
    cases++; cyc += r.vcycles; worst = Math.max(worst, r.vcycles); if (ps.some((p, k) => k !== victim - 1 && p.men !== men0[k])) hurt++;
  }
  console.log(`OK  гибель ${variant}: ${cases} случаев (записи, RandSeed, экран) совпали; задело соседей в ${hurt}; в среднем ${(cyc / cases / 3e6).toFixed(2)} с, худший ${(worst / 3e6).toFixed(2)} с при 3 МГц`);
}
