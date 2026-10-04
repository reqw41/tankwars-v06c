// Tank Wars 2.5 — эталонная модель на JS (ES-модуль для браузера и node).
// Побитный перенос scripts/ref/*.py; каждая функция сверена с настоящей игрой (web/test/run_fixtures.mjs).
// Адреса в комментариях — Ghidra (re/bomb25_flat.exe). Экран — 320×200 байт (индексы цветов VGA).
// Профиль Вектора (fixed) считает в Q16.16, см. web/fixmath.js. Профиль DOS — по-прежнему Real48.
import * as FX from './fixmath.js';

// ---------- профиль экрана: геометрия поля и классы цветов ----------
// DOS — оригинал (всё сверено с настоящей игрой). V06C — Вектор-06Ц: 256×256, 16 цветов (см. docs/spec/v06c.md).
export const PROFILE_DOS = { name: 'dos', W: 320, H: 200, X0: 11, Y0: 31, X1: 309, Y1: 189,
  ground: 2, frame: 13, ball: 19, beam: 0xfe, tank0: 20, nTank: 10, maxPlayers: 10,
  passable: (c) => c === 0 || (c >= 30 && c <= 99),          // сквозь это падает земля (1062:027e)
  fire: (i) => (0x82 + i) & 0xff,                             // кольца огня
  tmp: (c) => c & 0xff,                                       // временные цвета анимаций (в конце стираются)
  isTmp: (c, lo, hi) => c >= lo && c <= hi,
  sky: (c) => c, trail: (shooter) => (100 - shooter) & 0xff,
  terrain: { init: 150, lo: 20, hi: 140, min: 3, max: 155, margin: (n) => 60 - 7 * (n - 2) },
  place: { rnd: 28, off: 5 }, bgKinds: 6, sparkM: 390, fountainN: 400 };
// Вектор-06Ц: 3 плоскости (24 КБ экрана, 40 КБ под программу), 8 цветов, до 4 игроков. Поле 250×226 (x 3..252, y 27..252).
// Цвета: 0 фон, 1 земля, 2 рамка и текст, 3 временный (мяч, огонь, луч, искры), 4..7 танки игроков 1..4.
// Буфера фона нет: фон всегда чёрный (noBg), следа и звёзд нет; ИИ считает землю на луче, не рисуя (aiNoDraw);
// искры гибели считаются покадрово, без общего списка (stream).
const X = 0x7fff;
export const PROFILE_V06C = { name: 'v06c', W: 256, H: 256, X0: 3, Y0: 27, X1: 252, Y1: 252,
  ground: 1, frame: 2, ball: 3, beam: 3, tank0: 4, nTank: 4, maxPlayers: 4,
  passable: (c) => c === 0,
  fire: () => 3, tmp: () => 3, isTmp: (c) => c === 3,
  sky: () => 0, trail: null, noBg: true, aiNoDraw: true, stream: true, fixed: true, clip: true, disc: true,
  playerColors: [[1, X, X], [1, 1, X], [X, 1, 1], [1, X, 1]],          // красный, жёлтый, голубой, пурпурный
  terrain: { init: 200, lo: 20, hi: 185, min: 3, max: 205, margin: (n) => 50 - 6 * (n - 2) },
  place: { rnd: 24, off: 5 }, bgKinds: 1,
  sparkM: 48, fountainN: 50,
  shopNoGuides: true };   // магазин: всё оружие, щит и демпфер; наведения в порте на 8080 нет       // гибель: искр и комьев земли в 8 раз меньше, чем в оригинале (скорость 8080)
let P = PROFILE_DOS;
export let W = 320, H = 200, SCREEN = W * H;
export function setProfile(p) { P = p; W = p.W; H = p.H; SCREEN = W * H; VIEWPORT.splice(0, 4, p.X0, p.Y0, p.X1, p.Y1); }
export const profile = () => P;
const isTank = (c) => c >= P.tank0 && c < P.tank0 + P.nTank;
const tankColor = (idx) => P.tank0 + idx - 1;

// ---------- данные из RTL (передаются через init) ----------
let BARREL = null;   // a -> [dx, dy]  (1062:059f, Trunc(Cos/Sin(DegToRad(a))*8))
let TRIG = null;     // a -> [cos, sin] Real48 RTL TP6 (Cos(0) = 0.999999999994543)
export function init({ barrel, trig }) {
  BARREL = {}; for (const k in barrel) BARREL[+k] = barrel[k];
  TRIG = {};
  for (const k in trig) TRIG[+k] = [real48ToFloat(hexBytes(trig[k][0])), real48ToFloat(hexBytes(trig[k][1]))];
}
function hexBytes(h) { const b = new Uint8Array(h.length / 2); for (let i = 0; i < b.length; i++) b[i] = parseInt(h.substr(2 * i, 2), 16); return b; }

// ---------- Real48 ----------
export function real48ToFloat(b) {
  if (b[0] === 0) return 0;
  const sign = b[5] & 0x80;
  // мантисса 39 бит + неявная 1
  let sig = 1;
  let scale = 0.5;
  const bits = [b[5] & 0x7f, b[4], b[3], b[2], b[1]];
  let v = 0, nbits = 0;
  for (let i = 0; i < 5; i++) { v = v * 256 + bits[i]; }
  // v — 39 бит дробной части
  const val = (2 ** 39 + v) * 2 ** (b[0] - 129 - 39);
  return sign ? -val : val;
}
const _dv = new DataView(new ArrayBuffer(8));
// q(x): округление до Real48 (как float_to_real48 + обратно в scripts/real48.py: n = floor(m*2^39 + 0.5))
export function q(x) {
  if (P.fixed) throw new Error('q(): вещественная арифметика в режиме fixed');
  if (x === 0 || !Number.isFinite(x)) return 0;
  const ax = Math.abs(x);
  _dv.setFloat64(0, ax);
  let E = (_dv.getUint16(0) >> 4) & 0x7ff;
  let m2, e1;                      // ax = m2 * 2^e1, 1 <= m2 < 2
  if (E === 0) { // субнормаль — в Real48 это 0
    return 0;
  }
  e1 = E - 1023;
  m2 = ax / 2 ** e1;
  let exp = e1 + 129;
  if (exp <= 0) return 0;
  let n = Math.floor(m2 * 2 ** 39 + 0.5);
  if (n >= 2 ** 40) { n = n / 2; exp += 1; }
  if (exp > 255) { exp = 255; n = 2 ** 40 - 1; }
  const val = n * 2 ** (exp - 129 - 39);
  return x < 0 ? -val : val;
}
const trunc = Math.trunc;
// В режиме fixed эти обёртки не должны вызываться: физика идёт через fixmath.
function msqrt(x) { if (P.fixed) throw new Error('Math.sqrt в режиме fixed'); return Math.sqrt(x); }
function matan(x) { if (P.fixed) throw new Error('Math.atan в режиме fixed'); return Math.atan(x); }
function msin(x) { if (P.fixed) throw new Error('Math.sin в режиме fixed'); return Math.sin(x); }
function mcos(x) { if (P.fixed) throw new Error('Math.cos в режиме fixed'); return Math.cos(x); }
// Координата полёта: в fixed это raw Q16.16, иначе Real48. Наружу — целые пиксели, усечение к нулю.
function world(x) { return P.fixed ? FX.trunc(x) : trunc(x); }
function worldSub(x, n) { return P.fixed ? FX.trunc(FX.sub(x, FX.fromInt(n))) : trunc(x - n); }

// ---------- ГСЧ TP6 (1c5b:1639/15ea/1600) ----------
export class TPRandom {
  constructor(seed) { this.seed = seed >>> 0; }
  _next() { this.seed = (Number((BigInt(this.seed) * 0x08088405n + 1n) & 0xffffffffn)) >>> 0; return this.seed; }
  word(n) { const hi = this._next() >>> 16; return n ? hi % n : 0; }
  real() {
    if (P.fixed) throw new Error('TPRandom.real(): вещественное случайное в режиме fixed');
    return this._next() / 4294967296;
  }
}

// ---------- примитивы VRAM ----------
// Вектор: точка за пределами экрана 0..255 не пишется и читается как 0 (адрес-заглушка за концом массива).
// На 4743 ходах самоигры таких обращений не было (work/oob.mjs), правило — страховка для порта.
const off16 = (x, y) => (P.clip && (x < 0 || x > 255 || y < 0 || y > 255) ? 0x10000 : (y * W + x) & 0xffff);
function poke(v, o, c) { if (o < v.length) v[o] = c; }
function peek(v, o) { return o < v.length ? v[o] : 0; }

// 1691:08ef — Брезенхем без отсечения; bg -> 1691:09cb (пиксель из фона)
export function line(v, x1, y1, x2, y2, c, bg = null) {
  const put = bg ? (o) => { if (o < v.length) v[o] = o < bg.length ? bg[o] : 0; } : (o) => poke(v, o, c);
  let cx = x2 - x1;
  if (cx === 0) {
    const ya = Math.min(y1, y2), yb = Math.max(y1, y2);
    let o = off16(x1, ya);
    for (let i = 0; i < yb - ya + 1; i++) { put(o); o = (o + W) & 0xffff; }
    return;
  }
  if (cx < 0) { cx = -cx; [x1, x2] = [x2, x1]; [y1, y2] = [y2, y1]; }
  let bx = y2 - y1;
  if (bx === 0) { let o = off16(x1, y1); for (let i = 0; i < cx + 1; i++) { put(o); o = (o + 1) & 0xffff; } return; }
  let step = W;
  if (bx < 0) { bx = -bx; step = -W; }
  const ymajor = bx > cx;
  if (ymajor) [bx, cx] = [cx, bx];
  const d2 = 2 * bx; let err = d2 - cx; const d22 = d2 - 2 * cx;
  let o = off16(x1, y1);
  for (let i = 0; i < cx + 1; i++) {
    put(o); o = (o + 1) & 0xffff;
    if (!ymajor) { if (err < 0) err += d2; else { err += d22; o = (o + step) & 0xffff; } }
    else { o = (o + step) & 0xffff; if (err < 0) { err += d2; o = (o - 1) & 0xffff; } else err += d22; }
  }
}
export function rect(v, x1, y1, x2, y2, c) { line(v, x2, y1, x2, y2, c); line(v, x1, y1, x1, y2, c); line(v, x1, y2, x2, y2, c); line(v, x1, y1, x2, y1, c); }
const frameRects = (v) => { rect(v, P.X0 - 3, P.Y0 - 3, P.X1 + 3, P.Y1 + 3, P.frame); rect(v, P.X0 - 1, P.Y0 - 1, P.X1 + 1, P.Y1 + 1, P.frame); };
export function drawFrame(v, rebound) {            // 2b39:0386
  frameRects(v);
  if (!rebound) line(v, P.X0, P.Y1, P.X1, P.Y1, P.ground);
}

// ---------- небо (Background 6) ----------
export function skyBackground() {
  const v = new Uint8Array(SCREEN);
  for (let y = 31; y <= 189; y++) for (let x = 11; x <= 309; x++) v[y * W + x] = 30 + ((y - 30) >> 3);
  frameRects(v);
  return v;
}

// ---------- рельеф (2eef:0a4f..0dbc) ----------
const P_STEER = 0.20000000000004547, P_FLIP = 0.10000000000002274;
export function generateTerrain(rng, players) {
  const T = P.terrain, cols = []; let d = 1 - 2 * rng.word(2); const m = T.margin(players);
  let h = rng.word(T.init), s = 0, x = P.X0;
  const col = (xx, hh) => cols.push([xx, P.Y1 + 1 - hh]);
  const st = (hh) => (s > 0 ? hh + 1 : hh - 1);
  while (x < P.X1 + 1) {
    if (m + P.X0 > x || P.X1 - m < x) { col(x, h); x++; continue; }
    const a = Math.abs(s);
    if (s === 0) { col(x, h); x++; col(x, h); x++; col(x, h); }
    if (a === 1) { col(x, h); x++; col(x, h); x++; h = st(h); col(x, h); }
    if (a === 2) { col(x, h); x++; h = st(h); col(x, h); x++; h = st(h); col(x, h); }
    if (a === 3) { col(x, h); x++; h = st(h); col(x, h); h = st(h); }
    if (a === 4) { col(x, h); h = st(h); h = st(h); }
    if (P.fixed ? FX.rndLt(rng, FX.TH.p20) : rng.real() < P_STEER) s += d;
    if ((P.fixed ? FX.rndLt(rng, FX.TH.p10) : rng.real() < P_FLIP) || Math.abs(s) > 4) d = -d;
    s = Math.max(-4, Math.min(4, s));
    if (h <= T.lo) d = 1; if (h >= T.hi) d = -1; if (h <= T.min) s = 1; if (h >= T.max) s = -1;
    x++;
  }
  return { cols, hFinal: h };
}
export function renderTerrain(t, v) {
  for (const [x, top] of t.cols) { const y0 = Math.min(top, P.Y1), y1 = Math.max(top, P.Y1); for (let y = y0; y <= y1; y++) if (y >= 0 && y < H && x >= 0 && x < W) v[y * W + x] = P.ground; }
  return v;
}

// ---------- танки ----------
export const SPRITE = [[0,0],[1,0],[2,0],[3,0],[4,0],[-1,0],[-2,0],[-3,0],[-4,0],
  [0,-1],[-2,-1],[-3,-1],[-4,-1],[2,-1],[3,-1],[4,-1],
  [0,-2],[-1,-2],[-2,-2],[-3,-2],[1,-2],[2,-2],[3,-2],
  [0,-3],[-1,-3],[-2,-3],[-3,-3],[1,-3],[2,-3],[3,-3],[0,-4],[-1,-4],[1,-4]];
const SUPPORT = (c) => c === P.ground || c === P.frame;
export function drawTank(v, x, y, c) { const b = off16(x, y); for (const [dx, dy] of SPRITE) poke(v, (b + dy * W + dx) & 0xffff, c); }
export function eraseTank(v, bg, x, y) { const b = off16(x, y); for (const [dx, dy] of SPRITE) { const o = (b + dy * W + dx) & 0xffff; poke(v, o, peek(bg, o)); } }
function barrelOf(a) { return BARREL[a >= 0 ? a % 361 : ((a % 360) + 360) % 360]; }
export function drawTankBarrel(v, t) {
  if (!t.alive) return;
  drawTank(v, t.x, t.y, tankColor(t.idx));
  const [dx, dy] = barrelOf(t.angle);
  line(v, t.x, t.y, t.x + dx * t.facing, t.y - dy, tankColor(t.idx));
}
const sup = (v, x, y) => SUPPORT(peek(v, off16(x, y + 1)));
export function placeTanks(rng, players, v, bg, rebound = false) {
  const ts = [];
  for (let i = 1; i <= players; i++) ts.push({ idx: i, x: 0, y: 0, angle: 90, power: 200, facing: 1, men: 100, alive: true, shield: 0, damp: 0, score: 0, energy: 1000, weapon: 1 });
  const first = rng.word(P.place.rnd) + P.X0 + P.place.off, last = P.X1 - P.place.off + 1 - rng.word(P.place.rnd);
  ts[0].x = first; ts[players - 1].x = last;
  const q2 = trunc((last - first) / (players - 1));
  for (let i = 2; i < players; i++) ts[i - 1].x = (i - 1) * q2 + first;
  for (const t of ts) {
    t.angle = (t.idx === 1 || t.idx === players) ? 75 : 90;
    t.facing = t.idx === players ? -1 : 1; t.y = P.Y0 + 1;
    let any = false; for (let dx = -4; dx <= 4; dx++) if (sup(v, t.x + dx, t.y)) any = true;
    if (!any) {
      for (;;) {
        eraseTank(v, bg, t.x, t.y); t.y++; drawTank(v, t.x, t.y, tankColor(t.idx));
        let all = true; for (let dx = -4; dx <= 4; dx++) if (!sup(v, t.x + dx, t.y)) all = false;
        if (all) break;
      }
      drawTankBarrel(v, t); drawFrame(v, rebound);
    }
  }
  return ts;
}

