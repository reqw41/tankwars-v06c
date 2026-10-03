// Сравнение подпрограмм 8080 с эталоном web/tankwars.js (PROFILE_V06C).
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import * as TW from '../../web/tankwars.js';
import { createMachine, loadRom, poke, runUntil, parseSym, dumpMem } from '../tools/run.mjs';
import { planesToScreen, firstPixelDiff, screenToPlanes } from '../tools/screen.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const ROM = path.join(ROOT, 'v06c/build/tw.rom');
const SYM = path.join(ROOT, 'v06c/build/tw.sym');
const PARAM = 0x0080, LIST = 0x2000, RESULT = 0x7000;
const MODE_RANDOM = 1, MODE_PIXELS = 2, MODE_LINES = 3, MODE_BENCH = 4;
const MODE_ERASELN = 5, MODE_FRAME = 6, MODE_TANK = 7, MODE_CROSS = 8, MODE_RING = 9, MODE_CLEAR = 10, MODE_BARREL = 11;
const KIND_RANDOM = 1, KIND_PIXEL = 2, KIND_LINE = 3;
const KIND_FRAME = 4, KIND_TANK = 5, KIND_CROSS = 6, KIND_RING = 7, KIND_CLEAR = 8;

TW.setProfile(TW.PROFILE_V06C);
const P = TW.PROFILE_V06C;
TW.init({
  barrel: JSON.parse(fs.readFileSync(path.join(ROOT, 'web/data/barrel.json'), 'utf8')),
  trig: JSON.parse(fs.readFileSync(path.join(ROOT, 'web/data/trig.json'), 'utf8')),
});

function u16(n) { return [(n) & 255, (n >> 8) & 255]; }
function u32(n) {
  n >>>= 0;
  return [n & 255, (n >> 8) & 255, (n >> 16) & 255, (n >>> 24) & 255];
}
function readU16(mem, a) { return mem[a] | (mem[a + 1] << 8); }
function readU32(mem, a) { return (mem[a] | (mem[a + 1] << 8) | (mem[a + 2] << 16) | (mem[a + 3] << 24)) >>> 0; }

class LCG {
  constructor(seed) { this.s = seed >>> 0; }
  next() { this.s = (Math.imul(this.s, 1664525) + 1013904223) >>> 0; return this.s; }
  below(n) { return this.next() % n; }
}

let machine;
function boot() {
  if (!machine) machine = createMachine();
  loadRom(machine, fs.readFileSync(ROM));
}

function hdr(mode, extra = []) {
  const b = new Uint8Array(16);
  b[0] = mode;
  b.set(extra, 1);
  return b;
}

function runMode(mode, extra, listBytes) {
  boot();
  poke(machine, PARAM, hdr(mode, extra));
  if (listBytes && listBytes.length) poke(machine, LIST, listBytes);
  return runUntil(machine, { haltPc: null, maxInsns: 50_000_000 });
}

function fail(msg) {
  console.error('FAIL', msg);
  process.exit(1);
}

function testRandom() {
  const seeds = [0, 1, 0x08088405, 0x12345678, 0xDEADBEEF, 7, 42, 0xFFFFFFFF, 0x80000000, 99991];
  const gen = new LCG(0xC0FFEE);
  let cases = 0, calls = 0;
  for (const seed of seeds) {
    const ns = new Uint8Array(1000 * 2);
    const nList = [];
    for (let i = 0; i < 1000; i++) {
      const k = gen.below(12);
      const n = [0, 1, 2, 7, 10, 16, 100, 256, 1000, 32767, 65535, 3][k];
      nList.push(n);
      ns[i * 2] = n & 255;
      ns[i * 2 + 1] = (n >> 8) & 255;
    }
    const extra = new Uint8Array(15);
    extra[1] = 1000 & 255; extra[2] = 1000 >> 8;
    extra.set(u32(seed), 3);
    const r = runMode(MODE_RANDOM, extra, ns);
    const rng = new TW.TPRandom(seed);
    for (let i = 0; i < 1000; i++) {
      const got = readU16(r.mem, RESULT + i * 2);
      const exp = rng.word(nList[i]);
      if (got !== exp) {
        fail(`random seed=0x${seed.toString(16)} call#${i} n=${nList[i]} emu=${got} oracle=${exp}`);
      }
      calls++;
    }
    const seedGot = readU32(r.mem, PARAM + 4);
    if (seedGot !== rng.seed) {
      fail(`random seed=0x${seed.toString(16)} итоговый seed emu=0x${seedGot.toString(16)} oracle=0x${rng.seed.toString(16)}`);
    }
    cases++;
  }
  console.log(`OK  Random: ${cases} начальных × 1000 вызовов (${calls}), seed совпал`);
}

