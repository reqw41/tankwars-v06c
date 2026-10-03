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
const NAMES = ['Lobber', 'Rifleman', 'Twanger', 'Windless Wit', 'Mr. Stupid', 'Lob & Shoot', 'Rifleman', 'Lobber', 'Twanger', 'Windless Wit'];
const CASES = [[2, 1], [3, 0x1234], [4, 487264648], [5, 77], [6, 0xC0FFEE], [8, 31337], [10, 2026], [10, 0xDEADBEEF], [4, 5], [7, 999]];
const ROUNDS = 4;
const out = [], problems = [];
let turns = 0;
for (const [n, seed] of CASES) {
  const rng = new TW.TPRandom(seed);
  const ps = Array.from({ length: n }, (_, i) => { const p = TW.newPlayer(i + 1, ROUNDS); p.ctrl = 3; p.name = NAMES[(i + seed) % NAMES.length]; p.strategy = TW.pickStrategy(p.name, rng); return p; });
  const cfg = { walls: 1, bg: 6, windMode: 2, crumble: 50, fall: true, xkill: true, sound: false, ballVisible: true, trail: true };
  const rounds = [];
  for (let r = 1; r <= ROUNDS; r++) {
    TW.shufflePlayers(rng, ps);
    const res = TW.playRound(rng, ps, cfg);
    turns += res.turns;
    // инварианты: только 16 цветов; панель (строки 0..23) не тронута; временный цвет огня убран; живые танки внутри поля
    const hist = new Array(256).fill(0); for (const c of res.v) hist[c]++;
    if (hist.slice(16).some(Boolean)) problems.push(`${n}/${seed} r${r}: цвет вне 0..15`);
    if (res.v.subarray(0, 24 * 256).some(Boolean)) problems.push(`${n}/${seed} r${r}: запись в панель`);
    if (hist[5] || hist[4]) problems.push(`${n}/${seed} r${r}: остался огонь/мяч (${hist[5]}/${hist[4]})`);
    for (const p of ps) if (p.alive && !(p.x >= P.X0 + 4 && p.x <= P.X1 - 4 && p.y >= P.Y0 && p.y <= P.Y1)) problems.push(`${n}/${seed} r${r}: танк вне поля ${p.x},${p.y}`);
    if (res.turns >= 5000) problems.push(`${n}/${seed} r${r}: раунд не кончился`);
    if (res.winner) TW.winnerBonus(res.winner, n);
    TW.results(rng, ps, true);
    rounds.push({ turns: res.turns, winner: res.winner ? res.winner.name : null, seed: rng.seed, screen: sha(res.v),
      players: ps.map((p) => [p.name, p.score, p.wins, p.ammo.join('.')].join(':')).join('|') });
    if (r < ROUNDS) for (const p of ps) TW.aiShop(p, p.strategy);
  }
  out.push({ players: n, seed, rounds });
}
console.log(`матчей ${CASES.length}, раундов ${CASES.length * ROUNDS}, ходов ${turns}; нарушений инвариантов: ${problems.length}`);
for (const p of problems.slice(0, 10)) console.log('  ' + p);
if (process.argv.includes('--update') || !existsSync(GOLD)) { writeFileSync(GOLD, JSON.stringify(out, null, 1)); console.log('золотые хеши записаны'); }
else { const same = JSON.stringify(json(GOLD)) === JSON.stringify(out); console.log(same ? 'OK  совпадает с золотыми хешами' : 'FAIL отличается от золотых хешей'); if (!same) process.exit(1); }
process.exit(problems.length ? 1 : 0);
