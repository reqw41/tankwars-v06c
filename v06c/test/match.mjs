// Сравнение shuffle_players, winner_bonus, results_sort (8080) с эталоном. node v06c/test/match.mjs
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
const PARAM = 0x80, LIST = 0x7800, MODE_MATCH = 22;
const u32 = (v) => [v & 255, (v >>> 8) & 255, (v >>> 16) & 255, (v >>> 24) & 255];
for (const n of ['shuffle_players', 'winner_bonus', 'results_sort', 'match_end', 'players', 'n_players']) if (L[n] === undefined) { console.error('FAIL нет метки ' + n); process.exit(1); }
let s = 2026; const rnd = (n) => { s = (Math.imul(s, 1103515245) + 12345) >>> 0; return Math.floor(s / 4294967296 * n); };
const NAMES = ['Lobber', 'Rifleman', 'Twanger', 'Windless Wit', 'Mr. Stupid', 'Lob & Shoot', 'Player 1', 'Player 2'];
function mkPlayers(n, tie) {
  return Array.from({ length: n }, (_, i) => {
    const p = TW.newPlayer(i + 1, 10);
    p.name = NAMES[rnd(NAMES.length)] ; p.ctrl = rnd(2) ? 3 : 1; p.strategy = rnd(5);
    p.wins = tie ? rnd(2) : rnd(6); p.score = tie && rnd(2) ? 5000 : rnd(4) === 0 ? -rnd(3000) : rnd(200000); p.spent = rnd(50000);
    p.men = rnd(140) - 20; p.x = 8 + rnd(240); p.y = 30 + rnd(220); p.angle = rnd(91); p.facing = rnd(2) ? 1 : -1; p.power = rnd(1001); p.alive = rnd(4) > 0;
    p.weapon = rnd(18); p.shield = rnd(3) ? 0 : rnd(9000); p.damp = rnd(3) ? 0 : rnd(900); p.herb = rnd(6); p.vick = rnd(6);
    for (let k = 0; k < 18; k++) p.ammo[k] = rnd(3) ? 0 : rnd(300);
    p.hist = { n: rnd(20), planned: rnd(2), power: rnd(1000), angle: rnd(91), facing: rnd(2) ? 1 : -1, weapon: rnd(5), target: 1 + rnd(n) };
    return p;
  });
}
function run8080(kind, ps, seed, c) {
  const n = ps.length, list = new Uint8Array(MAX_PLAYERS * PL_SIZE);
  ps.forEach((p, i) => list.set(packPlayer(p), i * PL_SIZE));
  loadRom(machine, rom);
  const hdr = new Uint8Array(16); hdr[0] = MODE_MATCH; hdr[1] = kind; hdr.set(u32(seed), 4); hdr[8] = n; hdr[14] = c;
  poke(machine, PARAM, hdr); poke(machine, LIST, list);
  const r = runUntil(machine, { haltPc: null, maxInsns: 60_000_000 });
  const seedGot = (r.mem[PARAM + 4] | (r.mem[PARAM + 5] << 8) | (r.mem[PARAM + 6] << 16) | (r.mem[PARAM + 7] << 24)) >>> 0;
  return { recs: Array.from({ length: n }, (_, i) => r.mem.slice(LIST + i * PL_SIZE, LIST + (i + 1) * PL_SIZE)), seed: seedGot, v: r.vcycles };
}
function check(name, tag, got, ps, rngSeed) {
  for (let i = 0; i < ps.length; i++) {
    const want = packPlayer(ps[i]);
    if (viewKey(got.recs[i]) !== viewKey(want)) {
      const a = viewPlayer(got.recs[i]), b = viewPlayer(want), diff = Object.keys(b).filter((k) => String(a[k]) !== String(b[k]));
      console.error(`FAIL ${name} ${tag}: место ${i + 1}, поля ${diff.map((k) => `${k}: 8080=${a[k]} эталон=${b[k]}`).join('; ')}`); process.exit(1);
    }
  }
  if (got.seed !== rngSeed) { console.error(`FAIL ${name} ${tag}: RandSeed 8080=0x${got.seed.toString(16)} эталон=0x${rngSeed.toString(16)}`); process.exit(1); }
}
let nSh = 0, nBo = 0, nRe = 0, worst = 0;
for (let t = 0; t < 120; t++) {
  const n = 2 + rnd(3), seed = (0x9E3779B1 * (t + 3)) >>> 0;
  { const ps = mkPlayers(n, false), in0 = ps.map((p) => p); const got = run8080(1, in0, seed, 0); const rng = new TW.TPRandom(seed); TW.shufflePlayers(rng, ps);
    check('перетасовка', `seed=0x${seed.toString(16)} игроков=${n}`, got, ps, rng.seed); nSh++; worst = Math.max(worst, got.v); }
  { const ps = mkPlayers(n, false), w = 1 + rnd(n); const got = run8080(2, ps, seed, w); TW.winnerBonus(ps[w - 1], n);
    check('бонус', `игроков=${n} победитель=${w}`, got, ps, seed); nBo++; }
  { const ps = mkPlayers(n, t % 3 === 0), auto = t % 2; const got = run8080(3, ps.slice(), seed, auto); const rng = new TW.TPRandom(seed); TW.results(rng, ps, !!auto);
    check('результаты', `seed=0x${seed.toString(16)} игроков=${n} auto=${auto}`, got, ps, rng.seed); nRe++; worst = Math.max(worst, got.v); }
}
console.log(`OK  матч: перетасовка ${nSh}, бонус ${nBo}, результаты ${nRe} случаев совпали; байт ${L.match_end - L.shuffle_players}; такты до ${worst} vcycles`);