function testPixels() {
  const gen = new LCG(2026);
  const pts = [];
  const add = (x, y, c) => pts.push([x, y, c]);
  for (const [x, y] of [[0, 0], [255, 0], [0, 255], [255, 255], [0, 128], [255, 128], [128, 0], [128, 255], [7, 0], [8, 1], [1, 24], [2, 26], [253, 253], [252, 27], [3, 27]]) {
    add(x, y, 7);
  }
  add(40, 50, 3);
  while (pts.length < 500) add(gen.below(256), gen.below(256), gen.below(8));
  const n = pts.length;
  const list = new Uint8Array(n * 3);
  const v = new Uint8Array(P.W * P.H);
  for (let i = 0; i < n; i++) {
    const [x, y, c] = pts[i];
    list[i * 3] = x; list[i * 3 + 1] = y; list[i * 3 + 2] = c;
    v[y * 256 + x] = c;
  }
  const extra = new Uint8Array(15);
  extra[1] = n & 255; extra[2] = n >> 8;
  const r = runMode(MODE_PIXELS, extra, list);
  const got = planesToScreen(r.mem);
  const d = firstPixelDiff(got, v);
  if (d) fail(`точка экран: первый пиксель (${d.x},${d.y}) emu=${d.got} oracle=${d.exp}`);
  for (let i = 0; i < n; i++) {
    const [x, y] = pts[i];
    const back = r.mem[RESULT + i];
    const exp = v[y * 256 + x];
    if (back !== exp) fail(`точка getpixel #${i} (${x},${y}) emu=${back} oracle=${exp}`);
  }
  console.log(`OK  точка: ${n} put+get, экран 256×256 совпал`);
}

function testLines() {
  const gen = new LCG(0xBEEF);
  const segs = [];
  const add = (x1, y1, x2, y2, c) => segs.push([x1, y1, x2, y2, c]);
  add(10, 30, 10, 80, 1);           // вертикаль вниз
  add(10, 80, 10, 30, 1);           // вертикаль вверх
  add(20, 40, 90, 40, 2);           // горизонталь вправо
  add(90, 40, 20, 40, 2);           // горизонталь влево
  add(50, 50, 50, 50, 3);           // длина 1
  add(40, 40, 80, 80, 4);           // SE
  add(80, 40, 40, 80, 5);           // SW
  add(40, 80, 80, 40, 6);           // NE
  add(80, 80, 40, 40, 7);           // NW
  add(5, 40, 204, 40, 1);           // 200 точек, замер
  add(200, 60, 40, 70, 4);          // справа налево
  add(80, 200, 90, 40, 5);          // снизу вверх
  add(3, 27, 252, 252, 6);
  add(252, 27, 3, 252, 7);
  add(100, 100, 100, 101, 1);
  while (segs.length < 300) {
    const x1 = 3 + gen.below(250), y1 = 27 + gen.below(226);
    const x2 = 3 + gen.below(250), y2 = 27 + gen.below(226);
    add(x1, y1, x2, y2, gen.below(8));
  }
  const n = segs.length;
  const list = new Uint8Array(n * 5);
  const v = new Uint8Array(P.W * P.H);
  for (let i = 0; i < n; i++) {
    const [x1, y1, x2, y2, c] = segs[i];
    list[i * 5] = x1; list[i * 5 + 1] = y1; list[i * 5 + 2] = x2; list[i * 5 + 3] = y2; list[i * 5 + 4] = c;
    TW.line(v, x1, y1, x2, y2, c);
  }
  const extra = new Uint8Array(15);
  extra[1] = n & 255; extra[2] = n >> 8;
  const r = runMode(MODE_LINES, extra, list);
  const got = planesToScreen(r.mem);
  const d = firstPixelDiff(got, v);
  if (d) {
    const acc = new Uint8Array(P.W * P.H);
    let which = 0;
    for (let i = 0; i < n; i++) {
      TW.line(acc, ...segs[i]);
      if (acc[d.i] === v[d.i]) which = i;
    }
    const [x1, y1, x2, y2, c] = segs[which];
    fail(`линия случай #${which} (${x1},${y1})-(${x2},${y2}) c=${c}; первый пиксель (${d.x},${d.y}) emu=${d.got} oracle=${d.exp}`);
  }
  console.log(`OK  линия: ${n} отрезков, экран 256×256 совпал`);
}

