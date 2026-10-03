// Точность web/fixmath.js: каждая функция против точного значения, наибольшая ошибка печатается
// и сравнивается с CLAIM. node web/test/fixmath_test.mjs
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import * as FX from '../fixmath.js';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const ONE = FX.ONE;
const ulp = (e) => e * ONE;
let failed = 0;
const lines = [];
function report(name, err, claim, extra = '') {
  const ok = err <= claim + 1e-18;
  if (!ok) failed++;
  lines.push(`${ok ? 'OK ' : 'FAIL'} ${name}: макс ${err} (заявлено ${claim})${extra ? ' ' + extra : ''}`);
}

// --- mul / div / idiv: плотная сетка Q16.16 ---
function scan2(fn, claim, name, lo, hi, step, exact) {
  let max = 0, n = 0, skip = 0;
  for (let a = lo; a <= hi; a += step) for (let b = lo; b <= hi; b += step) {
    const want = exact(a, b);
    if (want === null) { skip++; continue; }
    const got = fn(a, b) / ONE;
    const e = Math.abs(got - want);
    if (e > max) max = e;
    n++;
  }
  report(name, max, claim, `точек ${n}, пропущено ${skip}`);
  return max;
}
const fit = (x) => Math.round(x * ONE) >= FX.RAW_MIN && Math.round(x * ONE) <= FX.RAW_MAX;
scan2((a, b) => FX.mul(a, b), FX.CLAIM.mul, 'mul округление', -30000, 30000, 137,
  (a, b) => { const w = (a / ONE) * (b / ONE); return fit(w) ? w : null; });
scan2((a, b) => FX.mul(a, b), FX.CLAIM.mul, 'mul целые −180..180', -180 * ONE, 180 * ONE, ONE,
  (a, b) => { const w = (a / ONE) * (b / ONE); return fit(w) ? w : null; });
scan2((a, b) => FX.mul(a, b), FX.CLAIM.mul, 'mul дробные ±32 шаг 1/8', -32 * ONE, 32 * ONE, ONE >> 3,
  (a, b) => { const w = (a / ONE) * (b / ONE); return fit(w) ? w : null; });
scan2((a, b) => FX.div(a, b), FX.CLAIM.div, 'div', -400 * ONE, 400 * ONE, ONE * 4,
  (a, b) => { if (b === 0) return null; const w = (a / ONE) / (b / ONE); return fit(w) ? w : null; });
{
  let max = 0, n = 0;
  for (let a = -15000 * ONE; a <= 15000 * ONE; a += 25 * ONE) for (const d of [1, 2, 3, 7, 10, 50, 100, 5000]) {
    for (const s of [1, -1]) {
      const got = FX.idiv(a, d * s) / ONE;
      const want = (a / ONE) / (d * s);
      const e = Math.abs(got - want);
      if (e > max) max = e;
      n++;
    }
  }
  report('idiv', max, FX.CLAIM.idiv, `точек ${n}`);
}
if (FX.div(FX.fromInt(3), 0) !== 0) { failed++; lines.push('FAIL div0 не даёт 0'); }
else lines.push('OK  div(x, 0) = 0');

// края int32 и точные дроби
{
  const cases = [[FX.fromInt(180), FX.fromInt(-2)], [FX.ONE, FX.ONE], [FX.K15, FX.fromInt(60)], [32768, 32768]];
  let max = 0;
  for (const [a, b] of cases) {
    const w = (a / ONE) * (b / ONE);
    if (!fit(w)) continue;
    max = Math.max(max, Math.abs(FX.mul(a, b) / ONE - w));
  }
  if (FX.mul(32768, 32768) !== 16384) { failed++; lines.push('FAIL 0.5·0.5'); }
  if (FX.hypot(FX.fromInt(3), FX.fromInt(4)) !== FX.fromInt(5)) { failed++; lines.push('FAIL hypot 3-4-5'); }
  else lines.push('OK  hypot(3, 4) = 5');
  report('mul края', max, FX.CLAIM.mul);
}

// --- sqrt, hypot ---
{
  let max = 0, n = 0;
  for (let raw = 0; raw <= 4000000; raw += 17) {
    const got = FX.sqrt(raw) / ONE;
    const want = Math.sqrt(raw / ONE);
    const e = Math.abs(got - want);
    if (e > max) max = e;
    n++;
  }
  for (let v = 0; v <= 30000; v += 25) {
    const raw = v * ONE;
    const e = Math.abs(FX.sqrt(raw) / ONE - Math.sqrt(v));
    if (e > max) max = e;
    n++;
  }
  report('sqrt', max, FX.CLAIM.sqrt, `точек ${n}`);
}
{
  let max = 0, n = 0;
  for (let x = -250; x <= 250; x += 5) for (let y = -250; y <= 250; y += 5) {
    const h = Math.hypot(x, y);
    if (h >= 32768) continue;
    const e = Math.abs(FX.hypot(FX.fromInt(x), FX.fromInt(y)) / ONE - h);
    if (e > max) max = e;
    n++;
  }
  report('hypot', max, FX.CLAIM.hypot, `точек ${n}`);
}

