// Сравнение профиля Вектора: fixed (Q16.16) против того же профиля с fixed:false (Real48).
// node web/test/v06c_compare.mjs
// Печатает отклонение точки падения и статистику раундов. Числа отсюда переносятся в отчёт.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import * as TW from '../tankwars.js';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const json = (p) => JSON.parse(readFileSync(p, 'utf8'));
TW.init({ barrel: json(path.join(ROOT, 'web/data/barrel.json')), trig: json(path.join(ROOT, 'web/data/trig.json')) });

const prof = (fixed) => { TW.setProfile({ ...TW.PROFILE_V06C, fixed }); return TW.profile(); };
const NSHOT = 2000, NROUND = 200;

function field(seed) {
  prof(false);
  const P = TW.profile();
  const rng = new TW.TPRandom(seed >>> 0);
  const v = new Uint8Array(P.W * P.H);
  TW.renderTerrain(TW.generateTerrain(rng, 2), v);
  return v;
}
function shoot(fixed, screen, inp) {
  const P = prof(fixed);
  const v = new Uint8Array(screen);
  const get = (x, y) => (x >= 0 && x < P.W && y >= 0 && y < P.H ? v[y * P.W + x] : 0);
  const r = TW.flight(inp, get);
  const last = r.positions.length ? r.positions[r.positions.length - 1] : [0, 0];
  return { last, stop: r.stop, n: r.positions.length };
}

const master = new TW.TPRandom(20261003);
const dist = [];
const worst = [];
let stopDiff = 0;
for (let i = 0; i < NSHOT; i++) {
  const angle = master.word(91);
  const power = master.word(1000) + 1;
  const wind = master.word(60001) - 30000;
  const facing = master.word(2) ? 1 : -1;
  const rebound = master.word(2) === 1;
  const screen = field(master._next());
  const P = TW.profile();
  let tx = P.X0 + 8 + master.word(P.X1 - P.X0 - 16);
  let top = P.Y1;
  for (let y = P.Y0; y <= P.Y1; y++) if (screen[y * P.W + tx] === P.ground) { top = y; break; }
  const ty = Math.max(P.Y0, top - 6);
  const inp = { angle, power, facing, tank_x: tx, tank_y: ty, wind, rebound, weapon: 1, men: 100, guided: 0 };
  const a = shoot(false, screen, inp);
  const b = shoot(true, screen, inp);
  const d = Math.hypot(a.last[0] - b.last[0], a.last[1] - b.last[1]);
  dist.push(d);
  if (a.stop !== b.stop) stopDiff++;
  if (d > 0 && (worst.length < 8 || d > worst[worst.length - 1].d)) {
    worst.push({ d, angle, power, wind, facing, rebound, steps: a.n, stepsF: b.n, stopA: a.stop, stopB: b.stop, ax: a.last[0], ay: a.last[1], bx: b.last[0], by: b.last[1] });
    worst.sort((p, q) => q.d - p.d);
    worst.length = Math.min(worst.length, 8);
  }
}
dist.sort((a, b) => a - b);
const mean = dist.reduce((s, x) => s + x, 0) / dist.length;
const p95 = dist[Math.ceil(0.95 * dist.length) - 1];
const mx = dist[dist.length - 1];
const over2 = dist.filter((x) => x > 2).length;
console.log(`выстрелов ${NSHOT}`);
console.log(`impact_mean ${mean}`);
console.log(`impact_p95 ${p95}`);
console.log(`impact_max ${mx}`);
console.log(`impact_gt2 ${over2}`);
console.log(`stop_differ ${stopDiff}`);
console.log('худшие:');
for (const w of worst) console.log(`  d=${w.d.toFixed(3)} angle=${w.angle} power=${w.power} wind=${w.wind} face=${w.facing} reb=${w.rebound} steps=${w.steps}/${w.stepsF} ${w.stopA}->${w.stopB} (${w.ax},${w.ay})->(${w.bx},${w.by})`);

const NAMES = ['Lobber', 'Rifleman', 'Twanger', 'Windless Wit', 'Mr. Stupid', 'Lob & Shoot'];
function playRounds(fixed) {
  prof(fixed);
  let len = 0, unfinished = 0, rounds = 0;
  const stat = {};
  for (const name of NAMES) stat[name] = { shots: 0, tank: 0, terrain: 0, miss: 0, rounds: 0 };
  for (let i = 0; i < NROUND; i++) {
    const n = 2 + (i % 3);
    const rng = new TW.TPRandom((0xA11CE + i * 9973) >>> 0);
    const ps = Array.from({ length: n }, (_, k) => {
      const p = TW.newPlayer(k + 1, 1);
      p.ctrl = 3;
      p.name = NAMES[(i + k) % NAMES.length];
      p.strategy = TW.pickStrategy(p.name, rng);
      return p;
    });
    const windMode = i % 5;
    const r = TW.roundStart(rng, ps, i % 3, 0, windMode);
    const fl = { rebound: r.rebound, crumble: 50, fall: true, xkill: true, sound: false, wind: r.wind, ballVisible: true, trail: false };
    let cur = r.first, turns = 0, done = false;
    for (; turns < 5000; turns++) {
      cur = TW.nextAlive(ps, cur);
      const p = ps[cur - 1];
      TW.turnBegin(p.hist);
      TW.autoSwitchWeapon(p);
      TW.computerTurn(r.v, r.bg, ps, p, rng, fl.rebound);
      const res = TW.fire(r.v, r.bg, ps, cur, rng, fl);
      const s = stat[p.name];
      s.rounds++;
      if (res) {
        s.shots++;
        if (res.stop === 'tank') s.tank++;
        else if (res.stop === 'terrain') s.terrain++;
        else s.miss++;
        TW.recordShot(p.hist, p, res.x, res.y);
      }
      TW.afterShot(r.v, r.bg, ps, cur, rng, fl);
      if (ps.filter((t) => t.alive).length <= 1) { done = true; break; }
    }
    const played = turns + 1;
    len += played;
    rounds++;
    if (!done) unfinished++;
  }
  return { len: len / rounds, unfinished, stat };
}
const rounds = [];
for (const fixed of [false, true]) {
  const r = playRounds(fixed);
  rounds.push(r);
  console.log(`раунды fixed=${fixed} n=${NROUND} avg_len ${r.len} unfinished ${r.unfinished}`);
  for (const name of NAMES) {
    const s = r.stat[name];
    const rate = s.shots ? s.tank / s.shots : 0;
    console.log(`  ${name} shots=${s.shots} tank=${s.tank} terrain=${s.terrain} miss=${s.miss} hit_rate ${rate}`);
  }
}
console.log(`len_ratio ${rounds[1].len / rounds[0].len}`);
console.log(`len_delta_rel ${(rounds[1].len - rounds[0].len) / rounds[0].len}`);
