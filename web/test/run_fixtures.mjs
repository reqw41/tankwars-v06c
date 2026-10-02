// Сверка JS-модели web/tankwars.js со ВСЕМИ эталонами настоящей игры из tests/fixtures.
// node web/test/run_fixtures.mjs   -> по разделам: совпало / всего; код выхода 1 при любом расхождении.
import { readFileSync } from 'node:fs';
import { inflateSync } from 'node:zlib';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import * as TW from '../tankwars.js';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const FX = (p) => path.join(ROOT, 'tests/fixtures', p);
const json = (p) => JSON.parse(readFileSync(p, 'utf8'));
const z = (p) => new Uint8Array(inflateSync(readFileSync(p)));
TW.init({ barrel: json(path.join(ROOT, 'web/data/barrel.json')), trig: json(path.join(ROOT, 'web/data/trig.json')) });

// запись игрока (0x61 байт) <-> объект танка
function decode(hex, idx) {
  const b = Buffer.from(hex, 'hex');
  return { idx, x: b.readInt16LE(0), y: b.readInt16LE(2), score: b.readInt32LE(4), power: b.readInt16LE(0x0e),
    angle: b.readInt16LE(0x10), facing: b.readInt16LE(0x12), men: b.readInt16LE(0x14), alive: b[0x16] !== 0,
    weapon: b.readInt16LE(0x17), energy: b.readInt16LE(0x2b), shield: b.readInt32LE(0x45), damp: b.readInt32LE(0x49) };
}
const same = (a, b) => a.length === b.length && a.every((v, i) => v === b[i]);
const vdiff = (a, b) => { let n = 0; for (let i = 0; i < 64000; i++) if (a[i] !== b[i]) n++; return n; };
const sha1 = (u8) => createHash('sha1').update(u8).digest('hex');

const results = [];
function section(name, cases, fn) {
  let ok = 0; const bad = [];
  for (const c of cases) {
    let r;
    try { r = fn(c); } catch (e) { r = 'ERR ' + e.message; }
    if (r === true) ok++; else bad.push(`${c.name || c.label || c.seed}: ${r}`);
  }
  results.push([name, ok, cases.length, bad]);
}

// --- T03: рельеф ---
section('рельеф (T03)', json(FX('t03/terrain_orig.json')), (c) => {
  const rng = new TW.TPRandom(c.seed), t = TW.generateTerrain(rng, c.players);
  const v = TW.renderTerrain(t, new Uint8Array(64000));
  const mask = v.map((b) => (b === 2 ? 1 : 0));
  return (t.hFinal === c.h_final && sha1(mask) === c.dirt_mask_sha1) || `h ${t.hFinal}/${c.h_final}`;
});

// --- T03: начало раунда (фон -> рельеф -> танки -> рамка) ---
section('начало раунда (T03)', json(FX('t03/placement/index.json')), (c) => {
  const bg = z(FX(`t03/placement/${c.name}.bg.z`));
  const rng = new TW.TPRandom(c.seed);
  const v = TW.renderTerrain(TW.generateTerrain(rng, c.players), new Uint8Array(bg));
  const ts = TW.placeTanks(rng, c.players, v, bg, !!c.rebound);
  const got = ts.map((t) => [t.x, t.y, t.angle, t.facing, t.men].join());
  const want = c.tanks.map((t) => [t.x, t.y, t.angle, t.facing, t.men].join());
  if (!same(got, want)) return 'танки ' + got + ' / ' + want;
  return sha1(v) === c.vram_sha1 || 'vram ' + vdiff(v, z(FX(`t03/placement/${c.name}.vram.z`)));
});

// --- T03: обычный взрыв ---
for (const dir of ['explosion', 'explosion_direct']) {
  section(`взрыв ${dir} (T03)`, json(FX(`t03/${dir}/index.json`)), (c) => {
    const v = z(FX(`t03/${dir}/${c.name}.pre.z`)), bg = z(FX(`t03/${dir}/${c.name}.bg.z`)), post = z(FX(`t03/${dir}/${c.name}.post.z`));
    const ps = c.pre.players.map((h, i) => decode(h, i + 1));
    const rng = new TW.TPRandom(c.pre.seed);
    TW.explode(v, bg, ps, c.x, c.y, c.hit_color, c.shooter, c.weapon, rng, c.sound);
    const want = c.post.players.map((h, i) => decode(h, i + 1));
    if (!same(ps.map((p) => [p.men, p.shield, p.score].join()), want.map((p) => [p.men, p.shield, p.score].join()))) return 'игроки';
    if (rng.seed !== c.post.seed) return 'RandSeed';
    return vdiff(v, post) === 0 || 'vram ' + vdiff(v, post);
  });
}

// --- T03: осыпание и падение ---
section('осыпание/падение (T03)', json(FX('t03/crumble/index.json')), (c) => {
  const d = 't03/crumble/';
  const v = z(FX(d + c.name + '.pre.z')), bg = z(FX(d + c.name + '.bg.z')), post = z(FX(d + c.name + '.post.z'));
  const ts = c.pre.players.map((h, i) => decode(h, i + 1));
  const rng = new TW.TPRandom(c.pre.seed);
  if (c.event === 'crumble') TW.crumbleGate(v, bg, rng, c.pre.percent, !!c.pre.rebound);
  else TW.tanksFall(v, bg, ts, rng, !!c.pre.rebound);
  const want = c.post.players.map((h, i) => decode(h, i + 1));
  if (!same(ts.map((t) => [t.x, t.y, t.men, t.damp].join()), want.map((t) => [t.x, t.y, t.men, t.damp].join()))) return 'танки';
  if (rng.seed !== c.post.seed) return 'RandSeed';
  return vdiff(v, post) === 0 || 'vram ' + vdiff(v, post);
});