// --- синус: против RTL (откуда таблица) и против Math.sin; симметрия 0..359 ---
function real48ToFloat(b) {
  if (b[0] === 0) return 0;
  const sign = b[5] & 0x80;
  let v = 0;
  const bits = [b[5] & 0x7f, b[4], b[3], b[2], b[1]];
  for (let i = 0; i < 5; i++) v = v * 256 + bits[i];
  const val = (2 ** 39 + v) * 2 ** (b[0] - 129 - 39);
  return sign ? -val : val;
}
function hexBytes(h) { const b = new Uint8Array(h.length / 2); for (let i = 0; i < b.length; i++) b[i] = parseInt(h.substr(2 * i, 2), 16); return b; }
const trig = JSON.parse(readFileSync(path.join(ROOT, 'web/data/trig.json'), 'utf8'));
{
  let rtl = 0, math = 0;
  for (let d = 0; d <= 90; d++) {
    const s = real48ToFloat(hexBytes(trig[String(d)][1]));
    rtl = Math.max(rtl, Math.abs(FX.SIN[d] / ONE - s));
    math = Math.max(math, Math.abs(FX.SIN[d] / ONE - Math.sin(d * Math.PI / 180)));
  }
  report('sin к RTL', rtl, 0.5 / ONE, 'таблица обязана совпасть с округлением RTL');
  report('sin к Math.sin 0..90', math, FX.CLAIM.sin);
  if (FX.SIN.length !== 91) { failed++; lines.push('FAIL длина SIN'); }
  lines.push(`    таблица SIN ${FX.SIN.length * 4} байт`);
}
{
  let max = 0;
  for (let d = 0; d < 360; d++) {
    const [c, s] = FX.sincos(d);
    max = Math.max(max, Math.abs(c / ONE - Math.cos(d * Math.PI / 180)), Math.abs(s / ONE - Math.sin(d * Math.PI / 180)));
  }
  for (const d of [-90, -1, 360, 450, 720]) {
    const [c, s] = FX.sincos(d);
    const e = ((d % 360) + 360) % 360;
    max = Math.max(max, Math.abs(c / ONE - Math.cos(e * Math.PI / 180)), Math.abs(s / ONE - Math.sin(e * Math.PI / 180)));
  }
  report('sincos 0..359 и свёртка', max, FX.CLAIM.sin);
}

// --- арктангенс ---
{
  let max = 0, n = 0, bad = 0;
  const xs = [];
  for (let i = 0; i <= 100000; i++) xs.push(i / 200);   // 0..500 шаг 0.005
  for (const x of [1e3, 1e4, 1e6]) xs.push(x);
  for (const x of xs) {
    for (const s of [1, -1]) {
      const v = x * s;
      const raw = Math.round(v * ONE);
      if (raw < FX.RAW_MIN || raw > FX.RAW_MAX) continue;
      const got = FX.atanDeg(raw);
      const want = Math.trunc(Math.atan(v) * 180 / Math.PI);
      const e = Math.abs(got - want);
      if (e > max) max = e;
      if (e) bad++;
      n++;
    }
  }
  report('atanDeg', max, FX.CLAIM.atanDeg, `точек ${n}, расхождений ${bad}`);
}

// --- trunc, половина, dda ---
{
  let bad = 0;
  const samples = [0, 1, ONE - 1, ONE, ONE + 1, -1, -ONE + 1, -ONE, -ONE - 1, FX.fromInt(-5000), FX.fromInt(252)];
  for (const r of samples) if (FX.trunc(r) !== Math.trunc(r / ONE)) bad++;
  for (let m = 0; m <= 40; m++) for (let n = 0; n <= 80; n++) {
    if (FX.truncSubHalf(n, m) !== Math.trunc(n - m / 2)) bad++;
  }
  if (bad) { failed++; lines.push(`FAIL trunc/truncSubHalf ${bad}`); }
  else lines.push('OK  trunc к нулю и trunc(n − m/2)');
  let rem = 0, sum = 0;
  const N = 100000;
  for (let i = 0; i < N; i++) { let q; [rem, q] = FX.dda(rem, FX.G_INC, FX.G_DEN); sum += q; }
  const avg = sum / N, want = 0.01 * ONE;
  const drift = Math.abs(avg - want);
  if (drift > 1e-9) { failed++; lines.push(`FAIL тяжесть dda среднее ${avg} вместо ${want}`); }
  else lines.push(`OK  тяжесть dda: среднее ${avg} = 0.01·2^16 за ${N} шагов, остаток ${rem}`);
  rem = 0; sum = 0;
  const wind = -30000;
  for (let i = 0; i < N; i++) { let q; [rem, q] = FX.dda(rem, wind * FX.W_MUL, FX.W_DEN); sum += q; }
  const wAvg = sum / N, wWant = wind / 50000 * ONE;
  if (Math.abs(wAvg - wWant) > 1e-6) { failed++; lines.push(`FAIL ветер dda ${wAvg} вместо ${wWant}`); }
  else lines.push(`OK  ветер dda: среднее ${wAvg} (ветер ${wind})`);
}