// ---------- осыпание (1062:027e) и падение танков (2b39:0020) ----------
const fallable = (c) => P.passable(c);
export function crumble(v, bg) {
  const lst = [];
  for (let bx = (P.Y1 + 2) * W; bx > 0; bx--) if (v[bx] === P.ground && fallable(v[bx + W])) { v[bx] = bg[bx]; v[bx + W] = P.ground; lst.push(bx + W); }
  if (!lst.length) return 0;
  let passes = 0;
  for (;;) {
    let moved = false; passes++;
    for (let i = 0; i < lst.length; i++) {
      const e = lst[i]; if (e === 0) continue;
      if (e + W < v.length && fallable(v[e + W])) { v[e] = bg[e]; v[e + W] = P.ground; lst[i] = e + W; moved = true; } else lst[i] = 0;
    }
    if (!moved) return passes;
  }
}
// То же без списка падающих точек: в каждом столбце вся земля над пустотой съезжает вниз до опоры.
// Эквивалентность с crumble проверяется в web/test/v06c_selfplay.mjs и run_fixtures.mjs.
export function crumbleColumns(v, bg) {
  for (let x = 0; x < W; x++) {
    let floor = -1;                                        // нижняя свободная строка под текущим «пролётом»
    for (let y = H - 1; y >= 0; y--) {
      const o = y * W + x, c = v[o];
      if (fallable(c)) { if (floor < 0) floor = y; }
      else if (c === P.ground && floor >= 0 && y <= P.Y1 + 1 && o > 0) { v[o] = bg[o]; v[floor * W + x] = P.ground; floor--; }
      else floor = -1;
    }
  }
}
export function crumbleGate(v, bg, rng, percent, rebound) {      // 2b39:03da
  drawFrame(v, rebound);
  if (P.fixed ? FX.rndLeRatio(rng, percent, 100) : rng.real() * 100 <= percent) { crumble(v, bg); return true; }
  return false;
}
export function tanksFall(v, bg, tanks, rng, rebound) {
  drawFrame(v, rebound);
  for (const t of tanks) {
    let falling = t.alive;
    for (let dx = -3; dx <= 3; dx++) if (sup(v, t.x + dx, t.y)) falling = false;
    if (sup(v, t.x - 4, t.y) && sup(v, t.x + 4, t.y)) falling = false;
    if (!falling) { drawTankBarrel(v, t); continue; }
    const [bdx, bdy] = barrelOf(t.angle);
    line(v, t.x, t.y, t.x + bdx * t.facing, t.y - bdy, 0, bg);
    for (;;) {
      const ox = t.x, oy = t.y;
      drawTank(v, ox, oy, tankColor(t.idx));
      t.y++;
      if (sup(v, t.x + 4, t.y)) t.x--;
      if (sup(v, t.x - 4, t.y)) t.x++;
      let landed = true; for (let dx = -4; dx <= 4; dx++) if (!sup(v, t.x + dx, t.y)) landed = false;
      if (t.damp > 0) t.damp--; else t.men -= rng.word(3) + 1;
      eraseTank(v, bg, ox, oy);
      if (landed) break;
    }
    drawTankBarrel(v, t);
  }
}

// ---------- эллипс 1691:025c / 0592 ----------
const s32 = (v) => { v = Number(BigInt.asIntN(32, BigInt(Math.trunc(v)))); return v; };
const mul32 = (a, b) => Number((BigInt(a) * BigInt(b & 0xffff)) & 0xffffffffn);
export function ellipsePoints(x, y, rx, ry) {
  const a2 = rx * rx, two_a2 = 2 * a2, b2 = ry * ry, two_b2 = 2 * b2;
  const br = [x, y + ry], tr = [x, y - ry], bl = [x, y + ry], tl = [x, y - ry];
  let px = 0, py = s32(mul32(two_a2, ry)), p = s32((a2 >> 2) + b2 - mul32(a2, ry)), yc = ry;
  const out = [];
  const plot = (cl, ch) => { br[0] += cl; br[1] -= ch; tr[0] += cl; tr[1] += ch; bl[0] -= cl; bl[1] -= ch; tl[0] -= cl; tl[1] += ch; out.push([br[0], br[1]], [tr[0], tr[1]], [bl[0], bl[1]], [tl[0], tl[1]]); };
  let cl = 0, ch = 0;
  while (px - py < 0) {
    plot(cl, ch); cl = 1; ch = 0;
    if (p >= 0) { ch = 1; yc--; py -= two_a2; p -= py; }
    px += two_b2; p += px + b2;
  }
  let t = a2 - b2; t = t + (t >> 1);
  p += (t - px - py) >> 1;
  for (;;) {
    plot(cl, ch); cl = 0; ch = 1;
    if (p < 0) { cl = 1; px += two_b2; p += px; }
    py -= two_a2; p -= py - a2; yc--;
    if (yc < 0) break;
  }
  return out;
}
export const VIEWPORT = [11, 31, 309, 189];
const inVp = (x, y, vp) => vp[0] <= x && x <= vp[2] && vp[1] <= y && y <= vp[3];
export function ring(v, cx, cy, r, color, vp = VIEWPORT, clip = true) {
  if (P.disc) throw new Error('ring(): в профиле Вектора кольца не рисуются, только disc()');
  for (const [x, y] of ellipsePoints(cx + vp[0], cy + vp[1], r, r)) if (!clip || inVp(x, y, vp)) poke(v, (y * W + x) & 0xffff, color);
}
export function ringRestore(v, bg, cx, cy, r, vp = VIEWPORT, clip = true) {
  if (P.disc) throw new Error('ringRestore(): в профиле Вектора кольца не рисуются, только disc()');
  for (const [x, y] of ellipsePoints(cx + vp[0], cy + vp[1], r, r)) if (!clip || inVp(x, y, vp)) { const o = (y * W + x) & 0xffff; poke(v, o, peek(bg, o)); }
}

// Закрашенный круг строками: строка y — от самой левой до самой правой точки внешнего кольца радиуса r, плюс по
// точке с каждой стороны. Это ровно объединение колец i = 0..r в трёх центрах cx-1, cx, cx+1, которыми оригинал
// рисует огонь, воронку и шар грязи (проверено для r = 0..61, work/disc_check.mjs). color = null — стереть (взять из bg).
// el, er — сколько точек добавить слева и справа: 1 и 1 — три центра; 0 и 1 — два центра cx, cx+1 (гибель танка,
// work/disc2_check.mjs).
export function disc(v, bg, cx, cy, r, color, vp = VIEWPORT, el = 1, er = 1) {
  const rows = new Map();
  for (const [x, y] of ellipsePoints(cx + vp[0], cy + vp[1], r, r)) { const e = rows.get(y); if (!e) rows.set(y, [x, x]); else { if (x < e[0]) e[0] = x; if (x > e[1]) e[1] = x; } }
  for (const [y, [a, b]] of rows) {
    if (y < vp[1] || y > vp[3]) continue;
    for (let x = Math.max(a - el, vp[0]); x <= Math.min(b + er, vp[2]); x++) { const o = (y * W + x) & 0xffff; poke(v, o, color === null ? peek(bg, o) : color); }
  }
}

// ---------- обычный взрыв 318e:00e0 (оружие 1,2,3,4,11) ----------
export const RADIUS = { 1: 10, 2: 15, 3: 30, 4: 60, 11: 2 };
const K15 = 1.5, K18 = 1.7999999999992724, K07 = 0.6999999999998181;
function applyDamage(players, victim, shooter, dmg) {
  victim.shield -= dmg;
  if (victim.shield < 0) {
    if (victim.idx !== shooter && players[shooter - 1]) players[shooter - 1].score -= victim.shield * 10;   // shooter 0 — «призрак» гибели 6
    victim.men += victim.shield; victim.shield = 0;
  }
}
export function explode(v, bg, players, x, y, hit, shooter, weapon, rng, sound) {
  if (!(weapon in RADIUS)) return null;
  const r = RADIUS[weapon], cx = worldSub(x, P.X0), cy = worldSub(y, P.Y0);
  if (P.disc) disc(v, bg, cx, cy, r, P.fire(r));                    // Вектор: огонь — один закрашенный круг
  else for (let i = 0; i <= r; i++) for (const dx of [1, -1, 0]) ring(v, cx + dx, cy, i, P.fire(i));
  if (sound && rng) {
    const T = (r + 1) * (r + 2) / 2;
    for (let i = 0; i < r + 1 + 2 * T; i++) rng.word(500);
    for (let i = 0; i < T; i++) rng.word(250);
  }
  if (P.disc) disc(v, bg, cx, cy, r, null);                         // и одно стирание
  else for (let i = r; i >= 0; i--) for (const dx of [1, -1, 0]) ringRestore(v, bg, cx + dx, cy, i);
  if (isTank(hit)) applyDamage(players, players[hit - P.tank0], shooter, 200);
  for (const p of players) {
    if (!p.alive) continue;
    let dmg = 0;
    if (P.fixed) {
      const d = FX.hypot(FX.sub(x, FX.fromInt(p.x)), FX.sub(y, FX.fromInt(p.y)));
      const r15 = FX.mul(FX.fromInt(r), FX.K15), r18 = FX.mul(FX.fromInt(r), FX.K18), r07 = FX.mul(FX.fromInt(r), FX.K07);
      if (!(r15 < d)) dmg += FX.trunc(FX.sub(r18, d));
      if (FX.fromInt(r) > d) dmg += 10 + 2 * FX.trunc(FX.sub(r18, d));
      if (r07 > d) dmg += 150;
    } else {
      const ddx = x - p.x, ddy = y - p.y, d = msqrt(ddx * ddx + ddy * ddy);
      if (!(r * K15 < d)) dmg += trunc(r * K18 - d);
      if (r > d) dmg += 10 + 2 * trunc(r * K18 - d);
      if (r * K07 > d) dmg += 150;
    }
    applyDamage(players, p, shooter, dmg);
  }
  return { radius: r, cx, cy };
}

// ---------- особое оружие (scripts/ref/weapons.py) ----------
const atv = (v, x, y) => (x >= 0 && x < W && y >= 0 && y < H) ? v[y * W + x] : 0;
const pixBg = (v, bg, x, y) => { if (x >= 0 && x < W && y >= 0 && y < H) { const o = y * W + x; v[o] = bg[o]; } };
function ellipseRestoreVp(v, bg, x, y, rx, ry, vp, clip) {
  const cx = x + vp[0], cy = y + vp[1];
  const inside = !clip || (vp[0] <= cx - rx && cx + rx <= vp[2] && vp[1] <= cy - ry && cy + ry <= vp[3]);
  for (const [px, py] of ellipsePoints(cx, cy, rx, ry)) if (inside || inVp(px, py, vp)) pixBg(v, bg, px, py);
}
export function sonic(v, bg, x, y, rng, sound, vp = VIEWPORT, clip = true) {   // 12
  for (let i = 0; i < 100; i++) { rng.word(64); if (sound) rng.word(1000); }
  for (let i = 0; i < 100; i++) { rng.word(64); rng.word(64); if (sound) rng.word(1000); }
  const ix = world(x), iy = world(y);
  ellipseRestoreVp(v, bg, ix, iy, 1, 1, vp, clip);
  pixBg(v, bg, ix, iy);
  crumble(v, bg);
}
const CRI_RADIUS = { 5: 4, 6: 4, 7: 8, 8: 8, 9: 20, 10: 20 }, CRI_FLUENT = new Set([6, 8, 10]);
const DIR = { 1: [0, -1], 2: [1, -1], 3: [1, 0], 4: [1, 1], 5: [0, 1], 6: [-1, 1], 7: [-1, 0], 8: [-1, -1] };
export function cri(v, bg, players, x, y, hit, shooter, weapon, rng, sound) {      // 6..10
  if (!(weapon in CRI_RADIUS)) return;
  if (isTank(hit)) {          // 318e:091c — урон со щита, перелив в men (16 бит) и очки
    const dmg = rng.word(weapon * 6) + 1, vic = players[hit - P.tank0];
    vic.shield -= dmg;
    if (vic.shield < 0) {
      vic.men = ((vic.men + (vic.shield & 0xffff)) << 16) >> 16;
      if (vic.idx !== shooter && shooter >= 1 && shooter <= players.length) players[shooter - 1].score -= vic.shield * 10;
      vic.shield = 0;
    }
    return;
  }
  if (hit !== P.ground) return;
  const radius = CRI_RADIUS[weapon], fluent = CRI_FLUENT.has(weapon);
  let cx = world(x), cy = world(y);
  while (![[-1, 0], [1, 0], [0, -1], [0, 1]].some(([dx, dy]) => atv(v, cx + dx, cy + dy) === P.ground)) cy++;
  const pts = Array.from({ length: 22 }, () => [0, 0]);
  for (let i = 1; i <= radius; i++) pts[i] = [cx, cy];
  for (;;) {
    for (let i = 1; i <= radius; i++) {
      const dirs = [], [px, py] = pts[i];
      for (let d = 1; d <= 8; d++) { if (d % 2 === 0 && !fluent) continue; const [dx, dy] = DIR[d]; if (atv(v, px + dx, py + dy) === P.ground) dirs.push(d); }
      if (dirs.length) {
        const d = dirs[rng.word(dirs.length)], [dx, dy] = DIR[d], nx = px + dx, ny = py + dy;
        pts[i] = [nx, ny]; if (sound) rng.word(500); pixBg(v, bg, nx, ny);
      } else pts[i] = [0, 0];
    }
    let dead = 0;
    for (let i = 1; i <= radius; i++) {
      if (pts[i][0] !== 0) continue;
      dead++; let j = 0;
      for (;;) { j++; if ((j !== i && j <= 21 && pts[j][0] !== 0) || j === 21) break; }
      if (j === 21) j = i;
      pts[i] = pts[j];
    }
    if (dead === radius) return;
  }
}
const DIRT_RADIUS = { 13: 10, 14: 15, 15: 30, 16: 60 };
export function dirtBall(v, x, y, weapon, vp = VIEWPORT) {                         // 13..16
  const r = DIRT_RADIUS[weapon];
  let cy, centers;
  if (P.fixed) {
    const base = FX.sub(x, FX.fromInt(vp[0]));
    cy = worldSub(y, vp[1]);
    centers = [FX.trunc(FX.add(base, FX.ONE)), FX.trunc(FX.sub(base, FX.ONE)), FX.trunc(base)];
  } else {
    const lx = x - vp[0], ly = y - vp[1];
    cy = trunc(ly);
    centers = [trunc(lx + 1), trunc(lx - 1), trunc(lx)];
  }
  if (P.disc) disc(v, null, centers[2], cy, r, P.ground, vp);
  else for (let i = 0; i <= r; i++) for (const cx of centers) ring(v, cx, cy, i, P.ground, vp);
}
export function explosiveDirt(v, bg, x, y, rng, sound, percent, vp = VIEWPORT) {   // 17
  const n = rng.word(100) + 300, rows = rng.word(8) + 3;
  const tx = worldSub(x, vp[0]), ty = worldSub(y, vp[1]), pts = [];
  for (let row = 1; row <= rows; row++) for (let c = 0; c < n; c++) {
    const span = rng.word(row * 10);
    const jitter = P.fixed ? FX.truncSubHalf(rng.word(span + 1), span) : trunc(rng.word(span + 1) - span / 2.0);
    pts.push([tx + jitter, ty - span + 2]);
  }
  for (const [px, py] of pts) {
    if (vp[0] <= px + vp[0] && px + vp[0] <= vp[2] && vp[1] <= py + vp[1] && py + vp[1] <= vp[3]) { const X = px + vp[0], Y = py + vp[1]; if (X >= 0 && X < W && Y >= 0 && Y < H) v[Y * W + X] = P.ground; }
    if (sound) rng.word(200);
  }
  if (P.fixed ? FX.rndLtRatio(rng, percent * 2, 100) : rng.real() * 100.0 < percent * 2) crumble(v, bg);
}

