// Экран магазина по записям игроков (8080) против drawShop эталона. node v06c/test/shopui.mjs [N]
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
const PARAM = 0x80, LIST = 0x8000, RESULT = 0x9400, MODE_SHOPUI = 34;
const N = +process.argv[2] || 150;
for (const n of ['show_shop', 'shopui_end', 'su_sel', 'su_menu']) if (L[n] === undefined) { console.error('FAIL нет метки ' + n); process.exit(1); }
let s = 1111; const rnd = (n) => { s = (Math.imul(s, 1103515245) + 12345) >>> 0; return Math.floor(s / 4294967296 * n); };
const NAMES = ['Lobber', 'Rifleman', 'Twanger', 'Windless Wit', 'Mr. Stupid', 'Lob & Shoot', 'PLAYER 1', 'PLAYER 4', 'A'];
for (let t = 0; t < N; t++) {
  const n = 2 + rnd(3);
  const ps = Array.from({ length: n }, (_, i) => { const p = TW.newPlayer(i + 1, 10); p.name = NAMES[rnd(NAMES.length)];
    for (let k = 0; k < 18; k++) p.ammo[k] = [0, 0, 1, 30, 100, 999][rnd(6)];
    p.herb = rnd(2) * 5; p.vick = rnd(2) * 5; p.shield = rnd(2) * 1000; p.damp = rnd(2) * 100; p.wins = rnd(12);
    p.score = [0, 2999, 9490, 45700, 123456][rnd(5)]; p.spent = rnd(3) ? 0 : rnd(Math.max(1, p.score)); return p; });
  const place = 1 + rnd(n), p = ps[place - 1];
  const menu = TW.shopMenu(p), qty = menu.map(() => (rnd(3) ? 0 : 1 + rnd(9)));
  let cart = 0; menu.forEach(([cat, i], c) => { cart += TW.SHOP_PRICE[cat][i] * qty[c]; });
  const sel = [-1, 0, rnd(menu.length + 2), menu.length, menu.length + 1][rnd(5)];
  const list = new Uint8Array(MAX_PLAYERS * PL_SIZE); ps.forEach((q, i) => list.set(packPlayer(q), i * PL_SIZE));
  const res = new Uint8Array(4 + 66); res[0] = cart & 255; res[1] = (cart >> 8) & 255; res[2] = (cart >> 16) & 255;
  menu.forEach(([cat, i], c) => { res[4 + c] = cat; res[26 + c] = i; res[48 + c] = qty[c]; });
  loadRom(machine, rom);
  const junk = new Uint8Array(65536); for (let k = 0; k < 65536; k++) junk[k] = [0, 1, 1, 2, 4][(k * 7 + (k >> 8)) % 5];
  const mem0 = new Uint8Array(0x10000); screenToPlanes(junk, mem0); poke(machine, 0xA000, mem0.subarray(0xA000));
  const hdr = new Uint8Array(16); hdr[0] = MODE_SHOPUI; hdr[1] = menu.length; hdr[8] = n; hdr[10] = sel < 0 ? 255 : sel; hdr[14] = place;
  poke(machine, PARAM, hdr); poke(machine, LIST, list); poke(machine, RESULT, res);
  const got = planesToScreen(runUntil(machine, { haltPc: null, maxInsns: 80_000_000 }).mem);
  const want = new Uint8Array(junk); TW.drawShop(want, p, menu, qty, cart, sel);
  const all = []; for (let k = 0; k < 65536 && all.length < 8; k++) if (got[k] !== want[k]) all.push(`(${k & 255},${k >> 8}) 8080=${got[k]} эталон=${want[k]}`);
  if (all.length) { console.error(`FAIL магазин #${t}: место=${place} имя=${p.name} деньги=${p.score - p.spent} позиций=${menu.length} меню=${menu.map((m, c) => m.join(':') + 'x' + qty[c]).join(' ')} корзина=${cart} выбор=${sel}: экран: ${all.join(' ')}`); process.exit(1); }
}
console.log(`OK  экран магазина по записям: ${N} случаев — экран совпал; байт ${L.shopui_end - L.show_shop}`);