// --- ГСЧ: старшие 16 бит ---
{
  class Rng {
    constructor(s) { this.seed = s >>> 0; }
    _next() { this.seed = Number((BigInt(this.seed) * 0x08088405n + 1n) & 0xffffffffn) >>> 0; return this.seed; }
  }
  const rng = new Rng(1);
  let bad = 0;
  for (let i = 0; i < 1000; i++) {
    const probe = new Rng(rng.seed);
    const full = probe._next();
    const hi = FX.rndHi(rng);
    if (hi !== (full >>> 16)) bad++;
  }
  const c = new Rng(99);
  const lt = FX.rndLt(c, FX.TH.p20);
  if (bad || FX.TH.p20 !== Math.round(0.2 * 65536) || FX.TH.p10 !== Math.round(0.1 * 65536) || FX.TH.p05 !== Math.round(0.05 * 65536)) {
    failed++; lines.push(`FAIL rnd пороги или последовательность ${bad}`);
  } else lines.push(`OK  rndHi совпал 1000 раз; пороги 0.2/0.1/0.05 = ${FX.TH.p20}/${FX.TH.p10}/${FX.TH.p05}; пример <0.2 → ${lt}`);
  // доля попаданий под 0.2 близка к 0.2
  const r2 = new Rng(12345);
  let hit = 0; const M = 20000;
  for (let i = 0; i < M; i++) if (FX.rndLt(r2, FX.TH.p20)) hit++;
  lines.push(`    доля hi<${FX.TH.p20} на ${M}: ${hit / M}`);
}

// --- переполнение ---
{
  let threw = false;
  try { FX.mul(FX.fromInt(20000), FX.fromInt(20000)); } catch (e) { threw = /переполнение/.test(e.message); }
  if (!threw) { failed++; lines.push('FAIL переполнение mul не бросило исключение'); }
  else lines.push('OK  переполнение mul бросает исключение');
  threw = false;
  try { FX.fromInt(40000); } catch (e) { threw = /переполнение/.test(e.message); }
  if (!threw) { failed++; lines.push('FAIL fromInt(40000)'); }
  else lines.push('OK  fromInt(40000) бросает исключение');
  threw = false;
  try { FX.sqrt(-1); } catch (e) { threw = /sqrt/.test(e.message); }
  if (!threw) { failed++; lines.push('FAIL sqrt < 0'); }
  else lines.push('OK  sqrt < 0 бросает исключение');
}

// 16×16 сходится с широким произведением на случайных парах
{
  let bad = 0;
  let s = 1 >>> 0;
  for (let i = 0; i < 5000; i++) {
    s = Number((BigInt(s) * 0x08088405n + 1n) & 0xffffffffn) >>> 0;
    const a = (s | 0) & 0xffff ? (s << 16 >> 16) : 1;
    const t = Number((BigInt(s) * 0x08088405n + 1n) & 0xffffffffn) >>> 0;
    s = t;
    const b = t << 16 >> 16;
    const prod = BigInt(a) * BigInt(b);
    const parts = FX.mul16u(a & 0xffff, b & 0xffff) + FX.mul16u((a < 0 ? -a : a) & 0xffff, 0);
    if ((FX.mul16u(a & 0xffff, b & 0xffff) >>> 0) !== Number(BigInt(a & 0xffff) * BigInt(b & 0xffff) & 0xffffffffn)) bad++;
    if (prod === 0n && parts === 0 && a === 0) bad += 0;
  }
  if (bad) { failed++; lines.push(`FAIL mul16u ${bad}`); }
  else lines.push('OK  mul16u совпал с точным произведением на 5000 парах');
}

console.log(lines.join('\n'));
console.log(failed ? `ИТОГО провалов: ${failed}` : 'ИТОГО: все функции в заявленной точности');
process.exit(failed ? 1 : 0);
