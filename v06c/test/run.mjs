// Сравнение подпрограмм 8080 с эталоном web/tankwars.js (PROFILE_V06C).
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import * as TW from '../../web/tankwars.js';
import { createMachine, loadRom, poke, runUntil, parseSym } from '../tools/run.mjs';
import { planesToScreen, firstPixelDiff } from '../tools/screen.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const ROM = path.join(ROOT, 'v06c/build/tw.rom');
const SYM = path.join(ROOT, 'v06c/build/tw.sym');
const PARAM = 0x0080, LIST = 0x2000, RESULT = 0x7000;
const MODE_RANDOM = 1, MODE_PIXELS = 2, MODE_LINES = 3, MODE_BENCH = 4;
const KIND_RANDOM = 1, KIND_PIXEL = 2, KIND_LINE = 3;

TW.setProfile(TW.PROFILE_V06C);
const P = TW.PROFILE_V06C;

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
  const r = runUntil(machine, { haltPc: ret, countFromPc: entry, maxInsns: 5_000_000 });
  console.log(`ТАКТЫ  ${name}: cpu_cycles=${r.bodyCpu} (vcycles=${r.bodyV})`);
  return r.bodyCpu;
}

function sizes(L) {
  const rows = [
    ['Random', L.random, L.random_end],
    ['точка (put+get+addr)', L.putpixel, L.pixel_end],
    ['putpixel', L.putpixel, L.putpixel_end],
    ['getpixel', L.getpixel, L.getpixel_end],
    ['линия', L.line, L.line_end],
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
console.log('--- замер ---');
const sz = sizes(L);
const tRandom = bench('Random(n=100)', L.random, L.bench_random_ret, KIND_RANDOM, { seed: 1, n: 100 });
const tPix = bench('точка putpixel(40,50,3)', L.putpixel, L.bench_pixel_ret, KIND_PIXEL, { x: 40, y: 50, c: 3 });
const tL10 = bench('линия 10 точек (10,20)-(19,20)', L.line, L.bench_line_ret, KIND_LINE, { x: 10, y: 20, x2: 19, y2: 20, c: 2 });
pokeBench(KIND_LINE, { x: 5, y: 40, x2: 204, y2: 40, c: 1 });
const tL200 = runUntil(machine, { haltPc: L.bench_line_ret, countFromPc: L.line, maxInsns: 5_000_000 }).bodyCpu;
console.log(`ТАКТЫ  линия 200 точек (5,40)-(204,40): cpu_cycles=${tL200}`);
console.log('--- таблица ---');
console.log(`подпрограмма\tбайт\tтакты`);
console.log(`Random\t${sz.random}\t${tRandom}`);
console.log(`точка\t${sz.pixel}\t${tPix}`);
console.log(`линия 10\t${sz.line}\t${tL10}`);
console.log(`линия 200\t${sz.line}\t${tL200}`);
console.log('OK  все случаи трёх подпрограмм совпали с эталоном');