function testEraseLines() {
  const gen = new LCG(0xE1);
  const segs = [];
  const add = (x1, y1, x2, y2) => segs.push([x1, y1, x2, y2, 0]);
  add(10, 30, 10, 80);
  add(20, 40, 90, 40);
  add(50, 50, 50, 50);
  add(0, 0, 255, 0);
  while (segs.length < 200) {
    add(gen.below(256), gen.below(256), gen.below(256), gen.below(256));
  }
  const n = segs.length;
  const list = new Uint8Array(n * 5);
  const v = new Uint8Array(P.W * P.H).fill(1);
  const bg = new Uint8Array(P.W * P.H);
  for (let i = 0; i < n; i++) {
    const [x1, y1, x2, y2, c] = segs[i];
    list[i * 5] = x1; list[i * 5 + 1] = y1; list[i * 5 + 2] = x2; list[i * 5 + 3] = y2; list[i * 5 + 4] = c;
    TW.line(v, x1, y1, x2, y2, 0, bg);
  }
  const extra = new Uint8Array(15);
  extra[1] = n & 255; extra[2] = n >> 8;
  const r = runMode(MODE_ERASELN, extra, list);
  const got = planesToScreen(r.mem);
  const d = firstPixelDiff(got, v);
  if (d) fail(`линия стирания # пиксель (${d.x},${d.y}) emu=${d.got} oracle=${d.exp}`);
  console.log(`OK  линия стирания: ${n} отрезков на фоне 1, экран совпал`);
}

function testFrame() {
  const cases = [0, 1, 0, 1, 0];
  while (cases.length < 200) cases.push(cases.length & 1);
  const n = cases.length;
  const list = Uint8Array.from(cases);
  const v = new Uint8Array(P.W * P.H);
  for (const reb of cases) TW.drawFrame(v, !!reb);
  const extra = new Uint8Array(15);
  extra[1] = n & 255; extra[2] = n >> 8;
  const r = runMode(MODE_FRAME, extra, list);
  const got = planesToScreen(r.mem);
  const d = firstPixelDiff(got, v);
  if (d) fail(`рамка пиксель (${d.x},${d.y}) emu=${d.got} oracle=${d.exp}`);
  console.log(`OK  рамка: ${n} (rebound 0/1), экран совпал`);
}

function testTank() {
  const gen = new LCG(0x7A11);
  const ops = [];
  const add = (x, y, c, er) => ops.push([x, y, c, er]);
  add(3, 27, 4, 0);
  add(252, 252, 5, 0);
  add(128, 128, 6, 0);
  add(4, 40, 7, 0);
  add(4, 40, 7, 1);
  add(0, 0, 4, 0);
  add(255, 255, 5, 0);
  while (ops.length < 200) add(gen.below(256), 27 + gen.below(220), 4 + gen.below(4), gen.below(2));
  const n = ops.length;
  const list = new Uint8Array(n * 4);
  const v = new Uint8Array(P.W * P.H);
  const bg = new Uint8Array(P.W * P.H);
  for (let i = 0; i < n; i++) {
    const [x, y, c, er] = ops[i];
    list[i * 4] = x; list[i * 4 + 1] = y; list[i * 4 + 2] = c; list[i * 4 + 3] = er;
    if (er) TW.eraseTank(v, bg, x, y);
    else TW.drawTank(v, x, y, c);
  }
  const extra = new Uint8Array(15);
  extra[1] = n & 255; extra[2] = n >> 8;
  const r = runMode(MODE_TANK, extra, list);
  const got = planesToScreen(r.mem);
  const d = firstPixelDiff(got, v);
  if (d) fail(`танк пиксель (${d.x},${d.y}) emu=${d.got} oracle=${d.exp}`);
  console.log(`OK  корпус танка: ${n} draw/erase, экран совпал`);
}

