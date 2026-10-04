// Полёт снаряда на 8080 против flightDraw эталона (PROFILE_V06C). node v06c/test/flight.mjs [N]
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import * as TW from '../../web/tankwars.js';
import { createMachine, loadRom, poke, runUntil, parseSym } from '../tools/run.mjs';
import { planesToScreen, firstPixelDiff, screenToPlanes } from '../tools/screen.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const json = (p) => JSON.parse(fs.readFileSync(path.join(ROOT, p), 'utf8'));
TW.init({ barrel: json('web/data/barrel.json'), trig: json('web/data/trig.json') });
TW.setProfile(TW.PROFILE_V06C);
const P = TW.PROFILE_V06C, L = parseSym(path.join(ROOT, 'v06c/build/tw.sym'));
const rom = new Uint8Array(fs.readFileSync(path.join(ROOT, 'v06c/build/tw.rom')));
const machine = createMachine();
const PARAM = 0x80, LIST = 0x8400, RESULT = 0x9600, MODE_FLIGHT = 23;
const N = +process.argv[2] || 300;
const master = new TW.TPRandom(20261003);
const i32 = (m, o) => (m[o] | (m[o + 1] << 8) | (m[o + 2] << 16) | (m[o + 3] << 24)) | 0;
const STOP = { max: 0, terrain: 1, tank: 2, bounds: 3 };
let cases = 0, steps = 0, cyc = 0, kinds = { 0: 0, 1: 0, 2: 0, 3: 0 };
for (let i = 0; i < N; i++) {
  const players = 2 + master.word(3);
  // экран раунда из эталона
  const rng = new TW.TPRandom(master._next());
  const ps = Array.from({ length: players }, (_, k) => TW.newPlayer(k + 1, 10));
  const r0 = TW.roundStart(rng, ps, master.word(3), 0, 2);
  const v = r0.v, bg = r0.bg;
  const sh = ps[master.word(players)];
  const angle = master.word(91), power = [master.word(1001), master.word(300) + 50, 1000 - 2 * 100, 1000][master.word(4)];
  let wind = [0, master.word(601) - 300, master.word(60001) - 30000][master.word(3)];
  if (process.env.G && Math.abs(wind) > 300) wind = wind % 300;      // с наведением — только настоящий ветер: на шквале эталон выходит из разрядности
  const facing = master.word(2) ? 1 : -1, rebound = master.word(2), men = [100, 100, 60, 1][master.word(4)], weapon = [1, 1, 1, 13][master.word(4)], ball = master.word(8) ? 1 : 0;
  const tg = ps[(sh.idx % players)], guided = process.env.G ? 1 + master.word(3) : 0;      // G=1 — выстрелы с наведением
  const inp = { angle, power, facing, tank_x: sh.x, tank_y: sh.y, wind, rebound: !!rebound, weapon, men, guided, target: guided ? [tg.x, tg.y] : null, maxSteps: 200000 };
  const tag = `#${i} угол=${angle} мощность=${power} ветер=${wind} напр=${facing} стены=${rebound} men=${men} оружие=${weapon} игроков=${players} танк=(${sh.x},${sh.y}) мяч=${ball}`;
  loadRom(machine, rom);
  const mem0 = new Uint8Array(0x10000); screenToPlanes(v, mem0);
  poke(machine, 0xA000, mem0.subarray(0xA000));
  let n = 0;
  const want = TW.flightDraw(v, bg, inp, sh.idx, !!ball, false, players, () => { n++; });
  const hdr = new Uint8Array(16); hdr[0] = MODE_FLIGHT;
  poke(machine, PARAM, hdr);
  poke(machine, LIST, [angle, facing & 255, power & 255, power >> 8, sh.x, sh.y, wind & 255, (wind >> 8) & 255, rebound, weapon, men & 255, (men >> 8) & 255, players, ball, guided, guided ? tg.x : 0, guided ? tg.y : 0]);
  const r = runUntil(machine, { haltPc: null, maxInsns: 2_000_000_000 });
  const got = { stop: r.mem[RESULT], hit: r.mem[RESULT + 1], x: i32(r.mem, RESULT + 2), y: i32(r.mem, RESULT + 6) };
  const exp = { stop: STOP[want.stop], hit: want.hit, x: Math.round(want.x * 65536), y: Math.round(want.y * 65536) };
  if (JSON.stringify(got) !== JSON.stringify(exp)) { console.error(`FAIL ${tag}: 8080=${JSON.stringify(got)} эталон=${JSON.stringify(exp)}`); process.exit(1); }
  const d = firstPixelDiff(planesToScreen(r.mem), v);
  if (d) { const g = planesToScreen(r.mem), all = []; for (let k = 0; k < 65536 && all.length < 12; k++) if (g[k] !== v[k]) all.push(`(${k & 255},${k >> 8}) 8080=${g[k]} эталон=${v[k]}`); console.error(`FAIL ${tag}: остановка ${JSON.stringify(exp)}; экран: ${all.join(' ')}`); process.exit(1); }
  cases++; steps += n + 1; cyc += r.vcycles; kinds[exp.stop]++;
}
console.log(`OK  полёт: ${cases} выстрелов совпали (остановка, цвет, x, y, экран): земля ${kinds[1]}, танк ${kinds[2]}, вылет ${kinds[3]}, предел ${kinds[0]}; ` +
  `байт ${L.flight_end - L.flight}; в среднем ${Math.round(cyc / steps)} vcycles на подшаг`);