// Laser 2583:140f..24c5 (оружие 5). shooter — объект танка; players — массив танков.
const LASER_P = 0.20000000000004547;
const inField = (x, y) => x >= P.X0 && x <= P.X1 && y >= P.Y0 && y <= P.Y1;
function trigOf(a) { return TRIG[a in TRIG ? a : ((a % 360) + 360) % 360]; }
function laserFix(v, bg, players, shooterIdx, rng, sound, rebound) {
  const t = players[shooterIdx - 1];
  const BEAM = P.beam;
  let power = t.power; if (power === 0) return;
  if (power > t.energy) { power = t.energy; t.power = power; }
  t.energy -= power;
  const [bdx, bdy] = barrelOf(t.angle);
  line(v, t.x, t.y, t.x + bdx * t.facing, t.y - bdy, BEAM);
  drawTank(v, t.x, t.y, tankColor(shooterIdx));
  let counter = 10 * power;
  const eff = t.facing > 0 ? t.angle : 180 - t.angle;
  if (FX.rndLt(rng, FX.TH.p20)) t.men -= 1;
  const [ca, sa] = FX.sincos(t.angle | 0);
  let X = FX.add(FX.fromInt(t.x), FX.mulInt(FX.mulInt(ca, 7), t.facing | 0));
  let Y = FX.sub(FX.fromInt(t.y), FX.mulInt(sa, 7));
  let [dx, dy] = FX.sincos(eff | 0);
  if (dy !== 0) dy = FX.neg(dy);
  const vget = (x, y) => peek(v, off16(x, y));
  const gp = (x, y) => (x >= 0 && x < W && y >= 0 && y < H) ? vget(x, y) : 0;
  const x0 = FX.fromInt(P.X0), x1 = FX.fromInt(P.X1), y0 = FX.fromInt(P.Y0), y1 = FX.fromInt(P.Y1);
  for (;;) {
    let done = false;
    X = FX.add(X, dx); Y = FX.add(Y, dy); counter -= 10;
    const c = vget(FX.trunc(X), FX.trunc(Y));
    if (c === P.ground) {
      for (let k = 1; k <= 15; k++) {
        const gx = FX.trunc(FX.sub(X, FX.mulInt(dx, rng.word(20)))), gy = FX.trunc(FX.sub(Y, FX.mulInt(dy, rng.word(20))));
        if (sound) rng.word((500 * k) & 0xffff);
        const gc = gp(gx, gy);
        if (inField(gx, gy) && !isTank(gc) && gc !== BEAM) poke(v, off16(gx, gy), bg[off16(gx, gy)]);
      }
    }
    if (isTank(c) && players[c - P.tank0] && players[c - P.tank0].men > 0) {
      counter -= 10;
      const vic = players[c - P.tank0];
      if (vic.shield <= 0) {
        const pts = [];
        for (let k = 1; k <= 15; k++) {
          let sx, sy;
          for (;;) {
            sx = FX.trunc(FX.add(FX.sub(X, FX.fromInt(rng.word(40))), FX.fromInt(20)));
            sy = FX.trunc(FX.add(FX.sub(Y, FX.fromInt(rng.word(40))), FX.fromInt(20)));
            const gc = gp(sx, sy);
            if (gc === c || (!isTank(gc) && gc !== BEAM)) break;
          }
          pts.push([sx, sy]);
          if (sound) rng.word((500 * k) & 0xffff);
          if (inField(sx, sy)) poke(v, off16(sx, sy), c);
        }
        pts.forEach(([sx, sy], i) => { if (sound) rng.word((500 * (i + 1)) & 0xffff); if (inField(sx, sy)) poke(v, off16(sx, sy), bg[off16(sx, sy)]); });
      }
      let sh = vic.shield - 3;
      if (sh < 0) { vic.men += sh; sh = 0; }
      vic.shield = sh;
      X = FX.sub(X, dx); Y = FX.sub(Y, dy);
    }
    if (sound) rng.word((12 * counter) & 0xffff);
    if (counter <= 0) done = true;
    if (rebound) {
      if (dx < 0 && X <= x0 && dx !== 0) dx = FX.neg(dx);
      if (dx > 0 && X >= x1 && dx !== 0) dx = FX.neg(dx);
      if (dy < 0 && Y <= y0 && dy !== 0) dy = FX.neg(dy);
      if (dy > 0 && Y >= y1 && dy !== 0) dy = FX.neg(dy);
    } else if ((dx < 0 && X <= x0) || (dx > 0 && X >= x1) || (dy < 0 && Y <= y0) || (dy > 0 && Y >= y1)) done = true;
    if (!done) poke(v, off16(FX.trunc(X), FX.trunc(Y)), BEAM);
    if (counter <= 0) done = true;
    if (done) break;
  }
  for (let o = SCREEN; o > 0; o--) if (o < v.length && v[o] === BEAM) v[o] = bg[o];
}
export function laser(v, bg, players, shooterIdx, rng, sound, rebound = false) {
  if (P.fixed) return laserFix(v, bg, players, shooterIdx, rng, sound, rebound);
  const t = players[shooterIdx - 1];
  const BEAM = P.beam;
  let power = t.power; if (power === 0) return;
  if (power > t.energy) { power = t.energy; t.power = power; }
  t.energy -= power;
  const [bdx, bdy] = barrelOf(t.angle);
  line(v, t.x, t.y, t.x + bdx * t.facing, t.y - bdy, BEAM);
  drawTank(v, t.x, t.y, tankColor(shooterIdx));
  let counter = 10 * power;
  const eff = t.facing > 0 ? t.angle : 180 - t.angle;
  if (rng.real() < LASER_P) t.men -= 1;
  const [ca, sa] = trigOf(t.angle);
  let X = q(t.x + q(q(ca * 7) * t.facing)), Y = q(t.y - q(sa * 7));
  let [dx, dy] = trigOf(eff); dy = dy !== 0 ? -dy : dy;
  const vget = (x, y) => peek(v, off16(x, y));
  const gp = (x, y) => (x >= 0 && x < W && y >= 0 && y < H) ? vget(x, y) : 0;
  for (;;) {
    let done = false;
    X = q(X + dx); Y = q(Y + dy); counter -= 10;
    const c = vget(trunc(X), trunc(Y));
    if (c === P.ground) {
      for (let k = 1; k <= 15; k++) {
        const gx = trunc(q(X - q(rng.word(20) * dx))), gy = trunc(q(Y - q(rng.word(20) * dy)));
        if (sound) rng.word((500 * k) & 0xffff);
        const gc = gp(gx, gy);
        if (inField(gx, gy) && !isTank(gc) && gc !== BEAM) poke(v, off16(gx, gy), bg[off16(gx, gy)]);
      }
    }
    if (isTank(c) && players[c - P.tank0] && players[c - P.tank0].men > 0) {
      counter -= 10;
      const vic = players[c - P.tank0];
      if (vic.shield <= 0) {
        const pts = [];
        for (let k = 1; k <= 15; k++) {
          let sx, sy;
          for (;;) {
            sx = trunc(q(q(X - rng.word(40)) + 20)); sy = trunc(q(q(Y - rng.word(40)) + 20));
            const gc = gp(sx, sy);
            if (gc === c || (!isTank(gc) && gc !== BEAM)) break;
          }
          pts.push([sx, sy]);
          if (sound) rng.word((500 * k) & 0xffff);
          if (inField(sx, sy)) poke(v, off16(sx, sy), c);
        }
        pts.forEach(([sx, sy], i) => { if (sound) rng.word((500 * (i + 1)) & 0xffff); if (inField(sx, sy)) poke(v, off16(sx, sy), bg[off16(sx, sy)]); });
      }
      let sh = vic.shield - 3;
      if (sh < 0) { vic.men += sh; sh = 0; }
      vic.shield = sh;
      X = q(X - dx); Y = q(Y - dy);
    }
    if (sound) rng.word((12 * counter) & 0xffff);
    if (counter <= 0) done = true;
    if (rebound) {
      if (dx < 0 && X <= P.X0 && dx !== 0) dx = -dx;
      if (dx > 0 && X >= P.X1 && dx !== 0) dx = -dx;
      if (dy < 0 && Y <= P.Y0 && dy !== 0) dy = -dy;
      if (dy > 0 && Y >= P.Y1 && dy !== 0) dy = -dy;
    } else if ((dx < 0 && X <= P.X0) || (dx > 0 && X >= P.X1) || (dy < 0 && Y <= P.Y0) || (dy > 0 && Y >= P.Y1)) done = true;
    if (!done) poke(v, off16(trunc(X), trunc(Y)), BEAM);
    if (counter <= 0) done = true;
    if (done) break;
  }
  for (let o = SCREEN; o > 0; o--) if (o < v.length && v[o] === BEAM) v[o] = bg[o];
}

