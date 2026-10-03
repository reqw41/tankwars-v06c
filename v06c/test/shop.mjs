// Магазин компьютерного игрока (8080) против aiShop эталона. node v06c/test/shop.mjs [N]
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
const PARAM = 0x80, LIST = 0x7800, MODE_SHOP = 29;
const N = +process.argv[2] || 300;
for (const n of ['ai_shop', 'shop_end', 'sh_wprice', 'sh_wpack']) if (L[n] === undefined) { console.error('FAIL нет метки ' + n); process.exit(1); }
let s = 31337; const rnd = (n) => { s = (Math.imul(s, 1103515245) + 12345) >>> 0; return Math.floor(s / 4294967296 * n); };
let cases = 0, bought = 0, worst = 0; const strat = [0, 0, 0, 0, 0];
for (let t = 0; t < N; t++) {
  const n = 2 + rnd(3);
  const ps = Array.from({ length: n }, (_, i) => {
    const p = TW.newPlayer(i + 1, 10); p.ctrl = 3; p.strategy = t < 10 ? t % 5 : rnd(5);
    p.spent = rnd(3) ? 0 : rnd(30000);
    const money = [0, 2999, 3000, 3001, 6999, 7000, 10000, 19999, 20000, 45000, 90000, rnd(60000), rnd(60000), rnd(15000)][rnd(14)];
    p.score = p.spent + money;
    for (let k = 0; k < 18; k++) p.ammo[k] = rnd(4) ? 0 : [1, 5, 19, 20, 21, 100, 300][rnd(7)];
    p.ammo[0] = 100; p.ammo[1] = [0, 0, 5, 19, 20, 30, 130][rnd(7)];
    p.herb = rnd(4) ? 0 : 5; p.vick = rnd(4) ? 0 : 5; p.shield = rnd(4) ? 0 : rnd(2000); p.damp = rnd(4) ? 0 : rnd(300);
    return p;
  });
  const list = new Uint8Array(MAX_PLAYERS * PL_SIZE); ps.forEach((p, i) => list.set(packPlayer(p), i * PL_SIZE));
  const before = ps.map((p) => p.spent);
  for (const p of ps) { TW.aiShop(p, p.strategy); strat[p.strategy]++; }
  loadRom(machine, rom);
  const hdr = new Uint8Array(16); hdr[0] = MODE_SHOP; hdr[8] = n;
  poke(machine, PARAM, hdr); poke(machine, LIST, list);
  const r = runUntil(machine, { haltPc: null, maxInsns: 400_000_000 });
  for (let i = 0; i < n; i++) {
    const g = r.mem.slice(LIST + i * PL_SIZE, LIST + (i + 1) * PL_SIZE), w = packPlayer(ps[i]);
    if (viewKey(g) !== viewKey(w)) { const a = viewPlayer(g), b = viewPlayer(w), diff = Object.keys(b).filter((k) => String(a[k]) !== String(b[k]));
      console.error(`FAIL #${t} игрок ${i + 1} (стратегия ${ps[i].strategy}, было потрачено ${before[i]}, очки ${ps[i].score}): поля ${diff.map((k) => `${k}: 8080=${a[k]} эталон=${b[k]}`).join('; ')}`); process.exit(1); }
    if (ps[i].spent !== before[i]) bought++;
  }
  cases++; worst = Math.max(worst, r.vcycles);
}
console.log(`OK  магазин ИИ: ${cases} случаев совпали; игроков с покупками ${bought}; по стратегиям 0..4: ${strat.join(', ')}; байт ${L.shop_end - L.ai_shop}; такты до ${worst} vcycles`);
