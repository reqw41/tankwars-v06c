// Повтор целого матча компьютеров: JS-модель против событий настоящей игры (tests/fixtures/t05/match/*.json).
// Состояние ведётся с самого начала матча и сверяется на каждом событии: вход в перетасовку, раунд, результаты, магазин.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import * as TW from '../tankwars.js';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const json = (p) => JSON.parse(readFileSync(p, 'utf8'));
TW.init({ barrel: json(path.join(ROOT, 'web/data/barrel.json')), trig: json(path.join(ROOT, 'web/data/trig.json')) });
const hexU8 = (h) => new Uint8Array(Buffer.from(h, 'hex'));
// настройки стенда = BOMB.CFG оригинала (звук включён: он тратит случайные числа)
const CFG = { walls: 1, bg: 6, windMode: 2, crumble: 50, fall: true, xkill: true, sound: true, ballVisible: true, trail: true };
const key = (p) => [p.name, p.score, p.spent, p.wins, p.men, p.ammo.join('.'), p.herb, p.vick, p.shield, p.damp].join();
const mk = (e) => e.recs.slice(1).map((h, i) => { const p = TW.playerFromRec(hexU8(h), i + 1, 0x0e); p.ctrl = e.ctrl[i + 1]; p.strategy = e.strategy[i + 1]; return p; });

let bad = 0;
for (const m of process.argv.slice(2).length ? process.argv.slice(2) : ['a', 'b', 'c']) {
  const ev = json(path.join(ROOT, `tests/fixtures/t05/match/${m}.json`));
  const ps = mk(ev[0]); const rng = new TW.TPRandom(ev[0].seed);
  let ok = 0, n = 0, turns = 0;
  for (let i = 0; i + 1 < ev.length; i++) {
    const a = ev[i], b = ev[i + 1];
    if (a.event === 'shuffle') TW.shufflePlayers(rng, ps);
    else if (a.event === 'round') { const r = TW.playRound(rng, ps, CFG); turns += r.turns; if (r.winner) TW.winnerBonus(r.winner, ps.length); }
    else if (a.event === 'results') TW.results(rng, ps, true);
    else if (a.event === 'shop') for (const p of ps) if (a.ai_buys) TW.aiShop(p, p.strategy);
    const want = mk(b); n++;
    const good = rng.seed === b.seed && ps.map(key).join('|') === want.map(key).join('|');
    if (good) ok++;
    else {
      console.log(`  матч ${m}: расхождение после события ${i} (${a.event}, раунд ${a.round}): seed ${rng.seed === b.seed}`);
      ps.forEach((p, k) => { if (key(p) !== key(want[k])) console.log('    ', key(p), '\n     ', key(want[k])); });
      break;
    }
  }
  console.log(`${ok === n ? 'OK ' : 'FAIL'} матч ${m}: ${ok}/${n} событий, ходов сыграно ${turns}`);
  if (ok !== n) bad++;
}
process.exit(bad ? 1 : 0);