// ---------- полёт снаряда 2583:01c0 (+ наведение 2583:06cf) ----------
const PI48 = real48ToFloat(new Uint8Array([0x82, 0x21, 0xa2, 0xda, 0x0f, 0x49]));
const D180 = real48ToFloat(new Uint8Array([0x88, 0x00, 0x00, 0x00, 0x00, 0x34]));
export const degToRad = (d) => q(q(q(d) / D180) * PI48);
const DIAMOND = [[-1, 0], [0, -1], [0, 0], [0, 1], [1, 0]];
const isHit = (c) => c === P.ground || isTank(c);
const HERB = 1.0100000000002183;
// Q16.16-полёт. Тяжесть и ветер — рациональный аккумулятор (среднее точно 0.01 и wind/50000).
function muzzleFix(inp) {
  const [c, s] = FX.sincos(inp.angle | 0);
  const facing = inp.facing | 0;
  const x = FX.add(FX.fromInt(inp.tank_x), FX.mulInt(FX.mulInt(c, 10), facing));
  const y = FX.sub(FX.fromInt(inp.tank_y), FX.mulInt(s, 10));
  const speed = FX.idiv(FX.fromInt(inp.power), 50);
  let vx = FX.mulInt(FX.mul(speed, c), facing);
  let vy = FX.mul(speed, s);
  if (vy !== 0) vy = FX.neg(vy);
  return { x, y, vx, vy };
}
function guideFix(x, y, vx, vy, guided, target) {
  const tdx = FX.sub(FX.fromInt(target[0]), x), tdy = FX.sub(FX.fromInt(target[1]), y);
  if ((guided === 2 || guided === 3) && FX.abs(tdx) <= 2 * FX.ONE) {
    vx = 0; y = tdy > 0 ? FX.add(y, FX.VX0) : FX.sub(y, FX.VX0);
  }
  if ((guided === 1 || guided === 3) && FX.abs(tdy) <= 2 * FX.ONE) {
    vy = 0;
    const prod = FX.mul(tdx, vx);
    vx = FX.mul(vx, prod >= 0 ? FX.HERB : -FX.HERB);
  }
  return { x, y, vx, vy };
}
function inBandFix(x, y) {
  return y < FX.fromInt(P.Y1) && x < FX.fromInt(P.X1) && y > FX.fromInt(P.Y0 + 2) && x > FX.fromInt(P.X0);
}
function reflectFix(x, y, vx, vy) {
  if (vx < 0 && x < FX.fromInt(P.X0 - 1)) vx = FX.neg(vx);
  if (vx > 0 && x > FX.fromInt(P.X1 + 1)) vx = FX.neg(vx);
  if (vy < 0 && y < FX.fromInt(P.Y0 - 1)) vy = FX.neg(vy);
  if (vy > 0 && y > FX.fromInt(P.Y1 + 1)) vy = FX.neg(vy);
  return { vx, vy };
}
function stepFix(x, y, vx, vy, gRem, wRem, wind) {
  x = FX.add(x, FX.idiv(vx, 10));
  y = FX.add(y, FX.idiv(vy, 10));
  let g; [gRem, g] = FX.dda(gRem, FX.G_INC, FX.G_DEN); vy = FX.add(vy, g);
  let w; [wRem, w] = FX.dda(wRem, (wind || 0) * FX.W_MUL, FX.W_DEN); vx = FX.add(vx, w);
  return { x, y, vx, vy, gRem, wRem };
}
function flightFix(inp, getPixel, onStep) {
  let { x, y, vx, vy } = muzzleFix(inp);
  const fuse = 1000 - 2 * (inp.men ?? 5);
  const guided = inp.guided || 0;
  let sub = 1, hit = 0, stop = 'max', gRem = 0, wRem = 0;
  const positions = [], wind = inp.wind || 0;
  for (let i = 0; i < (inp.maxSteps || 20000); i++) {
    sub++; if (sub > 10) sub = 0;
    ({ x, y, vx, vy, gRem, wRem } = stepFix(x, y, vx, vy, gRem, wRem, wind));
    if (guided && inp.target) ({ x, y, vx, vy } = guideFix(x, y, vx, vy, guided, inp.target));
    const px = FX.trunc(x), py = FX.trunc(y);
    positions.push([px, py]);
    if (onStep) onStep(px, py, x / FX.ONE, y / FX.ONE);
    if (inBandFix(x, y)) {
      hit = 0; let stopped = false;
      for (const [dx, dy] of DIAMOND) {
        const cp = getPixel(px + dx, py + dy);
        if (!isHit(cp)) continue;
        hit = cp;
        const tank = isTank(cp);
        let st = tank || sub === 10 || inp.power < fuse;
        if (cp === P.ground && inp.power === fuse) st = false;
        if (st) {
          if (tank && inp.weapon >= 12 && inp.weapon <= 16) vy = FX.mul(FX.neg(vy), FX.K12);
          else { stop = tank ? 'tank' : 'terrain'; stopped = true; break; }
        }
      }
      if (stopped) break;
    } else if (inp.rebound) {
      ({ vx, vy } = reflectFix(x, y, vx, vy));
    } else if (!guided) {
      if (vx > FX.ONE && x > FX.fromInt(P.X1 + 1) && wind > 0) y = FX.fromInt(P.Y1 + 11);
      if (vx < FX.ONE && x < FX.fromInt(P.X0 - 1) && wind < 0) y = FX.fromInt(P.Y1 + 11);
    }
    if (y < FX.fromInt(-5000) || y > FX.fromInt(P.Y1 + 4)) { stop = 'bounds'; break; }
  }
  return { positions, stop, hit, x, y };
}
function flightDrawFix(v, bg, inp, shooter, ballVisible, trail, players, onFrame) {
  let { x, y, vx, vy } = muzzleFix(inp);
  const fuse = 1000 - 2 * inp.men;
  let sub = players, pxPrev = FX.fromInt(-99), pyPrev = pxPrev, guided = inp.guided || 0;
  let gRem = 0, wRem = 0;
  const wind = inp.wind || 0;
  const tcol = P.trail ? P.trail(shooter) : 0;
  if (!P.trail) trail = false;
  const get = (X, Y) => (X >= 0 && X < W && Y >= 0 && Y < H ? v[Y * W + X] : 0);
  for (let i = 0; i < (inp.maxSteps || 200000); i++) {
    sub++; if (sub > 10) sub = 0;
    ({ x, y, vx, vy, gRem, wRem } = stepFix(x, y, vx, vy, gRem, wRem, wind));
    if (guided && inp.target) ({ x, y, vx, vy } = guideFix(x, y, vx, vy, guided, inp.target));
    if (pxPrev < FX.fromInt(P.X1) && pyPrev > FX.fromInt(P.Y0) && pxPrev > FX.fromInt(P.X0)) {
      const ix = FX.trunc(pxPrev), iy = FX.trunc(pyPrev);
      if (ballVisible) cross(v, bg, ix, iy);
      if (trail) { const o = off16(ix, iy); v[o] = tcol; bg[o] = tcol; }
    }
    pxPrev = x; pyPrev = y;
    const px = FX.trunc(x), py = FX.trunc(y);
    let stop = null, hit = 0;
    if (inBandFix(x, y)) {
      let done = false;
      for (const [dx, dy] of DIAMOND) {
        const cp = get(px + dx, py + dy);
        if (!isHit(cp)) continue;
        hit = cp;
        const tank = isTank(cp);
        if (tank || sub === 10 || inp.power < fuse) done = true;
        if (cp === P.ground && inp.power === fuse) done = false;
        if (tank && inp.weapon >= 12 && inp.weapon <= 16) { done = false; vy = FX.mul(FX.neg(vy), FX.K12); guided = 0; }
      }
      if (done) stop = isTank(hit) ? 'tank' : 'terrain';
    } else if (inp.rebound) {
      ({ vx, vy } = reflectFix(x, y, vx, vy));
    } else if (!guided) {
      if (vx > FX.ONE && x > FX.fromInt(P.X1 + 1) && wind > 0) y = FX.fromInt(P.Y1 + 11);
      if (vx < FX.ONE && x < FX.fromInt(P.X0 - 1) && wind < 0) y = FX.fromInt(P.Y1 + 11);
    }
    if (stop === null && (y < FX.fromInt(-5000) || y > FX.fromInt(P.Y1 + 4))) stop = 'bounds';
    if (stop !== null) {
      if (y > 0 && y < FX.fromInt(H) && x > 0 && x < FX.fromInt(W)) cross(v, bg, FX.trunc(x), FX.trunc(y));
      return { stop, x, y, hit };
    }
    if (ballVisible && x < FX.fromInt(P.X1) && y > FX.fromInt(P.Y0) && x > FX.fromInt(P.X0)) cross(v, null, px, py, P.ball);
    if (onFrame) onFrame(px, py);
  }
  return { stop: 'max', x, y, hit: 0 };
}
export function flight(inp, getPixel, onStep = null) {
  if (P.fixed) {
    const r = flightFix(inp, getPixel, onStep);
    r.x /= FX.ONE; r.y /= FX.ONE;
    return r;
  }
  // inp: angle, power, facing, tank_x, tank_y, wind, rebound, weapon, guided, men, target:[x,y]
  const [c, s] = trigOf(inp.angle);
  let x = q(q(inp.tank_x) + q(q(c * 10) * inp.facing));
  let y = q(q(inp.tank_y) - q(s * 10));
  let vx = q(q(q(inp.power / 50) * c) * inp.facing);
  let vy = q(q(inp.power / 50) * s);
  if (vy !== 0) vy = q(-vy);
  const step = 10, fuse = 1000 - 2 * (inp.men ?? 5), guided = inp.guided || 0;
  let sub = 1, hit = 0, stop = 'max';
  const positions = [];
  for (let i = 0; i < (inp.maxSteps || 20000); i++) {
    sub++; if (sub > step) sub = 0;
    x = q(x + q(vx / step)); y = q(y + q(vy / step));
    vy = q(vy + q(0.1 / step)); vx = q(vx + q(q((inp.wind || 0) / 5000) / step));
    if (guided && inp.target) {
      const tdx = q(q(inp.target[0]) - x), tdy = q(q(inp.target[1]) - y);
      if ((guided === 2 || guided === 3) && Math.abs(tdx) <= 2) { vx = q(0); y = tdy > 0 ? q(y + 0.5) : q(y - 0.5); }
      if ((guided === 1 || guided === 3) && Math.abs(tdy) <= 2) { vy = q(0); const prod = q(tdx * vx); vx = q(vx * (prod >= 0 ? HERB : -HERB)); }
    }
    const px = trunc(x), py = trunc(y);
    positions.push([px, py]);
    if (onStep) onStep(px, py, x, y);
    const inBand = y < P.Y1 && x < P.X1 && y > P.Y0 + 2 && x > P.X0;
    if (inBand) {
      hit = 0; let stopped = false;
      for (const [dx, dy] of DIAMOND) {
        const cp = getPixel(px + dx, py + dy);
        if (isHit(cp)) {
          hit = cp;
          const tank = isTank(cp);
          let st = tank || sub === step || inp.power < fuse;
          if (cp === P.ground && inp.power === fuse) st = false;
          if (st) {
            if (tank && inp.weapon >= 12 && inp.weapon <= 16) vy = q(-vy * 1.2);
            else { stop = tank ? 'tank' : 'terrain'; stopped = true; break; }
          }
        }
      }
      if (stopped) break;
    } else if (inp.rebound) {
      if (vx < 0 && x < P.X0 - 1) vx = q(-vx); if (vx > 0 && x > P.X1 + 1) vx = q(-vx);
      if (vy < 0 && y < P.Y0 - 1) vy = q(-vy); if (vy > 0 && y > P.Y1 + 1) vy = q(-vy);
    } else if (!guided) {
      if (vx > 1 && x > P.X1 + 1 && inp.wind > 0) y = P.Y1 + 11;
      if (vx < 1 && x < P.X0 - 1 && inp.wind < 0) y = P.Y1 + 11;
    }
    if (y < -5000 || y > P.Y1 + 4) { stop = 'bounds'; break; }
  }
  return { positions, stop, hit, x, y };
}

// ---------- ветер на раунд (2583:2567..2675) ----------
const SPANS = [0, 20, 100, 300, 4000], WTHR = [0.1, 0.1, 0.05, 0.05].map(q);
export function generateWind(rng, mode) {
  let eff = mode === 5 ? rng.word(5) : mode;
  const span = SPANS[eff] || 0;
  let w = ((span >> 1) - rng.word(span)) << 16 >> 16;
  const THW = [FX.TH.p10, FX.TH.p10, FX.TH.p05, FX.TH.p05];
  for (let i = 0; i < WTHR.length; i++) if (P.fixed ? FX.rndLt(rng, THW[i]) : rng.real() < WTHR[i]) w = ((w << 2) & 0xffff) << 16 >> 16;
  return Math.max(-30000, Math.min(30000, w));
}

// =====================================================================================================
// T05: игрок, ход целиком, гибель, фоны, начало раунда, ИИ, матч (scripts/ref/{game,death,background,ai,match}.py)
// =====================================================================================================

// ---------- игрок: запись 0x61 байт от DS:3EFC + 0x61*i ----------
export class Player {
  constructor(idx) {
    Object.assign(this, { idx, name: 'Player ' + idx, x: 0, y: 0, score: 0, spent: 0, wins: 0, power: 200, angle: 90, facing: 1,
      men: 100, alive: true, weapon: 1, guided: 0, target: 0, herb: 0, vick: 0, ammo: new Array(18).fill(0), shield: 0, damp: 0,
      colors: [1, 1, 1], ctrl: 1, hist: newHist(), strategy: 0 });
  }
  get energy() { return this.ammo[5]; }           // энергия лазера — это запас оружия 5 (+0x2B)
  set energy(v) { this.ammo[5] = v; }
}
const i16 = (v) => (v << 16) >> 16;
// b — Uint8Array записи; base = 0 (от DS:3EFC) или 0x0E (от DS:3EEE, тогда читается имя)
export function playerFromRec(b, idx, base = 0) {
  const dv = new DataView(b.buffer, b.byteOffset, b.byteLength), w = (o) => dv.getInt16(base + o, true), l = (o) => dv.getInt32(base + o, true);
  const p = new Player(idx);
  if (base) p.name = String.fromCharCode(...b.subarray(1, 1 + b[0]));
  Object.assign(p, { x: w(0), y: w(2), score: l(4), spent: l(8), wins: w(0x0c), power: w(0x0e), angle: w(0x10), facing: w(0x12),
    men: w(0x14), alive: b[base + 0x16] !== 0, weapon: w(0x17), guided: w(0x19), target: w(0x1b), herb: w(0x1d), vick: w(0x1f),
    shield: l(0x45), damp: l(0x49), colors: [w(0x4d), w(0x4f), w(0x51)] });
  for (let k = 0; k < 18; k++) p.ammo[k] = w(0x21 + 2 * k);
  return p;
}
// 32ec:02b9 — новый игрок матча
const COLOR_DIV = [[1, 0x7fff, 0x7fff], [0x7fff, 1, 0x7fff], [0x7fff, 0x7fff, 1], [1, 1, 0x7fff], [0x7fff, 1, 1], [1, 0x7fff, 1], [1, 1, 1], [1, 2, 0x7fff], [1, 0x7fff, 2], [1, 2, 2]];
export function newPlayer(idx, rounds) {
  const p = new Player(idx);
  p.ammo[0] = 100; p.ammo[1] = rounds * 3; p.ammo[11] = Math.min(999, rounds * 10);
  p.colors = (P.playerColors || COLOR_DIV)[idx - 1].slice();
  return p;
}
// 1062:07a9 — цвет танка в палитре (0..63 на компонент)
// Вектор: цвет танка в единицах палитры R3 G3 B2. Яркость по здоровью с нижним порогом, чтобы живой танк
// не пропадал на чёрном фоне (правило оригинала после обрезки до 3 бит давало чёрный уже при men ≤ 12):
// R и G: 3 + men·4 div 100 (3..7), B: 1 + men·2 div 100 (1..3); компонента есть, если её делитель в записи равен 1.
export function tankPalV06C(p) {
  if (p.men <= 0) return [0, 0, 0];
  const m = Math.min(p.men, 100), rg = 3 + trunc(m * 4 / 100), b = 1 + trunc(m * 2 / 100);
  return [p.colors[0] === 1 ? rg : 0, p.colors[1] === 1 ? rg : 0, p.colors[2] === 1 ? b : 0];
}
export function tankRGB(p) { if (p.men < 0) return [0, 0, 0]; const L = trunc(p.men * 63 / 100); return p.colors.map((d) => trunc(L / d)); }

// ---------- полёт с отрисовкой мяча и следа (2583:01c0) ----------
const K12 = real48ToFloat(new Uint8Array([0x81, 0x9a, 0x99, 0x99, 0x99, 0x19]));
const CROSS = [[0, 0], [0, 1], [0, -1], [1, 0], [-1, 0]];
export function cross(v, src, x, y, color = null) {
  const b = off16(x, y);
  for (const [dx, dy] of CROSS) { const o = (b + dy * W + dx) & 0xffff; if (o < v.length) v[o] = color !== null ? color : (o < src.length ? src[o] : 0); }
}
// inp: angle, power, facing, tank_x, tank_y, wind, rebound, weapon, men, guided, target:[x,y]; onFrame(x, y) — для анимации
export function flightDraw(v, bg, inp, shooter, ballVisible, trail, players = 1, onFrame = null) {
  if (P.fixed) {
    const r = flightDrawFix(v, bg, inp, shooter, ballVisible, trail, players, onFrame);
    r.x /= FX.ONE; r.y /= FX.ONE;
    return r;
  }
  const [c, s] = trigOf(inp.angle);
  let x = q(q(inp.tank_x) + q(q(c * 10) * inp.facing)), y = q(q(inp.tank_y) - q(s * 10));
  let vx = q(q(q(inp.power / 50) * c) * inp.facing), vy = q(q(inp.power / 50) * s);
  if (vy !== 0) vy = q(-vy);
  const step = 10, fuse = 1000 - 2 * inp.men;
  let sub = players, pxPrev = -99, pyPrev = -99, guided = inp.guided || 0;     // DS:3EAC перед полётом = число игроков
  const tcol = P.trail ? P.trail(shooter) : 0;
  if (!P.trail) trail = false;
  const get = (X, Y) => (X >= 0 && X < W && Y >= 0 && Y < H ? v[Y * W + X] : 0);
  for (let i = 0; i < (inp.maxSteps || 200000); i++) {
    sub++; if (sub > step) sub = 0;
    x = q(x + q(vx / step)); y = q(y + q(vy / step));
    vy = q(vy + q(0.1 / step)); vx = q(vx + q(q((inp.wind || 0) / 5000) / step));
    if (guided && inp.target) {                       // 2583:06cf (в составе хода исполнением не сверено)
      const tdx = q(q(inp.target[0]) - x), tdy = q(q(inp.target[1]) - y);
      if ((guided === 2 || guided === 3) && Math.abs(tdx) <= 2) { vx = q(0); y = tdy > 0 ? q(y + 0.5) : q(y - 0.5); }
      if ((guided === 1 || guided === 3) && Math.abs(tdy) <= 2) { vy = q(0); const prod = q(tdx * vx); vx = q(vx * (prod >= 0 ? HERB : -HERB)); }
    }
    if (pxPrev < P.X1 && pyPrev > P.Y0 && pxPrev > P.X0) {
      const ix = trunc(pxPrev), iy = trunc(pyPrev);
      if (ballVisible) cross(v, bg, ix, iy);
      if (trail) { const o = off16(ix, iy); v[o] = tcol; bg[o] = tcol; }
    }
    pxPrev = x; pyPrev = y;
    const px = trunc(x), py = trunc(y);
    let stop = null, hit = 0;
    if (y < P.Y1 && x < P.X1 && y > P.Y0 + 2 && x > P.X0) {
      let done = false;                               // ромб обходится целиком (2583:0c52..0e1d)
      for (const [dx, dy] of DIAMOND) {
        const cp = get(px + dx, py + dy);
        if (!isHit(cp)) continue;
        hit = cp;
        const tank = isTank(cp);
        if (tank || sub === step || inp.power < fuse) done = true;
        if (cp === P.ground && inp.power === fuse) done = false;
        if (tank && inp.weapon >= 12 && inp.weapon <= 16) { done = false; vy = q(q(-vy) * K12); guided = 0; }
      }
      if (done) stop = isTank(hit) ? 'tank' : 'terrain';
    } else if (inp.rebound) {
      if (vx < 0 && x < P.X0 - 1) vx = q(-vx); if (vx > 0 && x > P.X1 + 1) vx = q(-vx);
      if (vy < 0 && y < P.Y0 - 1) vy = q(-vy); if (vy > 0 && y > P.Y1 + 1) vy = q(-vy);
    } else if (!guided) {
      if (vx > 1 && x > P.X1 + 1 && inp.wind > 0) y = P.Y1 + 11;
      if (vx < 1 && x < P.X0 - 1 && inp.wind < 0) y = P.Y1 + 11;
    }
    if (stop === null && (y < -5000 || y > P.Y1 + 4)) stop = 'bounds';
    if (stop !== null) {
      if (y > 0 && y < H && x > 0 && x < W) cross(v, bg, trunc(x), trunc(y));
      return { stop, x, y, hit };
    }
    if (ballVisible && x < P.X1 && y > P.Y0 && x > P.X0) cross(v, null, px, py, P.ball);
    if (onFrame) onFrame(px, py);
  }
  return { stop: 'max', x, y, hit: 0 };
}

