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

// ================= T05 =================
const hexU8 = (h) => new Uint8Array(Buffer.from(h, 'hex'));
const inField = (k) => { const y = (k / 320) | 0, x = k % 320; return y >= 28 && y <= 192 && x >= 8 && x <= 312; };
const fdiff = (a, b) => { let n = 0; for (let k = 0; k < 64000; k++) if (a[k] !== b[k] && inField(k)) n++; return n; };

// --- гибель танка: 7 вариантов ---
for (const dir of ['death', 'death_b']) {
  section(`гибель ${dir} (T05)`, json(FX(`t05/${dir}/index.json`)), (c) => {
    const d = `t05/${dir}/`;
    const v = z(FX(d + c.name + '.pre.z')), bg = z(FX(d + c.name + '.bg.z')), post = z(FX(d + c.name + '.post.z'));
    const ps = c.pre.players.map((h, i) => TW.playerFromRec(hexU8(h), i + 1));
    const rng = new TW.TPRandom(c.pre.seed);
    TW.death(c.variant, v, bg, ps, c.victim, rng, !!c.sound, c.wind || 0, !!c.xkill);
    const want = c.post.players.map((h, i) => TW.playerFromRec(hexU8(h), i + 1));
    const key = (p) => [p.men, p.shield, p.score].join();
    if (!same(ps.map(key), want.map(key))) return 'игроки';
    if (rng.seed !== c.post.seed) return 'RandSeed';
    return vdiff(v, post) === 0 || 'vram ' + vdiff(v, post);
  });
}

// --- ход целиком ---
for (const dir of ['turns_ai2', 'turns_ai6']) {
  section(`ход ${dir} (T05)`, json(FX(`t05/${dir}/index.json`)), (c) => {
    const d = `t05/${dir}/`;
    const v = z(FX(d + c.name + '.pre.z')), bg = z(FX(d + c.name + '.bg.z')), post = z(FX(d + c.name + '.post.z')), bgpost = z(FX(d + c.name + '.bgpost.z'));
    const f = c.pre.flags;
    const fl = { rebound: !!f.rebound, crumble: f.crumble, fall: !!f.fall, xkill: !!f.xkill, sound: !!f.sound, wind: f.wind, ballVisible: !f.ball_inv, trail: !!f.trail };
    const ps = c.pre.players.map((h, i) => TW.playerFromRec(hexU8(h), i + 1));
    const rng = new TW.TPRandom(c.pre.seed);
    TW.turn(v, bg, ps, f.shooter, rng, fl);
    const want = c.post.players.map((h, i) => TW.playerFromRec(hexU8(h), i + 1));
    const key = (p) => [p.x, p.y, p.men, p.alive, p.shield, p.score, p.ammo.join('.')].join();
    if (!same(ps.map(key), want.map(key))) return 'игроки';
    if (rng.seed !== c.post.seed) return 'RandSeed';
    if (vdiff(bg, bgpost)) return 'фон ' + vdiff(bg, bgpost);
    return fdiff(v, post) === 0 || 'vram ' + fdiff(v, post);
  });
}

// --- начало раунда: стены, фон, рельеф, танки, первый игрок, ветер ---
section('начало раунда (T05)', json(FX('t05/rstart/index.json')), (c) => {
  const ps = c.pre.players.map((h, i) => TW.playerFromRec(hexU8(h), i + 1));
  const rng = new TW.TPRandom(c.pre.seed), cfg = c.pre.cfg;
  const r = TW.roundStart(rng, ps, cfg.walls_cfg, cfg.bg_cfg, cfg.wind_mode);
  const post = z(FX(`t05/rstart/${c.name}.post.z`)), bgo = z(FX(`t05/rstart/${c.name}.bg.z`));
  if (vdiff(r.bg, bgo)) return 'фон ' + vdiff(r.bg, bgo);
  if (fdiff(r.v, post)) return 'vram ' + fdiff(r.v, post);
  const want = c.post.players.map((h, i) => TW.playerFromRec(hexU8(h), i + 1));
  const key = (p) => [p.x, p.y, p.angle, p.power, p.facing, p.men, p.alive].join();
  if (!same(ps.map(key), want.map(key))) return 'игроки';
  return (rng.seed === c.post.seed && r.wind === c.post.wind && +r.rebound === c.post.rebound && r.first === c.post.first_raw) || 'seed/ветер/стены/первый';
});