// --- T04: особое оружие ---
const vpOf = (c) => { const b = Buffer.from(c.viewport, 'hex'); return [[b.readUInt16LE(0), b.readUInt16LE(2), b.readUInt16LE(4), b.readUInt16LE(6)], b[8]]; };
function t4(kind, fn) {
  let idx; try { idx = json(FX(`t04/${kind}/index.json`)); } catch { return; }
  section(`${kind} (T04)`, idx, (c) => {
    const d = `t04/${kind}/`;
    const v = z(FX(d + c.name + '.pre.z')), bg = z(FX(d + c.name + '.bg.z')), post = z(FX(d + c.name + '.post.z'));
    return fn(c, v, bg, post);
  });
}
const cmpPlayersHex = (ps, c) => {
  const want = c.post.players.map((h, i) => decode(h, i + 1));
  return same(ps.map((p) => [p.men, p.shield, p.score, p.energy, p.power].join()), want.map((p) => [p.men, p.shield, p.score, p.energy, p.power].join()));
};
t4('sonic', (c, v, bg, post) => { const [vp, clip] = vpOf(c); const rng = new TW.TPRandom(c.pre.seed); TW.sonic(v, bg, c.x, c.y, rng, c.sound, vp, !!clip); return (rng.seed === c.post.seed && vdiff(v, post) === 0) || 'vram ' + vdiff(v, post); });
t4('cri', (c, v, bg, post) => {
  const ps = c.pre.players.map((h, i) => decode(h, i + 1)); const rng = new TW.TPRandom(c.pre.seed);
  TW.cri(v, bg, ps, c.x, c.y, c.hit_color, c.shooter, c.weapon, rng, c.sound);
  if (!cmpPlayersHex(ps, c)) return 'игроки'; if (rng.seed !== c.post.seed) return 'RandSeed';
  return vdiff(v, post) === 0 || 'vram ' + vdiff(v, post);
});
t4('dirt', (c, v, bg, post) => { const [vp] = vpOf(c); TW.dirtBall(v, c.x, c.y, c.weapon, vp); return vdiff(v, post) === 0 || 'vram ' + vdiff(v, post); });
t4('xdirt', (c, v, bg, post) => { const [vp] = vpOf(c); const rng = new TW.TPRandom(c.pre.seed); TW.explosiveDirt(v, bg, c.x, c.y, rng, c.sound, c.crumble, vp); return (rng.seed === c.post.seed && vdiff(v, post) === 0) || 'vram ' + vdiff(v, post); });
for (const kind of ['laser', 'laser2']) t4(kind, (c, v, bg, post) => {
  const ps = c.pre.players.map((h, i) => decode(h, i + 1)); const rng = new TW.TPRandom(c.pre.seed);
  TW.laser(v, bg, ps, c.player, rng, c.sound, !!c.rebound);
  if (!cmpPlayersHex(ps, c)) return 'игроки'; if (rng.seed !== c.post.seed) return 'RandSeed';
  return vdiff(v, post) === 0 || 'vram ' + vdiff(v, post);
});
section('наведение (T04)', json(FX('t04/guide/index.json')), (c) => {
  const terr = z(FX(`t04/guide/${c.name}.vram.z`));
  const r = TW.flight({ angle: c.angle, power: c.power, facing: c.facing, tank_x: c.x, tank_y: c.y, men: c.men, wind: c.wind,
    guided: c.kind, target: [c.target_x, c.target_y], weapon: 1 }, (x, y) => (x >= 0 && x < 320 && y >= 0 && y < 200 ? terr[y * 320 + x] : 0));
  return same(r.positions.map(String), c.positions.map(String)) || `точек ${r.positions.length}/${c.positions.length}`;
});

// --- T02: полёт (трассы оригинала) и ветер ---
section('полёт (T02, оригинал)', json(FX('js/flight_orig.json')), (c) => {
  let terr;
  if (c.terrain_z) terr = new Uint8Array(inflateSync(Buffer.from(c.terrain_z, 'base64')));
  else { terr = new Uint8Array(64000); for (let i = 180 * 320; i < 64000; i++) terr[i] = 2; }
  const r = TW.flight({ angle: c.angle, power: c.power, facing: c.facing ?? 1, tank_x: c.tank_x, tank_y: c.tank_y,
    wind: c.wind || 0, rebound: !!c.rebound, weapon: c.weapon ?? 1, guided: c.guided || 0, men: c.men ?? 5 },
  (x, y) => (x >= 0 && x < 320 && y >= 0 && y < 200 ? terr[y * 320 + x] : 0));
  return same(r.positions.map(String), c.positions.map(String)) || `точек ${r.positions.length}/${c.positions.length}`;
});
section('ветер (T02, оригинал)', json(FX('js/wind_orig.json')), (c) => {
  const w = TW.generateWind(new TW.TPRandom(c.seed), c.mode);
  return w === c.wind || `${w}/${c.wind}`;
});

let fail = 0, total = 0, okAll = 0;
for (const [name, ok, n, bad] of results) {
  total += n; okAll += ok; if (ok !== n) fail++;
  console.log(`${ok === n ? 'OK ' : 'FAIL'} ${name}: ${ok}/${n}`);
  for (const b of bad.slice(0, 5)) console.log('      ' + b);
}
console.log(`ИТОГО: ${okAll}/${total}`);
process.exit(fail ? 1 : 0);