function testCross() {
  const gen = new LCG(0xC205);
  const ops = [];
  const add = (x, y, c) => ops.push([x, y, c]);
  add(128, 128, 3);
  add(3, 27, 3);
  add(252, 252, 0);
  add(0, 0, 3);
  add(255, 255, 0);
  while (ops.length < 200) add(gen.below(256), gen.below(256), gen.below(2) ? 3 : 0);
  const n = ops.length;
  const list = new Uint8Array(n * 3);
  const v = new Uint8Array(P.W * P.H);
  const bg = new Uint8Array(P.W * P.H);
  for (let i = 0; i < n; i++) {
    const [x, y, c] = ops[i];
    list[i * 3] = x; list[i * 3 + 1] = y; list[i * 3 + 2] = c;
    if (c) TW.cross(v, null, x, y, 3);
    else TW.cross(v, bg, x, y);
  }
  const extra = new Uint8Array(15);
  extra[1] = n & 255; extra[2] = n >> 8;
  const r = runMode(MODE_CROSS, extra, list);
  const got = planesToScreen(r.mem);
  const d = firstPixelDiff(got, v);
  if (d) fail(`мяч-крестик (${d.x},${d.y}) emu=${d.got} oracle=${d.exp}`);
  console.log(`OK  мяч-крестик: ${n}, экран совпал`);
}

function i16bytes(n) { n = (n << 16) >> 16; return [n & 255, (n >> 8) & 255]; }

function testRing() {
  const gen = new LCG(0xE11);
  const ops = [];
  const add = (cx, cy, r, c) => ops.push([cx, cy, r, c]);
  add(125, 113, 0, 3);
  add(125, 113, 1, 3);
  add(0, 0, 10, 3);
  add(249, 225, 30, 3);
  add(-5, 100, 20, 3);
  add(125, 113, 61, 3);
  add(1, 1, 5, 0);
  while (ops.length < 200) add(gen.below(280) - 20, gen.below(250) - 10, gen.below(62), gen.below(2) ? 3 : 0);
  const n = ops.length;
  const list = new Uint8Array(n * 6);
  const v = new Uint8Array(P.W * P.H);
  const bg = new Uint8Array(P.W * P.H);
  for (let i = 0; i < n; i++) {
    const [cx, cy, r, c] = ops[i];
    const xb = i16bytes(cx), yb = i16bytes(cy);
    list[i * 6] = xb[0]; list[i * 6 + 1] = xb[1];
    list[i * 6 + 2] = yb[0]; list[i * 6 + 3] = yb[1];
    list[i * 6 + 4] = r; list[i * 6 + 5] = c;
    if (c) TW.ring(v, cx, cy, r, c);
    else TW.ringRestore(v, bg, cx, cy, r);
  }
  const extra = new Uint8Array(15);
  extra[1] = n & 255; extra[2] = n >> 8;
  const r = runMode(MODE_RING, extra, list);
  const got = planesToScreen(r.mem);
  const d = firstPixelDiff(got, v);
  if (d) fail(`кольцо пиксель (${d.x},${d.y}) emu=${d.got} oracle=${d.exp}`);
  console.log(`OK  кольцо эллипса: ${n}, экран совпал`);
}

