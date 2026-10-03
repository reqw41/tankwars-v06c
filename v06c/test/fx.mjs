// Арифметика Q16.16 на 8080 против web/fixmath.js. node v06c/test/fx.mjs
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import * as FX from '../../web/fixmath.js';
import { createMachine, loadRom, poke, runUntil, parseSym } from '../tools/run.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const L = parseSym(path.join(ROOT, 'v06c/build/tw.sym'));
const rom = new Uint8Array(fs.readFileSync(path.join(ROOT, 'v06c/build/tw.rom')));
const machine = createMachine();
const PARAM = 0x80, LIST = 0x8000, RESULT = 0x9400, MODE_FX = 20;
const le = (v) => [v & 255, (v >>> 8) & 255, (v >>> 16) & 255, (v >>> 24) & 255];
const i32 = (m, o) => (m[o] | (m[o + 1] << 8) | (m[o + 2] << 16) | (m[o + 3] << 24)) | 0;
let seed = 12345; const rnd = () => (seed = (Math.imul(seed, 1103515245) + 12345) >>> 0) / 4294967296;
const ri = (lo, hi) => lo + Math.floor(rnd() * (hi - lo + 1));
// случайное Q16.16 разного масштаба
const rq = (maxInt) => { const k = ri(0, 5); const v = k === 0 ? ri(-65536, 65536) : k === 1 ? ri(-maxInt, maxInt) * 65536 : Math.round((rnd() * 2 - 1) * maxInt * 65536); return v | 0; };
FX.setDebug(false);
function batch(name, recs, want, cmp, cyc) {
  const list = new Uint8Array(recs.length * 9);
  recs.forEach(([op, a, b], i) => list.set([op, ...le(a), ...le(b)], i * 9));
  loadRom(machine, rom);
  const hdr = new Uint8Array(16); hdr[0] = MODE_FX; hdr[2] = recs.length & 255; hdr[3] = recs.length >> 8;
  poke(machine, PARAM, hdr); poke(machine, LIST, list);
  const r = runUntil(machine, { haltPc: null, maxInsns: 400_000_000 });
  for (let i = 0; i < recs.length; i++) {
    const got = cmp(r.mem, RESULT + i * 8), w = want[i];
    if (JSON.stringify(got) !== JSON.stringify(w)) { console.error(`FAIL ${name} #${i}: a=${recs[i][1]} b=${recs[i][2]} 8080=${JSON.stringify(got)} эталон=${JSON.stringify(w)}`); process.exit(1); }
  }
  console.log(`OK  ${name}: ${recs.length} случаев; в среднем ${Math.round(r.vcycles / recs.length)} vcycles`);
}
const one = (m, o) => i32(m, o);
const N = 300;      // список (9 байт на случай) не должен дотянуться до RESULT
const fits = (f) => { try { FX.setDebug(true); const v = f(); FX.setDebug(false); return v; } catch { FX.setDebug(false); return null; } };
{ // умножение
  const recs = [], want = [];
  const edge = [[0, 0], [65536, 65536], [-65536, 65536], [1, 1], [-1, 1], [32768, 32768], [0x7fff0000 | 0, 65536], [-0x7fff0000, -65536], [3, 21845], [-3, 21845], [98304, 98304], [-98304, 98304]];
  for (const [a, b] of edge) { recs.push([1, a, b]); want.push(FX.mul(a, b)); }
  while (recs.length < N) { const a = rq(180), b = rq(180); const v = fits(() => FX.mul(a, b)); if (v === null) continue; recs.push([1, a, b]); want.push(v); }
  batch('умножение', recs, want, one);
}
{ // деление
  const recs = [], want = [];
  for (const [a, b] of [[65536, 65536], [0, 65536], [65536, 0], [-65536, 3 * 65536], [65536, 3 * 65536], [1, 2], [-1, 2], [3, 2], [-3, 2], [250 * 65536, 65536], [250 * 65536, 1311]]) { const v = fits(() => FX.div(a, b)); if (v !== null) { recs.push([2, a, b]); want.push(v); } }
  while (recs.length < N) { const a = rq(300), b = rq(300); const v = fits(() => FX.div(a, b)); if (v === null) continue; recs.push([2, a, b]); want.push(v); }
  batch('деление', recs, want, one);
}
{ // деление на целое
  const recs = [], want = [];
  for (const n of [1, 2, 3, 10, 50, 100, 5000, 65535]) for (const a of [0, 1, -1, 5, -5, 65536, -65536, 0x7fffffff, -0x7fffffff, 1000 * 65536, -1000 * 65536]) { recs.push([3, a, n]); want.push(FX.idiv(a, n)); }
  while (recs.length < N) { const a = rq(30000), n = [10, 50, 5000, ri(1, 65535)][ri(0, 3)]; recs.push([3, a, n]); want.push(FX.idiv(a, n)); }
  batch('деление на целое', recs, want, one);
}
{ // корень
  const recs = [], want = [];
  for (const a of [0, 1, 2, 3, 4, 65536, 65535, 65537, 4 * 65536, 0x7fffffff, 2 * 65536, 100 * 65536, 16]) { recs.push([4, a, 0]); want.push(FX.sqrt(a)); }
  while (recs.length < N) { const a = Math.abs(rq(32000)); recs.push([4, a, 0]); want.push(FX.sqrt(a)); }
  batch('корень', recs, want, one);
}
{ // гипотенуза
  const recs = [], want = [];
  for (const [a, b] of [[3 * 65536, 4 * 65536], [0, 0], [65536, 0], [0, -65536], [-300 * 65536, 300 * 65536], [1, 1], [250 * 65536, 226 * 65536]]) { recs.push([5, a, b]); want.push(FX.hypot(a, b)); }
  while (recs.length < N) { const a = rq(20000), b = rq(20000); const v = fits(() => FX.hypot(a, b)); if (v === null) continue; recs.push([5, a, b]); want.push(v); }
  batch('гипотенуза', recs, want, one);
}
{ // синус и косинус: все углы -360..720
  const recs = [], want = [];
  for (let d = -360; d <= 720; d++) { recs.push([6, d, 0]); const [c, s] = FX.sincos(d); want.push([c, s]); }
  for (let k = 0; k < recs.length; k += 300) batch('синус и косинус', recs.slice(k, k + 300), want.slice(k, k + 300), (m, o) => [i32(m, o), i32(m, o + 4)]);   // список и результат не должны пересечься
}
{ // арктангенс
  const recs = [], want = [];
  for (const a of [0, 1, -1, 65536, -65536, 1144, 1143, 1145, 0x7fffffff, -0x7fffffff, 3754936, 3754935, 3754937]) { recs.push([7, a, 0]); want.push(FX.atanDeg(a)); }
  while (recs.length < N) { const a = [rq(3), rq(60), rq(30000)][ri(0, 2)]; recs.push([7, a, 0]); want.push(FX.atanDeg(a)); }
  batch('арктангенс', recs, want, (m, o) => (m[o] << 24) >> 24);
}
{ // усечение
  const recs = [], want = [];
  for (const a of [0, 1, -1, 65535, 65536, 65537, -65535, -65536, -65537, 98304, -98304, 0x7fffffff, -0x80000000]) { recs.push([8, a, 0]); want.push(FX.trunc(a)); }
  while (recs.length < N) { const a = rq(30000); recs.push([8, a, 0]); want.push(FX.trunc(a)); }
  batch('усечение', recs, want, (m, o) => ((m[o] | (m[o + 1] << 8)) << 16) >> 16);
}
console.log(`OK  арифметика Q16.16 совпала с web/fixmath.js; байт ${L.fx_end - L.fx_shl}`);