// ---------- эффект оружия 318e:00e0 и выстрел ----------
function effect(v, bg, ps, shooter, x, y, hit, rng, fl) {
  const w = ps[shooter - 1].weapon;
  if (w in RADIUS) explode(v, bg, ps, x, y, hit, shooter, w, rng, fl.sound);
  else if (w >= 6 && w <= 10) cri(v, bg, ps, x, y, hit, shooter, w, rng, fl.sound);
  else if (w === 12) sonic(v, bg, x, y, rng, fl.sound);
  else if (w >= 13 && w <= 16) dirtBall(v, x, y, w);
  else if (w === 17) explosiveDirt(v, bg, x, y, rng, fl.sound, fl.crumble);
}
// fl: {rebound, crumble, fall, xkill, sound, wind, ballVisible, trail}. Возвращает точку остановки снаряда (или null у лазера).
export function fire(v, bg, ps, shooter, rng, fl, onFrame = null) {
  const s = ps[shooter - 1];
  if (s.weapon === 5) { laser(v, bg, ps, shooter, rng, fl.sound, fl.rebound); return null; }
  s.ammo[s.weapon] = i16(s.ammo[s.weapon] - 1);       // 2583:02f1
  if (s.guided === 1 || s.guided === 3) s.herb--;
  if (s.guided === 2 || s.guided === 3) s.vick--;
  if (P.fixed ? FX.rndLt(rng, FX.TH.p20) : rng.real() < LASER_P) s.men -= 1;   // 2583:0348
  const t = s.guided && ps[s.target - 1] ? ps[s.target - 1] : null;
  const inp = { angle: s.angle, power: s.power, facing: s.facing, tank_x: s.x, tank_y: s.y, wind: fl.wind,
    rebound: fl.rebound, weapon: s.weapon, men: s.men, guided: t ? s.guided : 0, target: t ? [t.x, t.y] : null };
  // В fixed effect получает raw Q16.16, наружу координаты переводятся в точки.
  const r = P.fixed ? flightDrawFix(v, bg, inp, shooter, fl.ballVisible, fl.trail, ps.length, onFrame)
    : flightDraw(v, bg, inp, shooter, fl.ballVisible, fl.trail, ps.length, onFrame);
  if (r.stop === 'terrain' || r.stop === 'tank') effect(v, bg, ps, shooter, r.x, r.y, r.hit, rng, fl);
  if (P.fixed) { r.x /= FX.ONE; r.y /= FX.ONE; }
  return r;
}

// ---------- гибель танка (оверлей 285c), вариант Random(7) ----------
export function eraseTankBarrel(v, bg, t) { eraseTank(v, bg, t.x, t.y); const [bdx, bdy] = barrelOf(t.angle); line(v, t.x, t.y, t.x + bdx * t.facing, t.y - bdy, 0, bg); }
const redrawAll = (v, ts) => { for (const t of ts) drawTankBarrel(v, t); };
const gpVp = (v, x, y) => { const X = x + P.X0, Y = y + P.Y0; return X >= 0 && X < W && Y >= 0 && Y < H ? v[Y * W + X] : 0; };
const ppVp = (v, x, y, c) => { const X = x + P.X0, Y = y + P.Y0; if (inVp(X, Y, VIEWPORT)) v[Y * W + X] = c; };
export function replaceColor(v, bg, lo, hi) { for (let o = SCREEN; o > 0; o--) if (o < v.length && v[o] >= lo && v[o] <= hi) v[o] = bg[o]; }
export function replaceTmp(v, bg, lo, hi) { for (let o = SCREEN; o > 0; o--) if (o < v.length && P.isTmp(v[o], lo, hi)) v[o] = bg[o]; }
const G0 = 0.006999999999997897, VX0 = 0.5, VY0 = 0.10000000000002274;
const blastK = (n) => (n <= 2 ? 1 : n <= 5 ? 2 : n <= 7 ? 3 : n === 8 ? 4 : 5);
function deathIntro(rng, sound) { for (let i = 0; i < 54; i++) { if (sound) rng.word(500); rng.word(0xffff); } }
function deathOutro(v, bg, ts, tx, ty, rng, sound, color, hi, twin) {
  let r6 = 0;
  for (let ae = 0; ae < 5; ae++) for (let b0 = 3; b0 < 6; b0++) {
    r6++;
    const col = P.tmp(10 * b0 + 100 + ae);
    for (const rr of [r6, r6 + 1]) {
      if (!P.disc) { ring(v, tx, ty, rr, col); if (twin) ring(v, tx + 1, ty, rr, col); }
      for (let k = 0; k < 5; k++) { if (sound) rng.word((1300 - 40 * r6) & 0xffff); rng.word(0xffff); }
    }
    r6++;
  }
  for (let ae = 4; ae >= 0; ae--) for (let k = 4 - ae; k >= 0; k--) { if (sound) rng.word(200); rng.word(63); rng.word(63); rng.word(63); }
  // Вектор: кольца 1..30 (цвет 3) и их стирание в двух центрах сводятся к одному кругу радиуса 30 — заливка и стирание
  if (P.disc) { disc(v, bg, tx, ty, 30, P.tmp(0), VIEWPORT, 0, 1); disc(v, bg, tx, ty, 30, null, VIEWPORT, 0, 1); }
  else for (let r = 30; r >= 0; r--) { ringRestore(v, bg, tx, ty, r); ringRestore(v, bg, tx + 1, ty, r); }
  redrawAll(v, ts);
  replaceColor(v, bg, color, color);
  replaceTmp(v, bg, 0x82, hi);
}
function miniBlast(v, bg, px, py, rng, sound, call0) {
  const base = 10 * (rng.word(3) + 3), k = blastK(rng.word(10));
  for (let r = 0; r <= 4 * k; r++) {
    if (sound) rng.word(2500); if (call0) rng.word(0xffff);
    const col = P.tmp(base + 100 + trunc(r / k));
    if (!P.disc) { ring(v, px, py, r, col); ring(v, px + 1, py, r, col); }
  }
  if (P.disc) disc(v, bg, px, py, 4 * k, P.tmp(0), VIEWPORT, 0, 1);      // Вектор: кольца 0..4k в двух центрах = один круг
  for (let r = 4 * k; r >= 0; r--) { if (sound) rng.word(2500); if (call0) rng.word(0xffff); if (!P.disc) { ringRestore(v, bg, px, py, r); ringRestore(v, bg, px + 1, py, r); } }
  if (P.disc) disc(v, bg, px, py, 4 * k, null, VIEWPORT, 0, 1);
}
function death0(v, bg, ts, victim, rng, sound, wind, xkill) {          // 285c:0020
  const t = ts[victim - 1], color = tankColor(victim), tx = t.x - P.X0, ty = t.y - P.Y0;
  deathIntro(rng, sound);
  for (let f = 0; f < 11; f++) {
    if (sound) rng.word(500);
    let X, Y, vx, vy, px, py;
    if (P.fixed) { X = FX.fromInt(tx); Y = FX.fromInt(ty); vx = FX.sub(FX.VX0, FX.rndUnit(rng)); vy = FX.sub(FX.VY0, FX.rndUnit(rng)); }
    else { X = q(tx); Y = q(ty); vx = q(VX0 - rng.real()); vy = q(VY0 - rng.real()); }
    for (;;) {
      let done = false;
      if (P.fixed) {
        X = FX.add(X, vx); Y = FX.add(Y, vy); vy = FX.add(vy, FX.G0); vx = FX.add(vx, FX.idiv(FX.fromInt(wind), 5000));
        px = FX.trunc(X); py = FX.trunc(Y);
      } else {
        X = q(X + vx); Y = q(Y + vy); vy = q(vy + G0); vx = q(q(wind / 5000) + vx);
        px = trunc(X); py = trunc(Y);
      }
      const c = gpVp(v, px, py);
      if (c === P.frame || c === P.ground) done = true;
      if (xkill && isTank(c) && ts[c - P.tank0]) { const vic = ts[c - P.tank0]; if (vic.shield > 0) done = true; else vic.men -= rng.word(10) + 5; }
      if (py < 0 || py > H || px < 0 || px > W) done = true;
      ppVp(v, px, py, color);
      if (done) break;
    }
    miniBlast(v, bg, px, py, rng, sound, false);
  }
  deathOutro(v, bg, ts, tx, ty, rng, sound, color, 0x9f, true);
}
function death2(v, bg, ts, victim, rng, sound, wind, xkill) {          // 285c:1da5
  const t = ts[victim - 1], color = tankColor(victim), tx = t.x - P.X0, ty = t.y - P.Y0;
  deathIntro(rng, sound);
  const F = [];
  for (let i = 0; i < 11; i++) {
    if (sound) rng.word(500);
    const spark = P.fixed
      ? { X: FX.fromInt(tx), Y: FX.fromInt(ty), vx: FX.sub(FX.VX0, FX.rndUnit(rng)), vy: FX.sub(FX.VY0, FX.rndUnit(rng)) }
      : { X: q(tx), Y: q(ty), vx: q(VX0 - rng.real()), vy: q(VY0 - rng.real()) };
    F.push({ ...spark, dead: false, end: [0, 0] });
  }
  for (;;) {
    let any = false;
    for (const f of F) {
      if (f.dead) continue;
      let px, py;
      if (P.fixed) {
        f.X = FX.add(f.X, f.vx); f.Y = FX.add(f.Y, f.vy); f.vy = FX.add(f.vy, FX.G0); f.vx = FX.add(f.vx, FX.idiv(FX.fromInt(wind), 5000));
        px = FX.trunc(f.X); py = FX.trunc(f.Y);
      } else {
        f.X = q(f.X + f.vx); f.Y = q(f.Y + f.vy); f.vy = q(f.vy + G0); f.vx = q(q(wind / 5000) + f.vx);
        px = trunc(f.X); py = trunc(f.Y);
      }
      any = true;
      const c = gpVp(v, px, py);
      if (c === P.frame || c === P.ground) f.dead = true;
      if (xkill && isTank(c) && ts[c - P.tank0]) { const vic = ts[c - P.tank0]; if (vic.shield >= 1) f.dead = true; else vic.men -= rng.word(10) + 10; }
      if (py < 0 || py > P.Y1 - P.Y0 || px < 0 || px > P.X1 - P.X0) f.dead = true;
      ppVp(v, px, py, color);
      if (f.dead) f.end = [px, py];
    }
    if (!any) break;
  }
  for (const f of F) miniBlast(v, bg, f.end[0], f.end[1], rng, sound, true);
  deathOutro(v, bg, ts, tx, ty, rng, sound, color, 0x9a, false);
}
const vget16 = (v, x, y) => peek(v, off16(x, y)), vput16 = (v, x, y, c) => poke(v, off16(x, y), c);
function particleHit(v, ts, x, y, rng, xkill) {
  if (!xkill) return;
  const c = vget16(v, x, y);
  if (isTank(c) && ts[c - P.tank0] && ts[c - P.tank0].shield <= 0) ts[c - P.tank0].men -= rng.word(3);
}
const SHAPE = { 1: (x, y, a, b) => [x + b, y - a], 2: (x, y, a, b) => [x + b, y + a], 3: (x, y, a, b) => [x + a, y - b], 4: (x, y, a, b) => [x - a, y - b],
  5: (x, y, a, b) => [x + b + a, y - a], 6: (x, y, a, b) => [x + b - a, y - a], 7: (x, y, a, b) => [x + b + a, y + a], 8: (x, y, a, b) => [x + b - a, y + a] };