function testClear() {
  const gen = new LCG(99);
  const v0 = new Uint8Array(P.W * P.H);
  for (let i = 0; i < 2000; i++) v0[gen.below(65536)] = 1 + gen.below(7);
  const planes = screenToPlanes(v0);
  boot();
  poke(machine, 0xA000, planes.subarray(0xA000));
  poke(machine, PARAM, hdr(MODE_CLEAR, [0]));
  const r = runUntil(machine, { haltPc: null, maxInsns: 20_000_000 });
  const got = planesToScreen(r.mem);
  const z = new Uint8Array(65536);
  const d = firstPixelDiff(got, z);
  if (d) fail(`очистка (${d.x},${d.y}) emu=${d.got}`);
  console.log('OK  очистка всего экрана');

  boot();
  poke(machine, 0xA000, planes.subarray(0xA000));
  poke(machine, PARAM, hdr(MODE_CLEAR, [1]));
  const r2 = runUntil(machine, { haltPc: null, maxInsns: 20_000_000 });
  const got2 = planesToScreen(r2.mem);
  const exp = v0.slice();
  for (let i = 0; i < 24 * 256; i++) exp[i] = 0;
  const d2 = firstPixelDiff(got2, exp);
  if (d2) fail(`очистка панели (${d2.x},${d2.y}) emu=${d2.got} oracle=${d2.exp}`);
  console.log('OK  очистка строк 0..23');
}

function testBarrel() {
  const gen = new LCG(0xBA11);
  const ops = [];
  const add = (x, y, idx, angle, facing, alive, er) => ops.push({ x, y, idx, angle, facing, alive, er });
  add(40, 80, 1, 0, 1, 1, 0);
  add(80, 80, 2, 45, 1, 1, 0);
  add(120, 80, 3, 90, 1, 1, 0);
  add(200, 80, 4, 0, -1, 1, 0);
  add(40, 120, 1, 45, -1, 1, 0);
  add(80, 120, 2, 90, -1, 1, 0);
  add(3, 40, 1, 75, 1, 1, 0);
  add(252, 40, 4, 75, -1, 1, 0);
  add(100, 100, 1, 45, 1, 0, 0);
  add(60, 90, 2, 45, 1, 1, 0);
  add(60, 90, 2, 45, 1, 1, 1);
  while (ops.length < 200) {
    add(10 + gen.below(230), 40 + gen.below(180), 1 + gen.below(4), gen.below(91), gen.below(2) ? 1 : -1, gen.below(10) ? 1 : 0, gen.below(2));
  }
  const n = ops.length;
  const list = new Uint8Array(n * 8);
  const v = new Uint8Array(P.W * P.H);
  const bg = new Uint8Array(P.W * P.H);
  for (let i = 0; i < n; i++) {
    const t = ops[i];
    list[i * 8] = t.x; list[i * 8 + 1] = t.y; list[i * 8 + 2] = t.idx;
    list[i * 8 + 3] = t.angle & 255; list[i * 8 + 4] = (t.angle >> 8) & 255;
    list[i * 8 + 5] = t.facing & 255; list[i * 8 + 6] = t.alive; list[i * 8 + 7] = t.er;
    const rec = { alive: !!t.alive, x: t.x, y: t.y, idx: t.idx, angle: t.angle, facing: t.facing };
    if (t.er) TW.eraseTankBarrel(v, bg, rec);
    else TW.drawTankBarrel(v, rec);
  }
  const extra = new Uint8Array(15);
  extra[1] = n & 255; extra[2] = n >> 8;
  const r = runMode(MODE_BARREL, extra, list);
  const got = planesToScreen(r.mem);
  const d = firstPixelDiff(got, v);
  if (d) fail(`ствол (${d.x},${d.y}) emu=${d.got} oracle=${d.exp}`);
  console.log(`OK  танк со стволом: ${n}, экран совпал`);
}

function pokeBench(kind, fields) {
  boot();
  const b = new Uint8Array(16);
  b[0] = MODE_BENCH;
  b[1] = kind;
  if (fields.n != null) { b[8] = fields.n & 255; b[9] = (fields.n >> 8) & 255; }
  if (fields.seed != null) { const s = u32(fields.seed); b[4] = s[0]; b[5] = s[1]; b[6] = s[2]; b[7] = s[3]; }
  if (fields.x != null) b[10] = fields.x;
  if (fields.y != null) b[11] = fields.y;
  if (fields.x2 != null) b[12] = fields.x2;
  if (fields.y2 != null) b[13] = fields.y2;
  if (fields.c != null) b[14] = fields.c;
  poke(machine, PARAM, b);
}

function bench(name, entry, ret, kind, fields) {
  pokeBench(kind, fields);
  const r = runUntil(machine, { haltPc: ret, countFromPc: entry, maxInsns: 20_000_000 });
  console.log(`ТАКТЫ  ${name}: cpu_cycles=${r.bodyCpu} (vcycles=${r.bodyV})`);
  return { cpu: r.bodyCpu, v: r.bodyV };
}

