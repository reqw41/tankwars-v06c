// Профиль Вектора-06Ц: матчи компьютеров, проверка инвариантов экрана и «золотые» хеши для будущего порта на 8080.
// node web/test/v06c_selfplay.mjs [--update]  — tests/fixtures/v06c/golden.json
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import * as TW from '../tankwars.js';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const json = (p) => JSON.parse(readFileSync(p, 'utf8'));
TW.init({ barrel: json(path.join(ROOT, 'web/data/barrel.json')), trig: json(path.join(ROOT, 'web/data/trig.json')) });
TW.setProfile(TW.PROFILE_V06C);
const P = TW.PROFILE_V06C, GOLD = path.join(ROOT, 'tests/fixtures/v06c/golden.json');
const sha = (u8) => createHash('sha1').update(u8).digest('hex').slice(0, 16);
const NAMES = ['Lobber', 'Rifleman', 'Twanger', 'Windless Wit', 'Mr. Stupid', 'Lob & Shoot'];
const CASES = [[2, 1], [3, 0x1234], [4, 487264648], [4, 77], [3, 0xC0FFEE], [4, 31337], [2, 2026], [4, 0xDEADBEEF], [4, 5], [3, 999], [4, 123456], [4, 42]];
const ROUNDS = 4;
const out = [], problems = [];
let turns = 0;
for (const [n, seed] of CASES) {
  const rng = new TW.TPRandom(seed);
  const ps = Array.from({ length: n }, (_, i) => { const p = TW.newPlayer(i + 1, ROUNDS); p.ctrl = 3; p.name = NAMES[(i + seed) % NAMES.length]; p.strategy = TW.pickStrategy(p.name, rng); return p; });
  let colDiff = 0;
  const cfg = { walls: 1, bg: 0, windMode: 2, crumble: 50, fall: true, xkill: true, sound: false, ballVisible: true, trail: false,
    onTurn: (ph, cur, r) => { if (ph !== 'turn_end') return; const a = new Uint8Array(r.v), b = new Uint8Array(r.v); TW.crumble(a, r.bg); TW.crumbleColumns(b, r.bg); for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) { colDiff++; break; } } };
  const rounds = [];
  for (let r = 1; r <= ROUNDS; r++) {
    TW.shufflePlayers(rng, ps);
    const res = TW.playRound(rng, ps, cfg);
    turns += res.turns;
    // инварианты: только 8 цветов; панель (строки 0..23) не тронута; временного цвета не осталось; буфер фона пуст;
    // рамка цела; живые танки внутри поля; осыпание по столбцам совпадает с осыпанием со списком
    const hist = new Array(256).fill(0); for (const c of res.v) hist[c]++;
    const tag = `${n}/${seed} r${r}`;
    if (hist.slice(8).some(Boolean)) problems.push(`${tag}: цвет вне 0..7`);
    if (res.v.subarray(0, 24 * 256).some(Boolean)) problems.push(`${tag}: запись в панель`);
    if (hist[3]) problems.push(`${tag}: остался временный цвет (${hist[3]})`);
    if (res.bg.some(Boolean)) problems.push(`${tag}: буфер фона не пуст`);
    let hole = 0;
    for (const [x1, y1, x2, y2] of [[P.X0 - 3, P.Y0 - 3, P.X1 + 3, P.Y1 + 3], [P.X0 - 1, P.Y0 - 1, P.X1 + 1, P.Y1 + 1]]) {
      for (let x = x1; x <= x2; x++) for (const y of [y1, y2]) if (res.v[y * 256 + x] !== P.frame) hole++;
      for (let y = y1; y <= y2; y++) for (const x of [x1, x2]) if (res.v[y * 256 + x] !== P.frame) hole++;
    }
    if (hole) problems.push(`${tag}: рамка повреждена (${hole})`);
    if (colDiff) problems.push(`${tag}: осыпание по столбцам расходится`);
    for (const p of ps) if (p.alive && !(p.x >= P.X0 + 4 && p.x <= P.X1 - 4 && p.y >= P.Y0 && p.y <= P.Y1)) problems.push(`${tag}: танк вне поля ${p.x},${p.y}`);
    if (res.turns >= 5000) problems.push(`${n}/${seed} r${r}: раунд не кончился`);
    if (res.winner) TW.winnerBonus(res.winner, n);
    TW.results(rng, ps, true);
    rounds.push({ turns: res.turns, winner: res.winner ? res.winner.name : null, seed: rng.seed, screen: sha(res.v),
      players: ps.map((p) => [p.name, p.score, p.wins, p.ammo.join('.')].join(':')).join('|') });
    if (r < ROUNDS) for (const p of ps) TW.aiShop(p, p.strategy);
  }
  out.push({ players: n, seed, rounds });
}
// экраны: панель хода, результаты, магазин — на фиксированном состоянии
{
  const rng = new TW.TPRandom(31337);
  const ps = ['Twanger', 'Lob & Shoot', 'Windless Wit', 'Player 4'].map((nm, i) => { const p = TW.newPlayer(i + 1, 10); p.name = nm; return p; });
  ps[0].score = 45700; ps[0].wins = 2; ps[0].ammo[5] = 1000; ps[1].score = 11460; ps[1].spent = 3000; ps[1].wins = 1; ps[1].herb = 5; ps[1].vick = 5; ps[1].guided = 1;
  const r = TW.roundStart(rng, ps, 1, 0, 2);
  TW.drawPanel(r.v, ps[1], r.wind);
  const res = new Uint8Array(65536); TW.drawResults(res, ps, 2, 10);
  const shop = new Uint8Array(65536), menu = TW.shopMenu(ps[0]), qty = menu.map(() => 0); qty[1] = 2; TW.drawShop(shop, ps[0], menu, qty, 8000, 1);
  for (const [nm, buf] of [['panel', r.v], ['results', res], ['shop', shop]]) { if (buf.some((c) => c > 7)) problems.push(`экран ${nm}: цвет вне 0..7`); }
  out.push({ screens: { panel: sha(r.v), results: sha(res), shop: sha(shop) } });
}
console.log(`матчей ${CASES.length}, раундов ${CASES.length * ROUNDS}, ходов ${turns}; нарушений инвариантов: ${problems.length}`);
for (const p of problems.slice(0, 10)) console.log('  ' + p);
if (process.argv.includes('--width')) { const FX = await import('../fixmath.js'); console.log('наибольшая разрядность (бит модуля):'); for (const [k, b] of Object.entries(FX.WIDTH)) console.log(`  ${k}: ${b}`); }
if (process.argv.includes('--update') || !existsSync(GOLD)) { writeFileSync(GOLD, JSON.stringify(out, null, 1)); console.log('золотые хеши записаны'); }
else { const same = JSON.stringify(json(GOLD)) === JSON.stringify(out); console.log(same ? 'OK  совпадает с золотыми хешами' : 'FAIL отличается от золотых хешей'); if (!same) process.exit(1); }
process.exit(problems.length ? 1 : 0);
