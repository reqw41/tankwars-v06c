// Турнир компьютеров один на один в эталоне: доля выигранных раундов. PROFILE=v06c|dos, WALLS=0|1|2, ROUNDS, MATCHES
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import * as TW from '../../web/tankwars.js';
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const json = (p) => JSON.parse(fs.readFileSync(path.join(ROOT, p), 'utf8'));
TW.init({ barrel: json('web/data/barrel.json'), trig: json('web/data/trig.json') });
const prof = (process.env.PROFILE || 'v06c') === 'dos' ? TW.PROFILE_DOS : TW.PROFILE_V06C;
TW.setProfile(prof);
const NAMES = ['Mr. Stupid', 'Birdy Bonker', 'Rifleman', 'Lobber', 'Lob & Shoot', 'Windless Wit', 'Twanger'];
const ROUNDS = +process.env.ROUNDS || 10, MATCHES = +process.env.MATCHES || 12, walls = +(process.env.WALLS ?? 1);
const tab = {}, turnsBy = {};
for (let a = 0; a < NAMES.length; a++) for (let b = a + 1; b < NAMES.length; b++) {
  if (process.env.ONLY && NAMES[b] !== process.env.ONLY) { tab[NAMES[a] + '|' + NAMES[b]] = [0, 0, 0]; turnsBy[NAMES[a] + '|' + NAMES[b]] = 0; continue; }
  let wa = 0, wb = 0, draw = 0, turns = 0;
  for (let mi = 0; mi < MATCHES; mi++) {
    const rng = new TW.TPRandom(1000 + mi * 7919 + a * 131 + b * 17);
    const ps = [NAMES[a], NAMES[b]].map((nm, i) => { const p = TW.newPlayer(i + 1, ROUNDS); p.ctrl = 3; p.name = nm; p.strategy = TW.pickStrategy(nm, rng); return p; });
    const cfg = { walls, bg: 0, windMode: 2, crumble: 50, fall: true, xkill: true, sound: false, ballVisible: true, trail: false };
    for (let r = 1; r <= ROUNDS; r++) {
      TW.shufflePlayers(rng, ps);
      const res = TW.playRound(rng, ps, cfg); turns += res.turns;
      if (res.winner) { if (res.winner.name === NAMES[a]) wa++; else wb++; TW.winnerBonus(res.winner, 2); } else draw++;
      TW.results(rng, ps, true);
      if (r < ROUNDS) for (const p of ps) TW.aiShop(p, p.strategy);
    }
  }
  tab[NAMES[a] + '|' + NAMES[b]] = [wa, wb, draw]; turnsBy[NAMES[a] + '|' + NAMES[b]] = turns / (MATCHES * ROUNDS);
}
const tot = Object.fromEntries(NAMES.map((n) => [n, [0, 0]]));
for (const [k, [wa, wb, d]] of Object.entries(tab)) { const [a, b] = k.split('|'); tot[a][0] += wa; tot[a][1] += wa + wb + d; tot[b][0] += wb; tot[b][1] += wa + wb + d; }
console.log(`профиль ${process.env.PROFILE || 'v06c'}, стены ${walls}, ${MATCHES} матчей по ${ROUNDS} раундов на пару`);
if (!process.env.ONLY) console.log('всего побед в раундах: ' + NAMES.map((n) => `${n} ${(100 * tot[n][0] / tot[n][1]).toFixed(0)}%`).join(', '));
console.log('Twanger против: ' + NAMES.slice(0, 6).map((n) => { const [wa, wb, d] = tab[n + '|Twanger']; return `${n} ${wb}:${wa}${d ? ' (ничьих ' + d + ')' : ''}, ходов ${turnsBy[n + '|Twanger'].toFixed(0)}`; }).join('; '));