function sizes(L) {
  const rows = [
    ['Random', L.random, L.random_end],
    ['точка (put+get+addr)', L.putpixel, L.pixel_end],
    ['putpixel', L.putpixel, L.putpixel_end],
    ['getpixel', L.getpixel, L.getpixel_end],
    ['линия', L.line, L.line_end],
    ['рамка', L.draw_frame, L.draw_frame_end],
    ['танк', L.draw_tank, L.draw_tank_end],
    ['заливка', L.fill_screen, L.fill_screen_end],
    ['кольцо', L.ring, L.ring_end],
  ];
  for (const [name, a, b] of rows) {
    if (a == null || b == null) fail(`нет меток размера для ${name}`);
    console.log(`БАЙТЫ  ${name}: ${b - a} (0x${a.toString(16)}..0x${(b - 1).toString(16)})`);
  }
  return {
    random: L.random_end - L.random,
    pixel: L.pixel_end - L.putpixel,
    line: L.line_end - L.line,
  };
}

if (!fs.existsSync(ROM)) fail(`нет ${ROM} — сначала sh v06c/build.sh`);
const L = parseSym(SYM);
boot();
testRandom();
testPixels();
testLines();
testEraseLines();
testFrame();
testTank();
testCross();
testRing();
testClear();
testBarrel();
console.log('--- замер ---');
const sz = sizes(L);
const tRandom = bench('Random(n=100)', L.random, L.bench_random_ret, KIND_RANDOM, { seed: 1, n: 100 });
const tPix = bench('точка putpixel(40,50,3)', L.putpixel, L.bench_pixel_ret, KIND_PIXEL, { x: 40, y: 50, c: 3 });
const tL10 = bench('линия 10 точек (10,20)-(19,20)', L.line, L.bench_line_ret, KIND_LINE, { x: 10, y: 20, x2: 19, y2: 20, c: 2 });
pokeBench(KIND_LINE, { x: 5, y: 40, x2: 204, y2: 40, c: 1 });
const rL200 = runUntil(machine, { haltPc: L.bench_line_ret, countFromPc: L.line, maxInsns: 5_000_000 });
console.log(`ТАКТЫ  линия 200 точек (5,40)-(204,40): cpu_cycles=${rL200.bodyCpu} (vcycles=${rL200.bodyV})`);
const tFr = bench('рамка rebound=0', L.draw_frame, L.bench_frame_ret, KIND_FRAME, { c: 0 });
const tTk = bench('танк (128,128,4)', L.draw_tank, L.bench_tank_ret, KIND_TANK, { x: 128, y: 128, c: 4 });
const tCr = bench('крестик (100,100,3)', L.draw_cross, L.bench_cross_ret, KIND_CROSS, { x: 100, y: 100, c: 3 });
const tRg = bench('кольцо r=30', L.ring, L.bench_ring_ret, KIND_RING, { x: 125, y: 113, x2: 30, c: 3 });
const tCl = bench('очистка экрана', L.clear_screen, L.bench_clear_ret, KIND_CLEAR, {});
console.log('--- таблица ---');
console.log(`подпрограмма\tбайт\tтакты_cpu\tvcycles`);
const row = (name, b, t) => console.log(`${name}\t${b}\t${t.cpu}\t${t.v}`);
row('Random', sz.random, tRandom);
row('точка', sz.pixel, tPix);
row('линия 10', sz.line, tL10);
console.log(`линия 200\t${sz.line}\t${rL200.bodyCpu}\t${rL200.bodyV}`);
row('рамка', L.draw_frame_end - L.draw_frame, tFr);
row('танк', L.draw_tank_end - L.draw_tank, tTk);
row('крестик', L.draw_cross_end - L.draw_cross, tCr);
row('кольцо r=30', L.ring_end - L.ring, tRg);
row('очистка', L.fill_screen_end - L.fill_screen, tCl);
console.log(`линия 200 на точку\t\t${(rL200.bodyV / 200).toFixed(1)} vcycles`);
console.log('OK  сверка с эталоном PROFILE_V06C');