function deathParticles(v, bg, ts, victim, rng, sound, mode, xkill) {   // 285c:0f61
  const t = ts[victim - 1], bursts = rng.word(5) + 5;
  for (let n = 0; n < bursts; n++) {
    const m = rng.word(P.sparkM) + 2, kind = rng.word(8) + 1, frames = [];
    const gen = (f) => {
      const pts = [];
      for (let i = 0; i < m; i++) {
        const a = rng.word(10 * f), w = rng.word(a + 10);
        const b = P.fixed ? FX.truncSubHalf(w - 5, a) : trunc((w - a / 2) - 5);
        pts.push(SHAPE[kind](t.x, t.y, a, b));
      }
      for (const p of pts) {
        if (p[0] > P.X1) p[0] = 2 * P.X1 - p[0]; if (p[1] > P.Y1) p[1] = 2 * P.Y1 - p[1]; if (p[1] < P.Y0) p[1] = 2 * P.Y0 - p[1]; if (p[0] < P.X0) p[0] = 2 * P.X0 - p[0];
      }
      return pts;
    };
    if (!P.stream) for (let f = 1; f <= 5; f++) frames.push(gen(f));      // оригинал: сначала все 5 кадров, потом рисование
    if (mode === 0) {
      for (let f = 1; f <= 5; f++) { if (P.stream) frames[f - 1] = gen(f); for (let i = 0; i < m; i++) {
        if (sound) rng.word(f === 1 ? 500 : (500 * f) & 0xffff);
        const [x, y] = frames[f - 1][i];
        particleHit(v, ts, x, y, rng, xkill); vput16(v, x, y, P.tmp(rng.word(14) + 1));
        if (f > 1) { const [px, py] = frames[f - 2][i]; vput16(v, px, py, bg[off16(px, py)]); }
      } }
      for (const [x, y] of frames[4]) vput16(v, x, y, bg[off16(x, y)]);
    } else {
      for (let f = 1; f <= 5; f++) { if (P.stream) frames[f - 1] = gen(f); for (let i = 0; i < m; i++) {
        if (sound) rng.word((500 * f) & 0xffff);
        const [x, y] = frames[f - 1][i];
        particleHit(v, ts, x, y, rng, xkill);
        let col = rng.word(14) + 0xc9; col = col === 0xca ? P.ground : P.tmp(col);
        vput16(v, x, y, col);
      } }
    }
  }
  redrawAll(v, ts); eraseTankBarrel(v, bg, t); replaceTmp(v, bg, 0xc9, 0xdc);
}
function death4(v, bg, ts, victim, rng, sound) {                          // 285c:28d9
  const t = ts[victim - 1], waves = rng.word(30) + 30;
  for (let r = 1; r <= waves; r++) {
    const n = rng.word(P.fountainN);
    for (let i = 0; i < n; i++) {
      const h = rng.word(10 * r), w = rng.word(h + 10);
      const dx = P.fixed ? FX.truncSubHalf(w - 5, h) : trunc((w - h / 2) - 5);
      let y = t.y - h, x = t.x + dx;
      while (y > P.Y1 || x < P.X0 || y < P.Y0 || x > P.X1) { if (x > P.X1) x = 2 * P.X1 - x; if (y > P.Y1) y = 2 * P.Y1 - y; if (y < P.Y0) y = 2 * P.Y0 - y; if (x < P.X0) x = 2 * P.X0 - x; }
      vput16(v, x, y, P.ground);
      if (sound) rng.word(1000);
    }
  }
  redrawAll(v, ts); eraseTankBarrel(v, bg, t);
}
function death5(v, bg, ts, victim) { const t = ts[victim - 1]; t.men = -1; eraseTankBarrel(v, bg, t); }   // 285c:2b76
function death6(v, bg, ts, victim, rng, sound) {                          // 285c:2c29
  const t = ts[victim - 1], n = rng.word(10), count = n <= 1 ? 1 : n <= 4 ? 2 : n <= 7 ? 3 : 4;
  for (let j = 1; j <= count; j++) {
    const ex = P.fixed ? FX.fromInt(t.x) : t.x, ey = P.fixed ? FX.fromInt(t.y) : t.y;
    explode(v, bg, ts, ex, ey, P.ground, 0, j, rng, sound); redrawAll(v, ts);
  }
  t.men = -1;
}
export function death(variant, v, bg, ts, victim, rng, sound, wind = 0, xkill = false) {
  if (variant === 0) death0(v, bg, ts, victim, rng, sound, wind, xkill);
  else if (variant === 1) deathParticles(v, bg, ts, victim, rng, sound, 0, xkill);
  else if (variant === 2) death2(v, bg, ts, victim, rng, sound, wind, xkill);
  else if (variant === 3) deathParticles(v, bg, ts, victim, rng, sound, 1, xkill);
  else if (variant === 4) death4(v, bg, ts, victim, rng, sound);
  else if (variant === 5) death5(v, bg, ts, victim);
  else death6(v, bg, ts, victim, rng, sound);
}

// ---------- ход целиком: 2583:2976..2cee ----------
export function afterShot(v, bg, ps, shooter, rng, fl, onDeath = null) {
  for (const p of ps) drawTankBarrel(v, p);
  if (fl.crumble > 0) crumbleGate(v, bg, rng, fl.crumble, fl.rebound);
  if (fl.fall) tanksFall(v, bg, ps, rng, fl.rebound);
  for (;;) {
    let died = false;
    for (const p of ps) {
      if (p.men > 0 || !p.alive) continue;
      died = true; p.alive = false;
      const variant = rng.word(7);
      death(variant, v, bg, ps, p.idx, rng, fl.sound, fl.wind, fl.xkill);
      if (shooter !== p.idx) ps[shooter - 1].score += 1500;
      drawFrame(v, fl.rebound);
      if (P.fixed ? FX.rndLtRatio(rng, fl.crumble, 100) : rng.real() * 100 < fl.crumble) crumble(v, bg);
      if (fl.fall) tanksFall(v, bg, ps, rng, fl.rebound);
      if (onDeath) onDeath(p, variant);
    }
    if (!died) break;
  }
}
export function turn(v, bg, ps, shooter, rng, fl) { const r = fire(v, bg, ps, shooter, rng, fl); afterShot(v, bg, ps, shooter, rng, fl); return r; }

// ---------- фон поля 2eef:0000 ----------
export function drawBackground(kind, rng) {
  const v = new Uint8Array(SCREEN), VP = VIEWPORT, fw = P.X1 - P.X0 + 1, fh = P.Y1 - P.Y0 + 1, sky = (c) => P.sky(c);
  if (kind === 1) for (let i = 0; i < 500; i++) { const x = rng.word(fw) + P.X0, y = rng.word(fh) + P.Y0, c = rng.word(20) + 30; v[y * W + x] = sky(c); }
  else if (kind === 2) for (let y = P.Y0; y <= P.Y1 + 1; y++) line(v, P.X0, y, P.X1 + 1, y, sky((y % 30) + 30));
  else if (kind === 3) { const cx = fw >> 1, cy = fh >> 1; for (let r = 0; r <= 170; r++) { ring(v, cx, cy, r, sky((r % 30) + 30), VP); ring(v, cx + 1, cy, r, sky((r % 30) + 30), VP); } }
  else if (kind === 4) {
    let k = 0; const ray = (x, y) => { line(v, W >> 1, H >> 1, x, y, sky((k % 30) + 30)); k++; };
    for (let x = VP[0]; x <= VP[2]; x++) ray(x, VP[1]);
    for (let y = VP[1]; y <= VP[3]; y++) ray(VP[2], y);
    for (let x = VP[2]; x >= VP[0]; x--) ray(x, VP[3]);
    for (let y = VP[3]; y >= VP[1]; y--) ray(VP[0], y);
    for (let x = VP[0]; x <= (VP[2] + VP[0]) >> 1; x++) ray(x, VP[1]);
  } else if (kind === 5) for (let y = P.Y0; y <= P.Y1 + 1; y++) line(v, P.X0, y, P.X1 + 1, y, sky(((y - P.Y0 + 1) >> 3) + 30));
  frameRects(v);
  return v;
}

// ---------- начало раунда: 2eef:0909 + 2583:2531..2675 ----------
export function roundStart(rng, ps, wallsCfg, bgCfg, windMode) {
  let rebound = P.fixed ? FX.rndLt(rng, FX.TH.p50) : !(rng.real() > 0.5);
  if (wallsCfg === 0) rebound = false;
  if (wallsCfg === 2) rebound = true;
  const kind = P.noBg ? 0 : bgCfg < P.bgKinds ? bgCfg : rng.word(P.bgKinds);
  const v = drawBackground(kind, rng), bg = P.noBg ? new Uint8Array(SCREEN) : new Uint8Array(v), n = ps.length;   // noBg: «фон» — нули, рамка только на экране
  renderTerrain(generateTerrain(rng, n), v);
  const ts = placeTanks(rng, n, v, bg, rebound);
  ps.forEach((p, i) => { const t = ts[i]; Object.assign(p, { idx: i + 1, x: t.x, y: t.y, angle: t.angle, power: t.power, facing: t.facing, men: t.men, alive: true }); if (p.hist) p.hist.n = 0; });   // 2eef:0909: счётчик истории ИИ = 0 (сами выстрелы остаются)
  const first = rng.word(n);
  const wind = generateWind(rng, windMode);
  return { v, bg, rebound, wind, first, kind };
}

// ---------- ИИ: 2cab:000d, 2b39:0425 ----------
export const AI_NAMES = { 'Mr. Stupid': 1, 'Birdy Bonker': 2, Rifleman: 3, Lobber: 4, 'Lob & Shoot': 5, 'Windless Wit': 6, Twanger: 7 };
export function newHist() { return { n: 0, planned: 0, power: 0, angle: 0, facing: 0, weapon: 0, shots: {}, target: 0 }; }
export function histFromBytes(b) {
  const dv = new DataView(b.buffer, b.byteOffset, b.byteLength), w = (o) => dv.getInt16(o, true);
  const h = { n: w(0), planned: b[2], power: w(3), angle: w(5), facing: w(7), weapon: w(9), shots: {}, target: w(0x7e6), strategy: w(0x800) };
  for (let k = 0; k < 200; k++) { const o = 0x0b + 10 * k; h.shots[k] = { angle: w(o), power: w(o + 2), facing: w(o + 4), x: w(o + 6), y: w(o + 8) }; }
  return h;
}
const shot = (h, k) => h.shots[k] || { angle: 0, power: 0, facing: 0, x: 0, y: 0 };
export function aiType(name, rebound) {
  let t = AI_NAMES[name] || 0;
  if (t === 5) t = rebound ? 3 : 4;
  if (t === 7 && !rebound) t = 3;
  return t;
}
export function chooseCode(p, h) {                     // 2cab:213e
  while (p.ammo[h.weapon] < 1) { h.weapon--; if (h.weapon < 0) h.weapon = 12; }
  if (10 * p.men < h.power) h.power = 10 * p.men;
  if (p.energy < h.power && h.weapon === 5) h.power = p.energy;
  if (h.power < 0) h.power = 0;
  let code = 5; const t = trunc((p.facing - 1) / 2);
  if (p.angle < h.angle) code = 1 - t;
  if (p.angle > h.angle) code = t + 2;
  if (p.power > h.power) code = 3;
  if (p.power < h.power) code = 4;
  if (p.facing !== h.facing) code = 6;
  if (p.weapon !== h.weapon) code = 8;
  if (code === 3 && p.power - h.power > 99) p.power -= 90;
  if (code === 3 && p.power - h.power > 9) p.power -= 9;
  if (code === 4 && h.power - p.power > 99) p.power += 90;
  if (code === 4 && h.power - p.power > 9) p.power += 9;
  if (code === 5) h.planned = 0;
  return code;
}
// 2b39:0577..0efe — применить код действия (общий для человека и ИИ); 9/10 — наведение
export function applyCode(v, bg, p, code) {
  const eraseBarrel = () => { const [bdx, bdy] = barrelOf(p.angle); line(v, p.x, p.y, p.x + bdx * p.facing, p.y - bdy, 0, bg); };
  if (code === 7 || code === 8) {
    for (let guard = 0; guard < 40; guard++) {
      p.weapon += code === 8 ? 1 : -1;
      if (p.weapon < 0) p.weapon = 17; if (p.weapon > 17) p.weapon = 0;
      if (p.ammo[p.weapon] > 0 && !(p.ammo[p.weapon] < 100 && p.weapon === 5)) break;
    }
  } else if (code === 1 || code === 2) {
    eraseBarrel();
    p.angle += code === 1 ? p.facing : -p.facing;
    if (p.angle > 90) { p.facing = -p.facing; p.angle = 180 - p.angle; }
    if (p.angle < 0) { p.facing = -p.facing; p.angle = Math.abs(p.angle); }
    drawTankBarrel(v, p);
  } else if (code === 3 || code === 4) {
    p.power += code === 4 ? 1 : -1;
    if (p.power > 10 * p.men) p.power = 10 * p.men;
    if (p.power < 0) p.power = 0;
    if (p.power > p.energy && p.weapon === 5) p.power = p.energy;
  } else if (code === 6) { eraseBarrel(); p.facing = -p.facing; drawTankBarrel(v, p); }
  else if (code === 9 && p.herb > 0) p.guided ^= 1;
  else if (code === 10 && p.vick > 0) p.guided ^= 2;
}
export const needsWeaponSwitch = (p) => p.ammo[p.weapon] <= 0 || (p.weapon === 5 && p.ammo[5] <= 100);
// один «опрос ввода» компьютера (2b39:0f78): код действия
export function computerStep(v, bg, ps, p, rng, rebound) {
  if (needsWeaponSwitch(p)) return 8;
  if (!p.hist.planned) plan(v, bg, ps, p, p.hist, rng, rebound, p.name);
  return chooseCode(p, p.hist);
}
export function computerTurn(v, bg, ps, p, rng, rebound, maxCalls = 5000) {
  const codes = [];
  for (let i = 0; i < maxCalls; i++) { const c = computerStep(v, bg, ps, p, rng, rebound); codes.push(c); applyCode(v, bg, p, c); if (c === 5) break; }
  return codes;
}
// история выстрелов (2583:27b9, 2583:29ee)
export const turnBegin = (h) => { h.n = i16(h.n + 1); };
export function recordShot(h, p, x, y) { const tx = trunc(x); h.shots[h.n] = { angle: p.angle, power: p.power, facing: p.facing, x: tx > 0x7fff ? 0x7fff : i16(tx), y: i16(trunc(y)) }; }

