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
const PARAM = 0x0080, LIST = 0x4000, RESULT = 0x7000;
const MODE_RANDOM = 1, MODE_PIXELS = 2, MODE_LINES = 3, MODE_BENCH = 4;
const MODE_ERASELN = 5, MODE_FRAME = 6, MODE_TANK = 7, MODE_CROSS = 8, MODE_RING = 9;
const MODE_CLEAR = 10, MODE_BARREL = 11, MODE_TEXT = 12, MODE_CRUMBLE = 13, MODE_REPLACE = 14, MODE_PAL = 15;
const MODE_UI = 16, MODE_DISC = 17, KIND_DISC = 13;
const KIND_RANDOM = 1, KIND_PIXEL = 2, KIND_LINE = 3;
const KIND_FRAME = 4, KIND_TANK = 5, KIND_CROSS = 6, KIND_RING = 7, KIND_CLEAR = 8, KIND_CHAR = 10, KIND_PANEL = 11, KIND_CRUMBLE = 12;

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

// Кольцо нулём по точкам ellipsePoints эталона — только для подготовки экранов (в профиле Вектора ring() запрещён).
function ringZero(v, cx, cy, r) {
  const vp = TW.VIEWPORT;
  for (const [x, y] of TW.ellipsePoints(cx + vp[0], cy + vp[1], r, r)) if (vp[0] <= x && x <= vp[2] && vp[1] <= y && y <= vp[3]) v[y * 256 + x] = 0;
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

// Закрашенный круг: disc() эталона — огонь и воронка взрыва, шар грязи (три центра), круги гибели (два центра).
function testDisc() {
  const gen = new LCG(0xD15C);
  const RAD = [2, 4, 8, 10, 12, 15, 16, 20, 30, 60], ops = [];
  const add = (cx, cy, r, c, el = 1, er = 1) => ops.push([cx, cy, r, c, el, er]);   // cx, cy — в координатах поля, как у disc()
  for (const r of RAD) { add(125, 113, r, 3); add(125, 113, r, 0); add(60, 60, r, 1, 0, 1); }
  add(0, 0, 60, 3); add(249, 225, 60, 1); add(0, 225, 30, 3); add(249, 0, 30, 1); add(1, 100, 15, 3); add(248, 100, 10, 1); add(100, 1, 2, 3);
  add(-3, 100, 20, 3, 0, 1); add(260, 100, 20, 1, 0, 1); add(100, -20, 30, 3, 0, 1); add(100, 250, 30, 1, 0, 1); add(-40, -40, 60, 3); add(300, 300, 60, 3); add(-70, 50, 60, 3);
  while (ops.length < 400) { const two = gen.below(2); add(gen.below(290) - 20, gen.below(266) - 20, RAD[gen.below(10)], [3, 1, 0, 0][gen.below(4)], two ? 0 : 1, 1); }
  const n = ops.length, list = new Uint8Array(n * 8), v = new Uint8Array(P.W * P.H), bg = new Uint8Array(P.W * P.H);
  ops.forEach(([cx, cy, r, c, el, er], i) => {
    list.set([...i16bytes(cx + P.X0), ...i16bytes(cy + P.Y0), el, er, r, c], i * 8);
    TW.disc(v, bg, cx, cy, r, c === 0 ? null : c, TW.VIEWPORT, el, er);
  });
  const extra = new Uint8Array(15);
  extra[1] = n & 255; extra[2] = n >> 8;
  const r = runMode(MODE_DISC, extra, list);
  const d = firstPixelDiff(planesToScreen(r.mem), v);
  if (d) fail(`круг пиксель (${d.x},${d.y}) emu=${d.got} oracle=${d.exp}`);
  console.log(`OK  закрашенный круг: ${n} (три и два центра, центры за полем), экран совпал`);
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

function testText() {
  const gen = new LCG(0x7E87);
  const strs = [];
  const add = (col, row, color, s) => strs.push({ col, row, color, s });
  add(0, 0, 2, '');
  add(0, 1, 2, 'A');
  add(0, 2, 2, '????????????????????????????????'); // 32
  add(0, 3, 2, 'hello'); // lower → upper
  add(0, 4, 4, 'PLAYER 1');
  add(31, 31, 2, 'Z');
  add(-1, 0, 2, 'X'); // skipped by both
  while (strs.length < 200) {
    const n = gen.below(33);
    let s = '';
    for (let i = 0; i < n; i++) s += String.fromCharCode(32 + gen.below(64));
    add(gen.below(40) - 4, gen.below(36) - 2, 1 + gen.below(7), s);
  }
  const chunks = [];
  const v = new Uint8Array(P.W * P.H);
  for (const t of strs) {
    chunks.push(t.col & 255, t.row & 255, t.color, t.s.length);
    for (let i = 0; i < t.s.length; i++) chunks.push(t.s.charCodeAt(i) & 255);
    TW.drawText(v, t.col, t.row, t.s, t.color);
  }
  const extra = new Uint8Array(15);
  extra[1] = strs.length & 255; extra[2] = strs.length >> 8;
  const r = runMode(MODE_TEXT, extra, Uint8Array.from(chunks));
  const got = planesToScreen(r.mem);
  const d = firstPixelDiff(got, v);
  if (d) fail(`текст (${d.x},${d.y}) emu=${d.got} oracle=${d.exp}`);
  console.log(`OK  знак/строка: ${strs.length}, экран совпал`);
}

function runOnScreen(mode, v0, extra = new Uint8Array(15)) {
  boot();
  poke(machine, 0xA000, screenToPlanes(v0).subarray(0xA000));
  poke(machine, PARAM, hdr(mode, extra));
  return runUntil(machine, { haltPc: null, maxInsns: 80_000_000 });
}

function testCrumble() {
  const cases = [];
  const empty = new Uint8Array(65536);
  cases.push(empty);
  const full = new Uint8Array(65536).fill(1);
  cases.push(full);
  const field = new Uint8Array(65536);
  TW.drawFrame(field, false);
  for (let x = 3; x <= 252; x++) {
    const top = 80 + (x % 40);
    for (let y = top; y <= 252; y++) field[y * 256 + x] = 1;
  }
  ringZero(field, 125, 113, 30);
  cases.push(field);
  const gen = new LCG(0xC8B1);
  while (cases.length < 200) {
    const v = new Uint8Array(65536);
    TW.drawFrame(v, false);
    for (let x = 3; x <= 252; x++) {
      const top = 40 + gen.below(160);
      for (let y = top; y <= 252; y++) v[y * 256 + x] = 1;
    }
    if (gen.below(2)) ringZero(v, 20 + gen.below(200), 40 + gen.below(160), gen.below(40));
    cases.push(v);
  }
  const bg = new Uint8Array(65536);
  for (let i = 0; i < cases.length; i++) {
    const v = cases[i].slice();
    TW.crumbleColumns(v, bg);
    const r = runOnScreen(MODE_CRUMBLE, cases[i]);
    const got = planesToScreen(r.mem);
    const d = firstPixelDiff(got, v);
    if (d) fail(`осыпание случай #${i} (${d.x},${d.y}) emu=${d.got} oracle=${d.exp}`);
  }
  console.log(`OK  осыпание: ${cases.length} (пустой, сплошной, воронка r=30, случайные)`);
}

function testReplace() {
  const gen = new LCG(0x3E3);
  const cases = [];
  const a = new Uint8Array(65536);
  a[0] = 3;
  for (let i = 1; i < 400; i++) a[gen.below(65536)] = 3;
  cases.push(a);
  while (cases.length < 200) {
    const v = new Uint8Array(65536);
    for (let i = 0; i < 800; i++) v[gen.below(65536)] = gen.below(8);
    cases.push(v);
  }
  const bg = new Uint8Array(65536);
  for (let i = 0; i < cases.length; i++) {
    const v = cases[i].slice();
    TW.replaceTmp(v, bg, 0, 0);
    const r = runOnScreen(MODE_REPLACE, cases[i]);
    const got = planesToScreen(r.mem);
    const d = firstPixelDiff(got, v);
    if (d) fail(`replaceTmp #${i} (${d.x},${d.y}) emu=${d.got} oracle=${d.exp}`);
  }
  console.log(`OK  replaceTmp: ${cases.length}, точка (0,0) не трогается`);
}

function encPal(r, g, b) { return ((b & 3) << 6) | ((g & 7) << 3) | (r & 7); }

function testPal() {
  const gen = new LCG(0x0A1);
  const PAGE = [[0, 0, 0], [1, 5, 0], [5, 5, 2], [7, 6, 1]].map(([r, g, b]) => encPal(r, g, b));
  const gameC = (idx) => ((idx >> 2) & 1) + 2 * ((idx >> 1) & 1) + 4 * (idx & 1);
  let n = 0;
  const runCase = (ps) => {
    const list = new Uint8Array(32);
    for (let i = 0; i < 4; i++) {
      const p = ps[i];
      list[i * 2] = p.men & 255; list[i * 2 + 1] = (p.men >> 8) & 255;
      list[8 + i * 2] = p.colors[0] & 255; list[9 + i * 2] = (p.colors[0] >> 8) & 255;
      list[16 + i * 2] = p.colors[1] & 255; list[17 + i * 2] = (p.colors[1] >> 8) & 255;
      list[24 + i * 2] = p.colors[2] & 255; list[25 + i * 2] = (p.colors[2] >> 8) & 255;
    }
    const bytes = PAGE.slice();
    for (let i = 0; i < 4; i++) {
      const [R, G, B] = TW.tankPalV06C(ps[i]);
      bytes[4 + i] = encPal(R, G, B);
    }
    const exp = new Uint8Array(16);
    for (let idx = 0; idx < 16; idx++) exp[idx] = bytes[gameC(idx)];
    const extra = new Uint8Array(15);
    extra[1] = 1;
    const r = runMode(MODE_PAL, extra, list);
    for (let i = 0; i < 16; i++) {
      if (r.mem[RESULT + i] !== exp[i]) {
        fail(`палитра случай #${n} рег ${i} emu=${r.mem[RESULT + i]} oracle=${exp[i]}`);
      }
    }
    n++;
  };
  const def = TW.PROFILE_V06C.playerColors.map((c, i) => ({ men: 100, colors: c.slice(), idx: i + 1 }));
  runCase(def);
  runCase(def.map((p, i) => ({ ...p, men: i === 0 ? -1 : 50 })));
  runCase(def.map((p) => ({ ...p, men: 0 })));
  runCase(def.map((p) => ({ ...p, men: 1 })));
  while (n < 200) {
    runCase(def.map((p) => ({ ...p, men: gen.below(120) - 10 })));
  }
  console.log(`OK  палитра: ${n} наборов 16 регистров`);
}

const PLY = 80;
function i16b(n) { n = (n << 16) >> 16; return [n & 255, (n >> 8) & 255]; }
function i32b(n) { n |= 0; return [n & 255, (n >> 8) & 255, (n >> 16) & 255, (n >>> 24) & 255]; }
function packPlayer(p) {
  const b = new Uint8Array(PLY);
  const name = String(p.name ?? '');
  for (let i = 0; i < Math.min(name.length, 16); i++) b[i] = name.charCodeAt(i);
  b[16] = p.idx;
  b[17] = p.facing & 255;
  b.set(i16b(p.angle), 18);
  b.set(i16b(p.power), 20);
  b.set(i16b(p.men), 22);
  b[24] = p.weapon;
  b[25] = p.guided;
  b.set(i16b(p.herb), 26);
  b.set(i16b(p.vick), 28);
  b.set(i16b(p.wins), 30);
  b.set(i32b(p.score), 32);
  b.set(i32b(p.spent), 36);
  b.set(i16b(p.shield), 40);
  b.set(i16b(p.damp), 42);
  for (let i = 0; i < 18; i++) b.set(i16b(p.ammo[i] | 0), 44 + i * 2);
  return b;
}
function mkPlayer(over = {}) {
  const p = new TW.Player(over.idx ?? 1);
  Object.assign(p, over);
  if (over.ammo) p.ammo = over.ammo.slice();
  return p;
}

function cmpScreen(got, exp, tag) {
  const d = firstPixelDiff(got, exp);
  if (d) fail(`${tag} (${d.x},${d.y}) emu=${d.got} oracle=${d.exp}`);
}

function testPanel() {
  const cases = [
    [mkPlayer({ idx: 1, name: 'Player 1', weapon: 1, ammo: new Array(18).fill(0), power: 200, angle: 90, facing: 1, men: 100 }), 0],
    [mkPlayer({ idx: 2, name: 'Red', facing: -1, angle: 75, power: 1000, men: 50, weapon: 4, ammo: Object.assign(new Array(18).fill(0), { 4: 12 }), herb: 5, vick: 3, guided: 3 }), -50],
    [mkPlayer({ idx: 3, name: 'ABCDEFGHIJKLMNOP', angle: 0, facing: 1, power: 0, men: -3, weapon: 0, ammo: new Array(18).fill(7) }), 123],
    [mkPlayer({ idx: 4, name: '', weapon: 17, ammo: Object.assign(new Array(18).fill(0), { 17: 1 }), herb: 1, vick: 0, guided: 1, men: 0, angle: 1, facing: 1, power: 9 }), 1],
    [mkPlayer({ idx: 1, name: 'X', angle: 100, facing: 1, power: 1234, men: 8, weapon: 11, ammo: new Array(18).fill(0) }), -1],
  ];
  let n = 0;
  for (const item of cases) {
    const p = item[0], wind = item[1];
    const v = new Uint8Array(65536);
    TW.drawPanel(v, p, wind);
    const list = new Uint8Array(2 + PLY);
    list.set(i16b(wind), 0);
    list.set(packPlayer(p), 2);
    const r = runMode(MODE_UI, [0], list);
    cmpScreen(planesToScreen(r.mem), v, `панель #${n}`);
    n++;
  }
  console.log(`OK  панель: ${n} состояний`);
}

function testResults() {
  const mk = (n, extra = {}) => Array.from({ length: n }, (_, i) => mkPlayer({
    idx: extra.idx?.[i] ?? i + 1,
    name: extra.name?.[i] ?? ('P' + (i + 1)),
    wins: extra.wins?.[i] ?? i,
    score: extra.score?.[i] ?? (i + 1) * 1000,
    spent: extra.spent?.[i] ?? i * 100,
  }));
  const cases = [
    [mk(2), 1, 10],
    [mk(4, { name: ['Ann', 'Bob', 'Cat', 'Dan'], wins: [3, 2, 2, 0], score: [9000, 8000, 100, -50], spent: [0, 500, 0, 10] }), 10, 10],
    [mk(1, { name: ['Only'], wins: [0], score: [0], spent: [0] }), 3, 5],
    [mk(3, { name: ['LongNamePlayerX', 'B', 'C'] }), 0, 2],
    [mk(4, { score: [32767, -1000, 1, 99999], spent: [100, 0, 2, 50] }), 8, 8],
  ];
  let n = 0;
  for (const [ps, round, rounds] of cases) {
    const v = new Uint8Array(65536);
    TW.drawResults(v, ps, round, rounds);
    const list = new Uint8Array(3 + PLY * ps.length);
    list[0] = round; list[1] = rounds; list[2] = ps.length;
    for (let i = 0; i < ps.length; i++) list.set(packPlayer(ps[i]), 3 + i * PLY);
    const r = runMode(MODE_UI, [1], list);
    cmpScreen(planesToScreen(r.mem), v, `результаты #${n}`);
    n++;
  }
  console.log(`OK  результаты: ${n} состояний`);
}

function testShop() {
  const p0 = mkPlayer({ idx: 1, name: 'Buyer', score: 50000, spent: 1000, weapon: 1, ammo: Object.assign(new Array(18).fill(0), { 1: 3, 5: 10 }), herb: 2, vick: 0, shield: 4, damp: 0 });
  const menuA = [[0, 1], [0, 5], [1, 0], [2, 0], [2, 1]];
  const cases = [
    { p: p0, menu: [], qty: [], cart: 0, sel: -1 },
    { p: p0, menu: menuA, qty: [0, 0, 0, 0, 0], cart: 0, sel: 0 },
    { p: p0, menu: menuA, qty: [1, 0, 2, 0, 0], cart: 3000, sel: 2 },
    { p: p0, menu: menuA, qty: [0, 5, 0, 1, 0], cart: 15000, sel: menuA.length },
    { p: mkPlayer({ idx: 3, name: 'Z', score: 0, spent: 0, ammo: new Array(18).fill(0) }), menu: [[0, 2], [1, 1]], qty: [0, 0], cart: 0, sel: 3 },
  ];
  let n = 0;
  for (const c of cases) {
    const v = new Uint8Array(65536);
    TW.drawShop(v, c.p, c.menu, c.qty, c.cart, c.sel);
    const list = new Uint8Array(4 + c.menu.length * 4 + PLY);
    list.set(i16b(c.cart), 0);
    list[2] = c.sel < 0 ? 255 : c.sel;
    list[3] = c.menu.length;
    for (let i = 0; i < c.menu.length; i++) {
      list[4 + i * 4] = c.menu[i][0];
      list[5 + i * 4] = c.menu[i][1];
      list.set(i16b(c.qty[i] || 0), 6 + i * 4);
    }
    list.set(packPlayer(c.p), 4 + c.menu.length * 4);
    const r = runMode(MODE_UI, [2], list);
    cmpScreen(planesToScreen(r.mem), v, `магазин #${n}`);
    n++;
  }
  console.log(`OK  магазин: ${n} состояний`);
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
    ['круг', L.disc, L.disc_end],
    ['ствол', L.draw_tank_barrel, L.draw_tank_barrel_end],
    ['знак', L.draw_char, L.draw_char_end],
    ['осыпание', L.crumble, L.crumble_end],
    ['replaceTmp', L.replace_tmp, L.replace_tmp_end],
    ['палитра', L.pal_apply, L.pal_apply_end],
    ['экраны UI', L.draw_panel, L.draw_panel_end],
  ];
  for (const [name, a, b] of rows) {
    if (a == null || b == null) fail(`нет меток размера для ${name}`);
    console.log(`БАЙТЫ  ${name}: ${b - a} (0x${a.toString(16)}..0x${(b - 1).toString(16)})`);
  }
  if (L.kernel_start == null || L.kernel_end == null) fail('нет меток kernel_start/kernel_end');
  const stand = L.kernel_start - 0x0100;
  const kernel = L.kernel_end - L.kernel_start;
  const rom = L.rom_end - 0x0100;
  console.log(`БАЙТЫ  стенд+диспетчер: ${stand}`);
  console.log(`БАЙТЫ  ядро: ${kernel}`);
  console.log(`БАЙТЫ  образ: ${rom}`);
  return {
    random: L.random_end - L.random,
    pixel: L.pixel_end - L.putpixel,
    line: L.line_end - L.line,
    stand,
    kernel,
    rom,
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
testClear();
testBarrel();
testDisc();
testText();
testCrumble();
testReplace();
testPal();
testPanel();
testResults();
testShop();
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
const discT = {};
for (const r of [2, 10, 15, 30, 60]) discT[r] = bench(`круг r=${r}`, L.disc, L.bench_disc_ret, KIND_DISC, { x: 128, y: 140, x2: r, c: 3 });
for (const r of [10, 30, 60]) console.log(`ВЗРЫВ кругом R=${r}: огонь + стирание = ${2 * discT[r].v} vcycles = ${(2 * discT[r].v / 3e6).toFixed(3)} с при 3 МГц`);
console.log(`БАЙТЫ  круг: ${L.disc_end - L.disc}`);
const tCl = bench('очистка экрана', L.clear_screen, L.bench_clear_ret, KIND_CLEAR, {});
const tCh = bench('знак A', L.draw_char, L.bench_char_ret, KIND_CHAR, {});
const field = new Uint8Array(65536);
TW.drawFrame(field, false);
for (let x = 3; x <= 252; x++) {
  const top = 80 + (x % 40);
  for (let y = top; y <= 252; y++) field[y * 256 + x] = 1;
}
ringZero(field, 125, 113, 30);
boot();
poke(machine, 0xA000, screenToPlanes(field).subarray(0xA000));
pokeBench(KIND_CRUMBLE, {});
const rCb = runUntil(machine, { haltPc: L.bench_crumble_ret, countFromPc: L.crumble, maxInsns: 80_000_000 });
console.log(`ТАКТЫ  осыпание рельеф+воронка r=30: cpu_cycles=${rCb.bodyCpu} (vcycles=${rCb.bodyV})`);
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
row('очистка', L.fill_screen_end - L.fill_screen, tCl);
row('знак A', L.draw_char_end - L.draw_char, tCh);
console.log(`осыпание рельеф+r=30\t${L.crumble_end - L.crumble}\t${rCb.bodyCpu}\t${rCb.bodyV}`);
console.log(`линия 200 на точку\t\t${(rL200.bodyV / 200).toFixed(1)} vcycles`);
console.log(`таблица_v6\tточка\t${tPix.v}\t250`);
console.log(`таблица_v6\tтанк\t${tTk.v}\t6000`);
console.log(`таблица_v6\tкрестик\t${tCr.v}\t1200`);
console.log(`таблица_v6\tзнак\t${tCh.v}\t1500`);
console.log(`таблица_v6\tочистка\t${tCl.v}\t350000`);
console.log(`таблица_v6\tрамка\t${tFr.v}\t150000`);
console.log(`таблица_v6\tосыпание\t${rCb.bodyV}\t4000000`);
console.log(`таблица_v6\tядро\t${sz.kernel}\t5000`);
console.log('OK  сверка с эталоном PROFILE_V06C');
