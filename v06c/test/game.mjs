// Игровой образ (v06c/build/game.rom) против эталона: люди играют с клавиатуры, нажатия по сценарию.
// После каждого хода сверяются записи игроков, RandSeed и экран. node v06c/test/game.mjs [матчей] [png]
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import * as TW from '../../web/tankwars.js';
import { parseSym } from '../tools/run.mjs';
import { createVector, savePng } from '../tools/vmachine.mjs';
import { planesToScreen } from '../tools/screen.mjs';
import { packPlayer, viewKey, viewPlayer, PL_SIZE } from '../tools/player.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const json = (p) => JSON.parse(fs.readFileSync(path.join(ROOT, p), 'utf8'));
TW.init({ barrel: json('web/data/barrel.json'), trig: json('web/data/trig.json') });
TW.setProfile(TW.PROFILE_V06C);
const BUILD = process.env.BUILD || 'v06c/build';      // BUILD=work/snap — прогон на снимке сборки
const L = parseSym(path.join(ROOT, BUILD, 'game.sym'));
const ROM = new Uint8Array(fs.readFileSync(path.join(ROOT, BUILD, 'game.rom')));     // читаем один раз: пересборка во время прогона не мешает
// GOLD=номера — матчи компьютеров из tests/fixtures/v06c/golden.json (те же игроки, начальные числа, 4 раунда)
const GOLD = process.env.GOLD ? json('tests/fixtures/v06c/golden.json') : null, GOLD_IDS = (process.env.GOLD || '').split(',').map(Number);
const GOLD_NAMES = ['Lobber', 'Rifleman', 'Twanger', 'Windless Wit', 'Mr. Stupid', 'Lob & Shoot'];
const M = GOLD ? GOLD_IDS.length : +process.argv[2] || 6, PNG = process.argv[3];
const KEY = { 1: [0, 0x10], 2: [0, 0x40], 3: [0, 0x80], 4: [0, 0x20], 5: [7, 0x80], 6: [5, 0x02], 7: [6, 0x02], 8: [6, 0x80], 11: [1, 0x04], 12: [1, 0x02] };
const PH = { title: 0, input: 1, busy: 2, results: 3, ready: 4, shop: 5, splash: 6 };
const AI = [null, 'Mr. Stupid', 'Lobber', 'Rifleman', 'Lob & Shoot', 'Windless Wit', 'Twanger', 'Birdy Bonker'];
const KINDS = (process.env.KINDS || '0,2,3,4,5,6').split(',').map(Number);
const master = new TW.TPRandom(27182);
const u32 = (v) => [v & 255, (v >>> 8) & 255, (v >>> 16) & 255, (v >>> 24) & 255];
let shopChecked = 0, goldRounds = 0, aiTurns = 0, turns = 0, rounds = 0, keys = 0, frames = 0, worst = 0, panelChecked = 0;