const hyp = (a, b) => q(msqrt(q(q(a * a) + q(b * b))));
const RAD2DEG_PI = 3.1415926535883045;
const atanDeg = (x) => trunc(q(q(q(matan(x)) * 180) / RAD2DEG_PI));
// Произведение «промах × отношение мощностей» может не влезть в ±32768 — считаем широко, усекаем к нулю.
function truncRatio(miss, dp, dx) {
  const ratio = FX.div(FX.fromInt(dp), FX.fromInt(dx));
  const prod = FX.mulWide(FX.fromInt(miss), ratio);
  const neg = prod < 0n;
  const t = (neg ? -prod : prod) / BigInt(FX.ONE);
  return neg ? -Number(t) : Number(t);
}
function firstWeapon(p, h) { h.weapon = 11; for (let w = 1; w <= 4; w++) if (p.ammo[w] > 0) h.weapon = w; }
function planStupid(v, bg, ps, p, h, rng, rebound) {
  do { h.facing = rng.word(3) - 1; } while (Math.abs(h.facing) !== 1);
  firstWeapon(p, h);
  h.angle = rng.word(90); h.power = rng.word(5000) + 20;
  if (!rebound) { h.facing = trunc(ps.length / 2) < p.idx ? -1 : 1; h.power = rng.word(250) + 50; }
  if (10 * p.men < h.power) h.power = 10 * p.men;
  h.planned = 1;
}
function planBirdy(v, bg, ps, p, h) { h.weapon = 1; h.facing = 1; h.angle = 90; h.power = 300; if (10 * p.men < h.power) h.power = 10 * p.men; h.planned = 1; }
function planLobber(v, bg, ps, p, h, rng) {
  const N = ps.length, by = (k) => ps[k - 1];
  let target = p.idx, best = 0x7fff;
  h.weapon = p.ammo[1] >= 1 ? 1 : 11;
  if (Math.abs(h.facing) !== 1) h.facing = 1;
  let d = h.facing;
  if ((P.fixed ? FX.rndLt(rng, FX.TH.p50) : rng.real() <= 0.5) && h.n === 1) d = -d;
  if (h.n < 3) {
    do { target += d; if (target > N) target = 1; if (target < 1) target = N; } while (!(target !== p.idx && by(target).alive));
  } else {
    const sx = shot(h, h.n - 1).x;
    for (let k = 1; k <= N; k++) if (k !== p.idx && Math.abs(sx - by(k).x) < best && by(k).alive) { target = k; best = Math.abs(sx - by(k).x); }
  }
  if (target > N) target = 1;
  h.target = target;
  if ((h.facing === 1 && target < p.idx) || (h.facing === -1 && target > p.idx)) h.n = 1;
  h.facing = target > p.idx ? 1 : -1;
  if (h.n === 1) { h.angle = 75; h.power = rng.word(100) + 100; h.planned = 1; }
  else if (h.n === 2) { h.angle = 75; h.power = rng.word(100) + 200; h.planned = 1; }
  else {
    const si = shot(h, h.n - 2), sj = shot(h, h.n - 1);
    const dx = (sj.x - si.x) || 1, dp = (sj.power - si.power) || 1, miss = by(target).x - si.x;
    const adj = P.fixed ? truncRatio(miss, dp, dx) : trunc(q(miss * q(dp / dx)));
    h.planned = 1;
    h.power = i16(si.power + (adj % 0x7fff));
    if (h.power < 0) h.power = i16(-h.power * 2);       // 16 бит: большое отрицательное остаётся отрицательным -> 0 в chooseCode
    if (Math.abs(miss) > 5) h.weapon = 2;
    if (Math.abs(miss) > 15) h.weapon = 3;
    if (Math.abs(miss) > 30) h.weapon = 4;
    const nxt = { 11: 0, 1: 11, 2: 1, 3: 2, 4: 3 };
    while (p.ammo[h.weapon] < 1 && h.weapon in nxt) h.weapon = nxt[h.weapon];
  }
}
function planWitFix(ps, p, h, rng) {
  let target;
  do { target = rng.word(ps.length) + 1; } while (!(target !== p.idx && ps[target - 1].alive));
  h.target = target;
  const t = ps[target - 1];
  let dx = t.x - p.x, dy = t.y - p.y;
  if (dy < 0) dy += 4; if (dx > 0) dx -= 4; if (dx < 0) dx += 4;
  const r = rng.word(100) + 50;
  const vx0 = FX.div(FX.fromInt(target > p.idx ? r : -r), FX.fromInt(50));
  let vy50 = 0, vx50 = 0;
  if (vx0 !== 0) {
    const tt = dx === 0 ? 0 : FX.div(FX.fromInt(dx), vx0);
    let vy0 = 0n;
    if (tt !== 0) {
      const grav = FX.divWide(FX.mulWide(tt, tt), BigInt(FX.fromInt(20)));   // 0.05·tt² = tt²/20
      vy0 = FX.divWide(BigInt(FX.fromInt(dy)) - grav, BigInt(tt));
    }
    vy50 = FX.narrow(vy0 * 50n, 'wit.vy');
    vx50 = FX.mulInt(vx0, 50);
  }
  h.power = Math.abs(FX.trunc(FX.hypot(vy50, vx50)));
  h.angle = vx50 === 0 ? 0 : Math.abs(FX.atanDeg(FX.div(vy50, vx50)));
  h.facing = target > p.idx ? 1 : -1;
  if (10 * p.men < h.power) h.power = 10 * p.men;
  firstWeapon(p, h); h.planned = 1;
}
function planWit(v, bg, ps, p, h, rng) {
  if (P.fixed) return planWitFix(ps, p, h, rng);
  let target;
  do { target = rng.word(ps.length) + 1; } while (!(target !== p.idx && ps[target - 1].alive));
  h.target = target;
  const t = ps[target - 1];
  let dx = t.x - p.x, dy = t.y - p.y;
  if (dy < 0) dy += 4; if (dx > 0) dx -= 4; if (dx < 0) dx += 4;
  const r = rng.word(100) + 50;
  let vx = q((target > p.idx ? r : -r) / 50);
  const tt = q(dx / vx);
  let vy = q(q(dy - q(q(0.05000000000001137 * tt) * tt)) / tt);
  vy = q(vy * 50); vx = q(vx * 50);
  h.power = trunc(hyp(vy, vx));
  h.angle = Math.abs(atanDeg(q(vy / vx)));
  h.facing = target > p.idx ? 1 : -1;
  if (10 * p.men < h.power) h.power = 10 * p.men;
  firstWeapon(p, h); h.planned = 1;
}
const pxAt = (v, x, y) => (x >= 0 && x < W && y >= 0 && y < H ? v[y * W + x] : 0);
function bigWeapon(p, h, dx, dy, sc) {
  if (P.fixed) {
    if (sc > 990) for (const [w, r] of [[2, 15], [3, 30], [4, 60]]) if (FX.hypot(FX.fromInt(dx), FX.fromInt(dy)) > FX.fromInt(r) && p.ammo[w] > 0) h.weapon = w;
    if (p.ammo[5] > 100 && sc <= 990) h.weapon = 5;
    return;
  }
  if (sc > 990) for (const [w, r] of [[2, 15], [3, 30], [4, 60]]) if (hyp(dx, dy) > r && p.ammo[w] > 0) h.weapon = w;
  if (p.ammo[5] > 100 && sc <= 990) h.weapon = 5;
}
function planRiflemanFix(v, bg, ps, p, h, rng, rebound) {
  const N = ps.length, scr = new Uint8Array(v), score = {};
  h.weapon = p.ammo[1] >= 1 ? 1 : 11;
  for (let k = 1; k <= N; k++) {
    const t = ps[k - 1];
    let s = 1000;
    if (t.y > p.y) s = 100;
    if (k === p.idx || !t.alive) s = 0;
    if (s > 0) {
      const dx = t.x - p.x, dy = t.y - p.y, dist = FX.hypot(FX.fromInt(dx), FX.fromInt(dy));
      const n = FX.trunc(dist);
      if (dist !== 0) {
        const sx = FX.div(FX.fromInt(dx), dist), sy = FX.div(FX.fromInt(dy), dist);
        for (let i = 1; i <= n; i++) {
          const X = p.x + FX.trunc(FX.mul(sx, FX.fromInt(i))), Y = p.y + FX.trunc(FX.mul(sy, FX.fromInt(i)));
          if (pxAt(scr, X, Y) === P.ground) s--;
          if (!P.aiNoDraw && X >= 0 && X < W && Y >= 0 && Y < H) scr[Y * W + X] = tankColor(k);
        }
      }
    }
    score[k] = s;
  }
  let best = -32767, target = 0;
  for (let k = 1; k <= N; k++) if (score[k] > best) { best = score[k]; target = k; }
  h.target = target;
  const t = ps[target - 1], dx = (t.x - p.x) || 1, dy = (p.y - t.y + 4) || 1;
  bigWeapon(p, h, dx, dy, score[target]);
  h.power = 1000;
  h.angle = Math.abs(FX.atanDeg(FX.div(FX.fromInt(dy), FX.fromInt(dx))));
  h.facing = target < p.idx ? -1 : 1;
  if (dy < 0) {
    if (rebound) h.angle = rng.word(70) + 10; else { h.power = rng.word(100) + 200; h.angle = 45; }
    h.weapon = 1;
  }
  h.planned = 1;
}
function planRifleman(v, bg, ps, p, h, rng, rebound) {
  if (P.fixed) return planRiflemanFix(v, bg, ps, p, h, rng, rebound);
  const N = ps.length, scr = new Uint8Array(v), score = {};
  h.weapon = p.ammo[1] >= 1 ? 1 : 11;
  for (let k = 1; k <= N; k++) {
    const t = ps[k - 1];
    let s = 1000;
    if (t.y > p.y) s = 100;
    if (k === p.idx || !t.alive) s = 0;
    if (s > 0) {
      const dx = t.x - p.x, dy = t.y - p.y, dist = hyp(dx, dy);
      for (let i = 1; i <= trunc(dist); i++) {
        const X = p.x + trunc(q(q(dx / dist) * i)), Y = p.y + trunc(q(q(dy / dist) * i));
        if (pxAt(scr, X, Y) === P.ground) s--;
        if (!P.aiNoDraw && X >= 0 && X < W && Y >= 0 && Y < H) scr[Y * W + X] = tankColor(k);
      }
    }
    score[k] = s;
  }
  let best = -32767, target = 0;
  for (let k = 1; k <= N; k++) if (score[k] > best) { best = score[k]; target = k; }
  h.target = target;
  const t = ps[target - 1], dx = (t.x - p.x) || 1, dy = (p.y - t.y + 4) || 1;
  bigWeapon(p, h, dx, dy, score[target]);
  h.power = 1000;
  h.angle = Math.abs(atanDeg(q(dy / dx)));
  h.facing = target < p.idx ? -1 : 1;
  if (dy < 0) {
    if (rebound) h.angle = rng.word(70) + 10; else { h.power = rng.word(100) + 200; h.angle = 45; }
    h.weapon = 1;
  }
  h.planned = 1;
}
function twangTrace(scr, ps, p, h, k, score) {
  const CEILING = P.Y0 - 3, t = ps[k - 1], dx = t.x - p.x, dy = p.y - t.y, top = t.y - CEILING;
  const a = q(matan(Math.abs(q((dy + 2 * top) / dx))));
  h.facing = k < p.idx ? -1 : 1;
  const up = p.y - CEILING, tan = q(q(msin(a)) / q(mcos(a))), ox = trunc(q((h.facing * up) / tan));
  const seg = (x0, y0, ex, ey, sy, cost) => {
    const dist = hyp(ex, ey);
    for (let s = 1; s <= trunc(dist); s++) {
      const X = trunc(q(x0 + q(q(ex / dist) * s))), Y = trunc(q(y0 + sy * q(q(ey / dist) * s)));
      if (vget16(scr, X, Y) === P.ground) score[k] -= cost;
      if (!P.aiNoDraw) vput16(scr, X, Y, tankColor(k));
    }
  };
  seg(p.x, p.y, ox, up, -1, 3);
  const lx = p.x + ox, ly = p.y - up;
  seg(lx, ly, t.x - lx, t.y - ly, 1, 1);
}
function twangTraceFix(scr, ps, p, h, k, score) {
  const CEILING = P.Y0 - 3, t = ps[k - 1], dx = t.x - p.x, dy = p.y - t.y, top = t.y - CEILING;
  const numer = dy + 2 * top;
  const ratio = dx === 0 ? 0 : FX.abs(FX.div(FX.fromInt(numer), FX.fromInt(dx)));
  const deg = FX.atanDeg(ratio);
  h.facing = k < p.idx ? -1 : 1;
  const up = p.y - CEILING;
  const [co, si] = FX.sincos(deg);
  const tan = co === 0 ? 0 : FX.div(si, co);
  let ox = 0;
  if (tan !== 0) ox = FX.trunc(FX.div(FX.mulInt(FX.fromInt(up), h.facing), tan));
  const seg = (x0, y0, ex, ey, sy, cost) => {
    const dist = FX.hypot(FX.fromInt(ex), FX.fromInt(ey));
    const n = FX.trunc(dist);
    if (!dist) return;
    const sx = FX.div(FX.fromInt(ex), dist), syv = FX.div(FX.fromInt(ey), dist);
    for (let s = 1; s <= n; s++) {
      const step = FX.fromInt(s);
      const X = FX.trunc(FX.add(FX.fromInt(x0), FX.mul(sx, step)));
      const Y = FX.trunc(FX.add(FX.fromInt(y0), FX.mulInt(FX.mul(syv, step), sy)));
      if (vget16(scr, X, Y) === P.ground) score[k] -= cost;
      if (!P.aiNoDraw) vput16(scr, X, Y, tankColor(k));
    }
  };
  seg(p.x, p.y, ox, up, -1, 3);
  const lx = p.x + ox, ly = p.y - up;
  seg(lx, ly, t.x - lx, t.y - ly, 1, 1);
}
function planTwangerFix(v, bg, ps, p, h, rng) {
  const N = ps.length; let scr = new Uint8Array(v), score = {};
  h.weapon = 1;
  for (let k = 1; k <= N; k++) { score[k] = (k === p.idx || !ps[k - 1].alive) ? -1 : 1000; if (score[k] !== -1) twangTraceFix(scr, ps, p, h, k, score); }
  let best = 0, cnt = 1; const rank = {};
  for (let k = 1; k <= N; k++) { rank[k] = 0; if (score[k] > best) { cnt++; best = score[k]; rank[k] = cnt; } else if (score[k] === best) rank[k] = cnt; }
  const top = Math.max(0, ...Object.values(rank));
  score = {}; best = 0; let target = 0;
  for (let k = 1; k <= N; k++) {
    const d = FX.hypot(FX.fromInt(p.x - ps[k - 1].x), FX.fromInt(p.y - ps[k - 1].y));
    score[k] = rank[k] >= top && rank[k] ? 1000 - FX.trunc(d) : 0;
    if (score[k] > best) { best = score[k]; target = k; }
  }
  h.target = target; scr = new Uint8Array(v); score[target] = 1000;
  twangTraceFix(scr, ps, p, h, target, score);
  const t = ps[target - 1], dx = t.x - p.x, dy = p.y - t.y, tp = t.y - (P.Y0 - 3);
  h.power = rng.word(51) + 950;
  const numer = dy + 2 * tp;
  const ratio = dx === 0 ? 0 : FX.div(FX.fromInt(numer), FX.fromInt(dx));
  h.angle = Math.abs(FX.atanDeg(FX.abs(ratio)));
  h.facing = target < p.idx ? -1 : 1;
  h.weapon = 1;
  bigWeapon(p, h, dx, dy, score[target]);
  h.planned = 1;
}
function planTwanger(v, bg, ps, p, h, rng) {
  if (P.fixed) return planTwangerFix(v, bg, ps, p, h, rng);
  const N = ps.length; let scr = new Uint8Array(v), score = {};
  h.weapon = 1;
  for (let k = 1; k <= N; k++) { score[k] = (k === p.idx || !ps[k - 1].alive) ? -1 : 1000; if (score[k] !== -1) twangTrace(scr, ps, p, h, k, score); }
  let best = 0, cnt = 1; const rank = {};
  for (let k = 1; k <= N; k++) { rank[k] = 0; if (score[k] > best) { cnt++; best = score[k]; rank[k] = cnt; } else if (score[k] === best) rank[k] = cnt; }
  const top = Math.max(0, ...Object.values(rank));
  score = {}; best = 0; let target = 0;
  for (let k = 1; k <= N; k++) {
    score[k] = rank[k] >= top && rank[k] ? 1000 - trunc(hyp(p.x - ps[k - 1].x, p.y - ps[k - 1].y)) : 0;
    if (score[k] > best) { best = score[k]; target = k; }
  }
  h.target = target; scr = new Uint8Array(v); score[target] = 1000;
  twangTrace(scr, ps, p, h, target, score);
  const t = ps[target - 1], dx = t.x - p.x, dy = p.y - t.y, tp = t.y - (P.Y0 - 3);
  h.power = rng.word(51) + 950;
  h.angle = Math.abs(atanDeg(Math.abs(q((dy + 2 * tp) / dx))));
  h.facing = target < p.idx ? -1 : 1;
  h.weapon = 1;
  bigWeapon(p, h, dx, dy, score[target]);
  h.planned = 1;
}
const PLANNERS = { 1: planStupid, 2: planBirdy, 3: planRifleman, 4: planLobber, 6: planWit, 7: planTwanger };
export function plan(v, bg, ps, p, h, rng, rebound, name) {
  const fn = PLANNERS[aiType(name, rebound)];
  if (!fn) throw new Error('ИИ: неизвестное имя ' + name);
  fn(v, bg, ps, p, h, rng, rebound);
}