// --- ИИ: план и цикл кодов ---
{
  const cases = [];
  for (const d of ['birdy', 'm1', 'm2', 'm3', 'm4', 'm5', 'm6r']) for (const c of json(FX(`t05/ai/${d}/index.json`))) cases.push({ ...c, dir: d, label: `${d}-${c.name}` });
  const load = (c) => {
    const ps = c.recs.slice(1).map((h, i) => TW.playerFromRec(hexU8(h), i + 1, 0x0e));
    return { ps, p: ps[c.player - 1], bg: z(FX(`t05/ai/${c.dir}/${c.name}.bg.z`)) };
  };
  section('ИИ: план (T05)', cases, (c) => {
    const { ps, p, bg } = load(c);
    const h = TW.histFromBytes(hexU8(c.hist)), h1 = TW.histFromBytes(hexU8(c.hist1));
    if (h.planned) return true;
    const rng = new TW.TPRandom(c.seed0);
    TW.plan(z(FX(`t05/ai/${c.dir}/${c.name}.v0.z`)), bg, ps, p, h, rng, !!c.flags.rebound, p.name);
    const code = TW.chooseCode(p, h);
    const f = (x) => [x.power, x.angle, x.facing, x.weapon, x.target, x.n].join();
    if (f(h) !== f(h1)) return `план ${f(h)} / ${f(h1)}`;
    if (rng.seed !== c.seeds[0]) return 'RandSeed';
    return code === c.codes[0] || `код ${code}/${c.codes[0]}`;
  });
  section('ИИ: цикл кодов (T05)', cases, (c) => {
    const { ps, p, bg } = load(c);
    p.hist = TW.histFromBytes(hexU8(c.hist1)); p.hist.planned = 1;
    const codes = TW.computerTurn(z(FX(`t05/ai/${c.dir}/${c.name}.v1.z`)), bg, ps, p, new TW.TPRandom(0), !!c.flags.rebound);
    const end = TW.playerFromRec(hexU8(c.rec_end), c.player, 0x0e);
    if (!same(codes, c.codes)) return `коды ${codes.length}/${c.codes.length}`;
    return [p.angle, p.power, p.facing, p.weapon].join() === [end.angle, end.power, end.facing, end.weapon].join() || 'запись';
  });
}

// --- матч: перетасовка, результаты, магазин ---
for (const m of ['a', 'b', 'c']) {
  const ev = json(FX(`t05/match/${m}.json`));
  const pairs = []; for (let i = 0; i + 1 < ev.length; i++) pairs.push({ a: ev[i], b: ev[i + 1], label: `${m}-${i}-${ev[i].event}` });
  const mk = (e) => e.recs.slice(1).map((h, i) => { const p = TW.playerFromRec(hexU8(h), i + 1, 0x0e); p.ctrl = e.ctrl[i + 1]; p.strategy = e.strategy[i + 1]; return p; });
  const key = (p) => [p.name, p.score, p.spent, p.wins, p.men, p.ammo.join('.'), p.herb, p.vick, p.shield, p.damp, p.colors.join('.'), p.ctrl, p.strategy].join();
  section(`матч ${m} (T05)`, pairs.filter((x) => x.a.event !== 'round'), ({ a, b }) => {
    const ps = mk(a), want = mk(b), rng = new TW.TPRandom(a.seed);
    if (a.event === 'shuffle') TW.shufflePlayers(rng, ps);
    else if (a.event === 'results') TW.results(rng, ps, true);
    else if (a.event === 'shop') for (const p of ps) if (p.ctrl === 3 && a.ai_buys) TW.aiShop(p, p.strategy);
    if (!same(ps.map(key), want.map(key))) return 'игроки';
    return rng.seed === b.seed || 'RandSeed';
  });
}

// --- осыпание по столбцам (вариант для порта, без списка) = осыпание оригинала ---
{
  const cases = [];
  for (const c of json(FX('t03/crumble/index.json'))) cases.push({ label: 'crumble-' + c.name, v: FX(`t03/crumble/${c.name}.pre.z`), bg: FX(`t03/crumble/${c.name}.bg.z`) });
  for (const d of ['turns_ai2', 'turns_ai6']) for (const c of json(FX(`t05/${d}/index.json`))) cases.push({ label: `${d}-${c.name}`, v: FX(`t05/${d}/${c.name}.post.z`), bg: FX(`t05/${d}/${c.name}.bgpost.z`) });
  for (const d of ['explosion', 'explosion_direct']) for (const c of json(FX(`t03/${d}/index.json`))) cases.push({ label: `${d}-${c.name}`, v: FX(`t03/${d}/${c.name}.post.z`), bg: FX(`t03/${d}/${c.name}.bg.z`) });
  section('осыпание по столбцам = осыпание со списком', cases, (c) => {
    const a = z(c.v), b = z(c.v), bg = z(c.bg);
    TW.crumble(a, bg); TW.crumbleColumns(b, bg);
    return vdiff(a, b) === 0 || 'различий ' + vdiff(a, b);
  });
}

let fail = 0, total = 0, okAll = 0;
for (const [name, ok, n, bad] of results) {
  total += n; okAll += ok; if (ok !== n) fail++;
  console.log(`${ok === n ? 'OK ' : 'FAIL'} ${name}: ${ok}/${n}`);
  for (const b of bad.slice(0, 5)) console.log('      ' + b);
}
console.log(`ИТОГО: ${okAll}/${total}`);
process.exit(fail ? 1 : 0);