function fail(msg) { console.error('FAIL ' + msg); process.exit(1); }
for (let mi = 0; mi < M; mi++) {
  const gold = GOLD ? (GOLD.matches || GOLD.cases || GOLD)[GOLD_IDS[mi]] : null;
  const n = gold ? gold.players : 2 + master.word(3), seed = gold ? gold.seed >>> 0 : master._next(), nRounds = gold ? gold.rounds.length : 2;
  const types = Array.from({ length: n }, (_, i) => (gold ? AI.indexOf(GOLD_NAMES[(i + gold.seed) % GOLD_NAMES.length]) : mi === 0 ? 0 : KINDS[master.word(KINDS.length)]));     // первый матч — одни люди
  const m = createVector(ROM);
  const phase = () => m.rd(L.g_phase);
  // нажать клавишу и отпустить, дождаться, пока игра снова ждёт ввода (или показывает результаты)
  function press(code, tag) {
    const [row, bit] = KEY[code], t0 = m.rd(L.kb_taken), f0 = m.frames;
    m.key(row, bit, true);
    for (let f = 0; m.rd(L.kb_taken) === t0; f++) { if (f > 200) fail(`${tag}: нажатие ${code} не принято`); m.frame(); }
    m.key(row, bit, false);
    for (let f = 0; ; f++) { m.frame(); if (m.rd(L.gk_last) === 0 && [PH.input, PH.results, PH.ready, PH.shop, PH.title].includes(phase())) break; if (f > 60000) { const pc = m.cpu.pc & 0xffff, near = Object.entries(L).filter(([, v]) => v <= pc).sort((x, y) => y[1] - x[1])[0]; fail(`${tag}: игра не вернулась к вводу за 20 минут (PC=${pc.toString(16)} у метки ${near && near[0]})`); } }
    keys++; return m.frames - f0;
  }
  function check(tag, ps, rng, v, panel) {
    const mem = m.mem();
    for (let k = 0; k < n; k++) {
      const g = mem.slice(L.players + k * PL_SIZE, L.players + (k + 1) * PL_SIZE), w = packPlayer(ps[k]);
      if (viewKey(g) !== viewKey(w)) { const a = viewPlayer(g), b = viewPlayer(w), diff = Object.keys(b).filter((q) => String(a[q]) !== String(b[q]));
        fail(`${tag}: игрок ${k + 1}, поля ${diff.map((q) => `${q}: 8080=${a[q]} эталон=${b[q]}`).join('; ')}`); }
    }
    const sg = (mem[L.rand_seed] | (mem[L.rand_seed + 1] << 8) | (mem[L.rand_seed + 2] << 16) | (mem[L.rand_seed + 3] << 24)) >>> 0;
    if (sg !== rng.seed) fail(`${tag}: RandSeed 8080=0x${sg.toString(16)} эталон=0x${rng.seed.toString(16)}`);
    if (!v) return;
    const g = planesToScreen(mem), want = new Uint8Array(v); if (panel) panel(want);
    let any = false; for (let k = 0; k < 24 * 256; k++) if (g[k]) { any = true; break; }
    const from = any && panel ? 0 : 24 * 256; if (!from) panelChecked++;
    const all = []; for (let k = from; k < 65536 && all.length < (process.env.ALL ? 400 : 8); k++) if (g[k] !== want[k]) all.push(`(${k & 255},${k >> 8}) 8080=${g[k]} эталон=${want[k]}`);
    if (all.length && process.env.DBG) for (let y = 226; y < 242; y++) { let a = '', b = ''; for (let x = 214; x < 246; x++) { a += g[y * 256 + x]; b += want[y * 256 + x]; } console.log(y, a, b); }
    if (all.length) fail(`${tag}: экран: ${all.join(' ')}`);
  }
  // --- эталон: тот же порядок, что в game.asm ---
  const rng = new TW.TPRandom(seed);
  const ps = Array.from({ length: n }, (_, i) => { const p = TW.newPlayer(i + 1, nRounds); if (types[i]) { p.ctrl = 3; p.name = AI[types[i]]; } else p.name = 'PLAYER ' + (i + 1);
    p.strategy = TW.pickStrategy(p.name, rng); return p; });
  const allAi = types.every(Boolean);
  // загрузчик: заставка, любая клавиша, распаковка игры (её признак — вектор прерывания указывает на isr игры)
  m.frame(100);
  if (process.env.SPLASH && mi === 0) savePng(m.bmp(), process.env.SPLASH);
  m.key(7, 0x80, true);
  for (let f = 0; (m.rd(0x39) | (m.rd(0x3A) << 8)) !== L.isr; f++) { if (f > 600) fail(`матч ${mi}: игра не запустилась после заставки`); m.frame(); }
  m.key(7, 0x80, false);
  m.frame(40);                                            // игра ждёт отпускания клавиши и рисует экран настройки
  if (phase() !== PH.title || m.rd(L.kb_taken) !== 0) fail(`матч ${mi}: нет экрана настройки`);
  m.wr(L.g_n, [n]); m.wr(L.g_rounds, [nRounds]); m.wr(L.g_seed, u32(seed)); m.wr(L.g_fixed, [1]); m.wr(L.g_types, types); m.wr(L.g_step, [1]);
  press(5, `матч ${mi}: заставка`);                       // любая клавиша -> первый раунд
  for (let round = 1; round <= nRounds; round++) {
    TW.shufflePlayers(rng, ps);
    const r = TW.roundStart(rng, ps, 1, 0, 2), v = r.v, bg = r.bg;
    const fl = { rebound: r.rebound, crumble: 50, fall: true, xkill: true, sound: false, wind: r.wind, ballVisible: true, trail: false };
    let cur = r.first, winner = null, over = false;
    for (let t = 0; !over; t++) {
      cur = TW.nextAlive(ps, cur); const p = ps[cur - 1];
      TW.turnBegin(p.hist); TW.autoSwitchWeapon(p);
      const tag = `матч ${mi} (игроки ${types.map((k) => AI[k] || 'человек').join(', ')}; seed 0x${seed.toString(16)}) раунд ${round} ход ${t + 1} место ${cur} ${p.name}`;
      const shot = () => { const res = TW.fire(v, bg, ps, cur, rng, fl); if (res) TW.recordShot(p.hist, p, res.x, res.y); TW.afterShot(v, bg, ps, cur, rng, fl); };
      if (p.ctrl === 3) {
        TW.computerTurn(v, bg, ps, p, rng, fl.rebound);
        if (phase() !== PH.ready) fail(`${tag}: компьютер не готов к выстрелу (фаза ${phase()})`);
        check(tag + ' перед выстрелом', ps, rng, v, (w) => TW.drawPanel(w, p, fl.wind));
        if (t > 60 && !gold) { const c0 = master.word(2) ? 11 : 12; press(c0, tag); if (c0 === 12) winner = TW.abortRound(rng, ps, true); over = true; break; }
        shot();
        const f = press(5, tag); frames += f; worst = Math.max(worst, f); turns++; aiTurns++;
        const alive = ps.filter((q) => q.alive);
        if (alive.length <= 1) { winner = alive[0] || null; over = true; }
        continue;
      }
      if (phase() !== PH.input) fail(`${tag}: игра не ждёт ввода (фаза ${phase()})`);
      if (process.env.SHOT && mi === 0 && round === 1 && t === 4) savePng(m.bmp(), process.env.SHOT);
      check(tag + ' перед вводом', ps, rng, v, (w) => TW.drawPanel(w, p, fl.wind));
      // сценарий: навестись на соседа, покрутить угол и мощность, иногда сменить оружие и развернуться
      const tgt = ps.filter((q) => q.alive && q !== p)[0];
      const codes = [];
      if ((tgt.x > p.x ? 1 : -1) !== p.facing) codes.push(6);
      const wantA = 35 + master.word(30); for (let k = 0; k < 8 + master.word(8); k++) codes.push(p.angle > wantA ? 2 : 1);
      for (let k = 0; k < master.word(12); k++) codes.push(master.word(2) ? 3 : 4);
      if (!master.word(3)) codes.push(8); if (!master.word(5)) codes.push(7);
      if (t > 25) { codes.length = 0; codes.push(master.word(2) ? 11 : 12); }       // затянулось — прервать раунд
      if (process.env.DBG) console.log(tag, 'коды', codes.join(''), ps.map((q) => `${q.idx}:x${q.x} y${q.y} a${q.angle} f${q.facing} w${q.weapon} men${q.men}`).join(' | '));
      for (const c0 of codes) {
        if (c0 >= 11) {
          press(c0, tag);
          if (c0 === 12) winner = TW.abortRound(rng, ps, true);
          over = true; break;
        }
        let c = c0; if (TW.needsWeaponSwitch(p) && c !== 7) c = 8;
        TW.applyCode(v, bg, p, c); press(c0, tag);
      }
      if (over) break;
      check(tag + ' после ввода', ps, rng, v, (w) => TW.drawPanel(w, p, fl.wind));
      if (TW.needsWeaponSwitch(p)) fail(`${tag}: сценарий — оружие пусто`);
      shot();
      const f = press(5, tag); if (process.env.DBG) { const q = (a) => ((m.rd(a) | (m.rd(a + 1) << 8) | (m.rd(a + 2) << 16) | (m.rd(a + 3) << 24)) / 65536).toFixed(4); console.log('  вход:', ['fl_angle','fl_facing','fl_power','fl_power+1','fl_tx','fl_ty','fl_wind','fl_wind+1','fl_rebound','fl_weapon','fl_men','rs_wind','rs_wind+1','rs_rebound'].map((k) => { const [nm, o] = k.split('+'); return k + '=' + m.rd(L[nm] + (+o || 0)); }).join(' ')); console.log('  8080: fl_x', q(L.fl_x), 'fl_y', q(L.fl_y), 'stop', m.rd(L.fl_stop), 'dk_x', m.rd(L.dk_x), 'dk_y', m.rd(L.dk_y), 'dk_r', m.rd(L.dk_r), 'el/er', m.rd(L.dk_el), m.rd(L.dk_er)); } frames += f; worst = Math.max(worst, f); turns++;
      const alive = ps.filter((q) => q.alive);
      if (alive.length <= 1) { winner = alive[0] || null; over = true; break; }
    }
    if (winner) TW.winnerBonus(winner, n);
    TW.results(rng, ps, allAi);
    if (gold) { const g = gold.rounds[round - 1], mine = ps.map((q) => [q.name, q.score, q.wins, q.ammo.join('.')].join(':')).join('|');
      if (g.seed !== rng.seed || g.players !== mine) fail(`золотой матч ${GOLD_IDS[mi]} раунд ${round}: эталонный цикл теста разошёлся с golden.json`); goldRounds++; }
    const tag = `матч ${mi} (игроки ${types.map((k) => AI[k] || 'человек').join(', ')}; seed 0x${seed.toString(16)}) раунд ${round}: результаты`;
    if (phase() !== PH.results) fail(`${tag}: нет экрана результатов (фаза ${phase()})`);
    const res = new Uint8Array(65536); TW.drawResults(res, ps, round, nRounds);
    check(tag, ps, rng, null, null);
    { const g = planesToScreen(m.mem()); let any = false; for (let k = 0; k < 65536; k++) if (g[k]) { any = true; break; }
      if (any) { for (let k = 0; k < 65536; k++) if (g[k] !== res[k]) fail(`${tag}: экран: (${k & 255},${k >> 8}) 8080=${g[k]} эталон=${res[k]}`); panelChecked++; } }
    rounds++;
    if (PNG && mi === 0 && round === 1) savePng(m.bmp(), PNG);
    if (round < nRounds) {
      press(5, tag);
      for (const q of ps) {                                   // магазин по порядку мест
        if (q.ctrl === 3) { TW.aiShop(q, q.strategy); continue; }
        if (q.score - q.spent < TW.MIN_PRICE) continue;
        const stag = `${tag}: магазин ${q.name}`;
        let menu, qty, cart, sel;
        const reset = () => { menu = TW.shopMenu(q); qty = menu.map(() => 0); cart = 0; sel = 0; };
        const look = () => {
          if (phase() !== PH.shop) fail(`${stag}: игра не в магазине (фаза ${phase()})`);
          if (m.rd(L.hs_sel) !== sel) fail(`${stag}: строка 8080=${m.rd(L.hs_sel)} эталон=${sel}`);
          { const cnt = m.rd(L.sh_count), cat = [], num = [], qq = []; for (let k = 0; k < cnt; k++) { cat.push(m.rd(L.sh_cat + k)); num.push(m.rd(L.sh_num + k)); qq.push(m.rd(L.sh_qty + k)); }
            const mine = cat.map((c, k) => c + ':' + num[k] + 'x' + qq[k]).join(' '), ref = menu.map(([c, i], k) => c + ':' + i + 'x' + qty[k]).join(' ');
            const cart8 = m.rd(L.sh_cart) | (m.rd(L.sh_cart + 1) << 8) | (m.rd(L.sh_cart + 2) << 16);
            if (mine !== ref || cart8 !== cart) fail(`${stag}: меню 8080=[${mine}] корзина ${cart8}; эталон=[${ref}] корзина ${cart}; деньги ${q.score - q.spent}`); }
          if (L.shopui_end - L.show_shop < 4) return;         // экран магазина ещё заглушка
          const want = new Uint8Array(65536); TW.drawShop(want, q, menu, qty, cart, sel);
          const g = planesToScreen(m.mem()); for (let k = 0; k < 65536; k++) if (g[k] !== want[k]) fail(`${stag}: экран: (${k & 255},${k >> 8}) 8080=${g[k]} эталон=${want[k]}`);
          shopChecked++;
        };
        const key = (c) => {
          const rows = menu.length + 2;
          if (c === 3) sel = (sel + 1) % rows; else if (c === 4) sel = (sel + rows - 1) % rows;
          else if (sel < menu.length) { const [cat, i] = menu[sel], price = TW.SHOP_PRICE[cat][i];
            if (c === 1) { if (qty[sel] > 0) { qty[sel]--; cart -= price; } } else if (qty[sel] < 9 && price <= q.score - q.spent - cart) { qty[sel]++; cart += price; } }
          else if (c === 5) { TW.shopCommit(q, menu, qty); if (sel === menu.length) reset(); else sel = -9; }
          press(c, stag);
        };
        if (process.env.DBG) console.log(stag, 'деньги', q.score - q.spent, 'порядок', ps.map((z) => z.name + ':' + (z.score - z.spent)).join(' | '));
        reset(); look();
        for (let a = 0; a < 2 + master.word(5) && sel !== -9; a++) {
          for (let k = master.word(menu.length + 3); k > 0; k--) key(master.word(4) ? 3 : 4);
          look();
          for (let k = 1 + master.word(4); k > 0 && sel !== -9; k--) key([2, 2, 5, 1][master.word(4)]);
          if (sel !== -9) look();
        }
        while (sel !== -9) { if (sel === menu.length + 1) key(5); else key(3); }
        if (process.env.DBG) console.log('  магазин закрыт: фаза', phase(), 'hs_place', m.rd(L.hs_place), 'hs_sel', m.rd(L.hs_sel), 'sh_count', m.rd(L.sh_count));
      }
    }
  }
}
console.log(`OK  игра${GOLD ? ' (золотые матчи ' + GOLD_IDS.join(',') + ', раундов сверено с golden.json: ' + goldRounds + ')' : ' с клавиатуры'}: матчей ${M}, раундов ${rounds}, ходов ${turns} (компьютера ${aiTurns}), нажатий ${keys} — записи, RandSeed и экран совпали` +
  ` (панель и результаты сверены ${panelChecked} раз, экран магазина ${shopChecked}); ход в среднем ${(frames / Math.max(1, turns) / 50).toFixed(1)} с, худший ${(worst / 50).toFixed(1)} с`);