// ---------- матч: перетасовка, результаты, магазин (224b) ----------
export const W_PRICE = [-1, 3000, 4000, 7000, 10000, 10000, 5000, 5000, 10000, 10000, 15000, -1, 4500, 4000, 6000, 8000, 10000, 4500];
export const W_PACK = [0, 100, 10, 2, 1, 1000, 5, 10, 3, 3, 1, 0, 10, 10, 7, 3, 1, 10];
export const SHOP_PRICE = [W_PRICE, [20000, 20000], [20000, 10000]], SHOP_PACK = [W_PACK, [5, 5], [1000, 100]];
export const SHOP_NAMES = [null, ["Herb's Guide", "Vick's Guide"], ['Energy Shield', 'Inertia Damp.']];
export const MIN_PRICE = 3000;
const STRATEGY_SETS = { 'Mr. Stupid': [1, 2, 4], Lobber: [1, 2, 4], 'Windless Wit': [1, 2, 4], Rifleman: [1, 2, 3, 4], 'Lob & Shoot': [1, 2, 3, 4], Twanger: [1, 2, 3, 4] };
export const AI_PICKABLE = ['Mr. Stupid', 'Lobber', 'Rifleman', 'Lob & Shoot', 'Windless Wit', 'Twanger'];   // DS:0120.. — «Random» выбирает Random(6)+1
export function pickStrategy(name, rng) { const a = STRATEGY_SETS[name]; for (;;) { const s = rng.word(4) + 1; if (!a || a.includes(s)) return s; } }
const reindex = (ps) => ps.forEach((p, i) => { p.idx = i + 1; });
export function shufflePlayers(rng, ps) {             // 224b:25a7
  const n = ps.length, cnt = rng.word(20) + 10;
  for (let i = 0; i < cnt; i++) { const a = rng.word(n); let b; do { b = rng.word(n); } while (a === b); [ps[a], ps[b]] = [ps[b], ps[a]]; }
  reindex(ps);
}
export function winnerBonus(p, n) { p.wins++; p.score += i16(n * 1000); }
export function results(rng, ps, auto) {              // 224b:2641
  const n = ps.length, sw = (e) => { [ps[e], ps[e + 1]] = [ps[e + 1], ps[e]]; };
  for (let k = 0; k < n; k++) for (let e = 0; e < n - 1; e++) if (ps[e].wins < ps[e + 1].wins) sw(e);
  for (let k = 0; k < n; k++) for (let e = 0; e < n - 1; e++) if (ps[e].wins === ps[e + 1].wins && ps[e].score < ps[e + 1].score) sw(e);
  for (const p of ps) p.men = 100;
  reindex(ps);
  if (auto) for (let i = 0; i < 200; i++) for (const m of [319, 199, 319, 199, 16]) rng.word(m);
}
export const shopHave = (p, cat, i) => (cat === 0 ? p.ammo[i] : cat === 1 ? (i ? p.vick : p.herb) : (i ? p.damp : p.shield));
export function shopAdd(p, cat, i, n) {
  if (cat === 0) p.ammo[i] = i16(p.ammo[i] + n);
  else if (cat === 1) { if (i) p.vick = i16(p.vick + n); else p.herb = i16(p.herb + n); }
  else if (i) p.damp += n; else p.shield += n;
}
export function shopMenu(p) {                          // 224b:0118 -> [[категория, номер], ...]
  const money = p.score - p.spent, menu = [];
  for (let w = 0; w < 18; w++) if ((p.ammo[w] > 0 || W_PRICE[w] <= money) && W_PACK[w] !== 0 && !(P.shopMaxWeapon && w > P.shopMaxWeapon)) menu.push([0, w]);
  for (const cat of P.shopNoGuides ? [2] : [1, 2]) for (let i = 0; i < 2; i++) if (shopHave(p, cat, i) > 0 || (SHOP_PRICE[cat][i] <= money && SHOP_PACK[cat][i] !== 0)) menu.push([cat, i]);
  return menu;
}
export function shopCommit(p, menu, qty) {            // «Purchase»/«Done»
  menu.forEach(([cat, i], c) => { if (qty[c] > 0) { p.spent += SHOP_PRICE[cat][i] * qty[c]; shopAdd(p, cat, i, SHOP_PACK[cat][i] * qty[c]); } });
}
function aiChoice(p, strategy, menu, qty, cart) {      // 224b:173d..1ab8: индекс позиции (с 0) или -1 = Done
  const money = p.score - p.spent - cart;
  let sel = -1;
  if (strategy === 1) {
    for (let c = menu.length - 1; c >= 0; c--) { const [cat, i] = menu[c]; if (cat === 0 && i >= 1 && i <= 4 && p.ammo[i] + W_PACK[i] * qty[c] < 20 && W_PRICE[i] <= money) sel = c; }
    return sel;
  }
  if (strategy === 2 || strategy === 3) {
    const hi = strategy === 2 ? 4 : 5;
    for (let c = 0; c < menu.length; c++) { const [cat, i] = menu[c]; if (cat === 0 && i >= 1 && i <= hi && W_PRICE[i] <= money) sel = c; }
  } else if (strategy === 4) {
    for (let c = menu.length - 1; c >= 0; c--) { const [cat, i] = menu[c]; if (cat === 2 && SHOP_PRICE[2][i] <= money) sel = c; }
  } else return -1;
  if (p.ammo[1] + W_PACK[1] * (qty[0] || 0) < 20) sel = 0;
  return sel;
}
export function aiShop(p, strategy) {
  if (p.score - p.spent < MIN_PRICE || !strategy) return false;
  const menu = shopMenu(p), qty = menu.map(() => 0);
  let cart = 0;
  for (let step = 0; step < 10000; step++) {
    const sel = aiChoice(p, strategy, menu, qty, cart);
    if (sel < 0 || !menu[sel]) break;
    const [cat, i] = menu[sel], price = SHOP_PRICE[cat][i];
    if (qty[sel] < 9 && price <= p.score - p.spent - cart) { cart += price; qty[sel]++; } else if (qty[sel] >= 9) break;   // в оригинале здесь зацикливание
  }
  shopCommit(p, menu, qty);
  return true;
}

// ---------- раунд целиком без анимации (2583:2531), все игроки — компьютеры ----------
// cfg: {walls, bg, windMode, crumble, fall, xkill, sound, ballVisible, trail}
export function nextAlive(ps, cur) { const n = ps.length; do { cur = cur % n + 1; } while (!ps[cur - 1].alive); return cur; }   // 2583:2783
export function autoSwitchWeapon(p) {                                 // 2583:27d7
  if (p.ammo[p.weapon] !== 0) return;
  for (let g = 0; g < 40; g++) { p.weapon = p.weapon >= 17 ? 0 : p.weapon + 1; if (p.ammo[p.weapon] > 0) break; }
}
// Прерывание раунда по желанию игроков (в оригинале такого нет; решение для Вектора, docs/spec/v06c.md).
// random = false — ничья: победителя нет, случайные числа не тратятся.
// random = true  — победа случайному из живых: Random(число живых), счёт по порядку мест.
// Дальше раунд завершается как обычно: бонус победителю (если он есть), результаты, магазин.
export function abortRound(rng, ps, random) {
  if (!random) return null;
  const alive = ps.filter((t) => t.alive);
  return alive.length ? alive[rng.word(alive.length)] : null;
}
export function playRound(rng, ps, cfg, maxTurns = 5000) {
  const r = roundStart(rng, ps, cfg.walls, cfg.bg, cfg.windMode);
  const fl = { rebound: r.rebound, crumble: cfg.crumble, fall: cfg.fall, xkill: cfg.xkill, sound: cfg.sound, wind: r.wind, ballVisible: cfg.ballVisible, trail: cfg.trail };
  let cur = r.first, turns = 0, winner = null;
  for (; turns < maxTurns; turns++) {
    cur = nextAlive(ps, cur);
    const p = ps[cur - 1];
    turnBegin(p.hist); autoSwitchWeapon(p);
    computerTurn(r.v, r.bg, ps, p, rng, fl.rebound);
    if (cfg.onTurn) cfg.onTurn('fire', cur, r, fl);
    const res = fire(r.v, r.bg, ps, cur, rng, fl);
    if (res) recordShot(p.hist, p, res.x, res.y);
    afterShot(r.v, r.bg, ps, cur, rng, fl);
    if (cfg.onTurn) cfg.onTurn('turn_end', cur, r, fl);
    const alive = ps.filter((t) => t.alive);
    if (alive.length <= 1) { winner = alive[0] || null; break; }
  }
  return { winner, turns: turns + 1, v: r.v, bg: r.bg, fl };
}

// =====================================================================================================
// Экран Вектора целиком: шрифт, панель хода, результаты, магазин (docs/spec/v06c-screen.md).
// Знакоместо 8×8, 32 столбца × 32 строки; текст только из 64 знаков 20h..5Fh (строчные буквы → прописные).
// =====================================================================================================
// Знак 5×7 в знакоместе 8×8 (столбцы 1..5, строки 0..6). 5 байт на знак — столбцы, бит 0 сверху. 320 байт.
const FONT_HEX =
  '0000000000' + '00005F0000' + '0007000700' + '147F147F14' + '242A7F2A12' + '2313086462' + '3649562050' + '0008070300' +
  '001C224100' + '0041221C00' + '2A1C7F1C2A' + '08083E0808' + '0080703000' + '0808080808' + '0000606000' + '2010080402' +
  '3E5149453E' + '00427F4000' + '7249494946' + '2141494D33' + '1814127F10' + '2745454539' + '3C4A494931' + '4121110907' +
  '3649494936' + '464949291E' + '0000140000' + '0040340000' + '0008142241' + '1414141414' + '0041221408' + '0201590906' +
  '3E415D594E' + '7C1211127C' + '7F49494936' + '3E41414122' + '7F4141413E' + '7F49494941' + '7F09090901' + '3E41415173' +
  '7F0808087F' + '00417F4100' + '2040413F01' + '7F08142241' + '7F40404040' + '7F021C027F' + '7F0408107F' + '3E4141413E' +
  '7F09090906' + '3E4151215E' + '7F09192946' + '2649494932' + '03017F0103' + '3F4040403F' + '1F2040201F' + '3F4038403F' +
  '6314081463' + '0304780403' + '6159494D43' + '007F414141' + '0204081020' + '004141417F' + '0402010204' + '4040404040';
export const FONT = hexBytes(FONT_HEX);
export const TEXT_COLOR = () => P.frame;
// col 0..31, row 0..31 — знакоместа. Фон знакоместа очищается в 0.
export function drawChar(v, col, row, ch, color) {
  let c = ch.toUpperCase().charCodeAt(0); if (c < 0x20 || c > 0x5f) c = 0x3f;
  const g = (c - 0x20) * 5, x0 = col * 8, y0 = row * 8;
  if (col < 0 || col > 31 || row < 0 || row > 31) return;
  for (let y = 0; y < 8; y++) for (let x = 0; x < 8; x++) {
    const on = x >= 1 && x <= 5 && y < 7 && (FONT[g + x - 1] >> y) & 1;
    v[(y0 + y) * W + x0 + x] = on ? color : 0;
  }
}
export function drawText(v, col, row, str, color = TEXT_COLOR()) { for (let i = 0; i < str.length; i++) drawChar(v, col + i, row, str[i], color); }
const padL = (s, n) => String(s).padStart(n).slice(-n), padR = (s, n) => String(s).padEnd(n).slice(0, n);
export const WEAPON_NAMES = ['Lead Ball', 'Incinerator', 'Mark II Incin.', '20 Kilo Nuke', '5 Meg Nuke', 'Laser', 'CRI 4/D', 'CRI 8/ND', 'CRI 8/D', 'CRI 20/ND',
  'CRI 20/D', 'Hand Grenade', 'Sonic Blaster', "Ball 'O' Dirt", 'Mark II Dirt', 'Pressured Dirt', 'High Pres. Dirt', 'Xplosive Dirt'];   // DS:1920+0x100*w
// Панель хода — строки знакомест 0..2 (точки y 0..23):
//   0: имя игрока его цветом (13)              WIND <123 / WIND 123> / WIND 0   (столбцы 21..31)
//   1: ANG <75 или ANG 75>   POW 1000   MEN 100
//   2: название оружия (15) xNNNN               H V — наведение: есть запас; * перед буквой — включено
export function drawPanel(v, p, wind) {
  for (let i = 0; i < 24 * W; i++) v[i] = 0;
  if (!p) return;
  drawText(v, 0, 0, padR(p.name, 13), tankColor(p.idx));
  const w = Math.abs(wind), ws = wind < 0 ? '<' + w : wind > 0 ? w + '>' : '0';
  drawText(v, 21, 0, 'WIND ' + padL(ws, 6));
  drawText(v, 0, 1, 'ANG ' + padR(p.facing < 0 ? '<' + p.angle : p.angle + '>', 3) + '  POW ' + padR(p.power, 4) + '  MEN ' + padL(Math.max(p.men, 0), 3));
  drawText(v, 0, 2, padR(WEAPON_NAMES[p.weapon], 15) + ' x' + padR(p.ammo[p.weapon], 5));
  if (p.herb > 0) drawText(v, 26, 2, (p.guided & 1 ? '*' : ' ') + 'H');
  if (p.vick > 0) drawText(v, 29, 2, (p.guided & 2 ? '*' : ' ') + 'V');
}
// Экран результатов (вместо поля): заголовок, по строке на игрока в порядке мест, подсказка.
export function drawResults(v, ps, round, rounds) {
  v.fill(0); frameRects(v);
  const last = round >= rounds;
  drawText(v, 2, 5, last ? 'FINAL RESULTS' : 'AFTER ROUND ' + round + ' OF ' + rounds);
  drawText(v, 2, 8, '# PLAYER        WINS  SCORE');
  ps.forEach((p, i) => {
    const row = 10 + 2 * i;
    drawText(v, 2, row, String(i + 1));
    drawText(v, 4, row, padR(p.name, 13), tankColor(p.idx));
    drawText(v, 18, row, padL(p.wins, 4) + padL(p.score, 7));
  });
  drawText(v, 2, 20, 'MONEY');
  ps.forEach((p, i) => drawText(v, 8 + 6 * i, 20, padL(p.score - p.spent, 5), tankColor(p.idx)));
  drawText(v, 2, 28, last ? 'GAME OVER' : 'PRESS ANY KEY');
}
// Магазин (весь экран, без рамки): строка на позицию меню; sel — выбранная строка (0..menu.length+1: дальше BUY и DONE),
// -1 — без курсора. Позиций не больше 22 (18 видов оружия без двух непродаваемых + 2 наведения + 2 защиты = 20).
export function drawShop(v, p, menu, qty, cart, sel = -1) {
  v.fill(0);
  drawText(v, 0, 0, 'SHOP');
  drawText(v, 5, 0, padR(p.name, 13), tankColor(p.idx));
  drawText(v, 0, 1, 'MONEY ' + padL(p.score - p.spent - cart, 6) + '   CART ' + padL(cart, 6));
  drawText(v, 2, 3, 'ITEM            PRICE  HAVE BUY');
  menu.forEach(([cat, i], c) => {
    const row = 4 + c, name = cat === 0 ? WEAPON_NAMES[i] : SHOP_NAMES[cat][i];
    drawText(v, 0, row, sel === c ? '>' : ' ');
    drawText(v, 2, row, padR(name, 15) + padL(SHOP_PRICE[cat][i], 6) + padL(Math.min(shopHave(p, cat, i), 99999), 6) + padL(qty[c] || '', 3));
  });
  const row = 5 + menu.length;
  drawText(v, 0, row, (sel === menu.length ? '>' : ' ') + ' BUY');
  drawText(v, 10, row, (sel === menu.length + 1 ? '>' : ' ') + ' DONE');
}
