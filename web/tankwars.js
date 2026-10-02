// Tank Wars 2.5 — эталонная модель на JS (ES-модуль для браузера и node).
// Побитный перенос scripts/ref/*.py; каждая функция сверена с настоящей игрой (web/test/run_fixtures.mjs).
// Адреса в комментариях — Ghidra (re/bomb25_flat.exe). Экран — 320×200 байт (индексы цветов VGA).

export const W = 320, H = 200, SCREEN = W * H;

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

// ---------- ГСЧ TP6 (1c5b:1639/15ea/1600) ----------
export class TPRandom {
  constructor(seed) { this.seed = seed >>> 0; }
  _next() { this.seed = (Number((BigInt(this.seed) * 0x08088405n + 1n) & 0xffffffffn)) >>> 0; return this.seed; }
  word(n) { const hi = this._next() >>> 16; return n ? hi % n : 0; }
  real() { return this._next() / 4294967296; }
}

// ---------- примитивы VRAM ----------
const off16 = (x, y) => ((y * W + x) & 0xffff);
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
export function drawFrame(v, rebound) {            // 2b39:0386
  rect(v, 8, 28, 312, 192, 13); rect(v, 10, 30, 310, 190, 13);
  if (!rebound) line(v, 11, 189, 309, 189, 2);
}

// ---------- небо (Background 6) ----------
export function skyBackground() {
  const v = new Uint8Array(SCREEN);
  for (let y = 31; y <= 189; y++) for (let x = 11; x <= 309; x++) v[y * W + x] = 30 + ((y - 30) >> 3);
  rect(v, 8, 28, 312, 192, 13); rect(v, 10, 30, 310, 190, 13);
  return v;
}

// ---------- рельеф (2eef:0a4f..0dbc) ----------
const P_STEER = 0.20000000000004547, P_FLIP = 0.10000000000002274;
export function generateTerrain(rng, players) {
  const cols = []; let d = 1 - 2 * rng.word(2); const m = 60 - 7 * (players - 2);
  let h = rng.word(150), s = 0, x = 11;
  const col = (xx, hh) => cols.push([xx, 190 - hh]);
  const st = (hh) => (s > 0 ? hh + 1 : hh - 1);
  while (x < 0x136) {
    if (m + 11 > x || 0x135 - m < x) { col(x, h); x++; continue; }
    const a = Math.abs(s);
    if (s === 0) { col(x, h); x++; col(x, h); x++; col(x, h); }
    if (a === 1) { col(x, h); x++; col(x, h); x++; h = st(h); col(x, h); }
    if (a === 2) { col(x, h); x++; h = st(h); col(x, h); x++; h = st(h); col(x, h); }
    if (a === 3) { col(x, h); x++; h = st(h); col(x, h); h = st(h); }
    if (a === 4) { col(x, h); h = st(h); h = st(h); }
    if (rng.real() < P_STEER) s += d;
    if (rng.real() < P_FLIP || Math.abs(s) > 4) d = -d;
    s = Math.max(-4, Math.min(4, s));
    if (h <= 20) d = 1; if (h >= 140) d = -1; if (h <= 3) s = 1; if (h >= 155) s = -1;
    x++;
  }
  return { cols, hFinal: h };
}
export function renderTerrain(t, v) {
  for (const [x, top] of t.cols) { const y0 = Math.min(top, 189), y1 = Math.max(top, 189); for (let y = y0; y <= y1; y++) if (y >= 0 && y < H && x >= 0 && x < W) v[y * W + x] = 2; }
  return v;
}

// ---------- танки ----------
export const SPRITE = [[0,0],[1,0],[2,0],[3,0],[4,0],[-1,0],[-2,0],[-3,0],[-4,0],
  [0,-1],[-2,-1],[-3,-1],[-4,-1],[2,-1],[3,-1],[4,-1],
  [0,-2],[-1,-2],[-2,-2],[-3,-2],[1,-2],[2,-2],[3,-2],
  [0,-3],[-1,-3],[-2,-3],[-3,-3],[1,-3],[2,-3],[3,-3],[0,-4],[-1,-4],[1,-4]];
const SUPPORT = (c) => c === 2 || c === 13;
export function drawTank(v, x, y, c) { const b = off16(x, y); for (const [dx, dy] of SPRITE) poke(v, (b + dy * W + dx) & 0xffff, c); }
export function eraseTank(v, bg, x, y) { const b = off16(x, y); for (const [dx, dy] of SPRITE) { const o = (b + dy * W + dx) & 0xffff; poke(v, o, peek(bg, o)); } }
function barrelOf(a) { return BARREL[a >= 0 ? a % 361 : ((a % 360) + 360) % 360]; }
export function drawTankBarrel(v, t) {
  if (!t.alive) return;
  drawTank(v, t.x, t.y, t.idx + 19);
  const [dx, dy] = barrelOf(t.angle);
  line(v, t.x, t.y, t.x + dx * t.facing, t.y - dy, t.idx + 19);
}
const sup = (v, x, y) => SUPPORT(peek(v, off16(x, y + 1)));
export function placeTanks(rng, players, v, bg, rebound = false) {
  const ts = [];
  for (let i = 1; i <= players; i++) ts.push({ idx: i, x: 0, y: 0, angle: 90, power: 200, facing: 1, men: 100, alive: true, shield: 0, damp: 0, score: 0, energy: 1000, weapon: 1 });
  const first = rng.word(28) + 16, last = 0x131 - rng.word(28);
  ts[0].x = first; ts[players - 1].x = last;
  const q2 = trunc((last - first) / (players - 1));
  for (let i = 2; i < players; i++) ts[i - 1].x = (i - 1) * q2 + first;
  for (const t of ts) {
    t.angle = (t.idx === 1 || t.idx === players) ? 75 : 90;
    t.facing = t.idx === players ? -1 : 1; t.y = 32;
    let any = false; for (let dx = -4; dx <= 4; dx++) if (sup(v, t.x + dx, t.y)) any = true;
    if (!any) {
      for (;;) {
        eraseTank(v, bg, t.x, t.y); t.y++; drawTank(v, t.x, t.y, t.idx + 19);
        let all = true; for (let dx = -4; dx <= 4; dx++) if (!sup(v, t.x + dx, t.y)) all = false;
        if (all) break;
      }
      drawTankBarrel(v, t); drawFrame(v, rebound);
    }
  }
  return ts;
}

// ---------- осыпание (1062:027e) и падение танков (2b39:0020) ----------
const fallable = (c) => c === 0 || (c >= 30 && c <= 99);
export function crumble(v, bg) {
  const lst = [];
  for (let bx = 0xEEC0; bx > 0; bx--) if (v[bx] === 2 && fallable(v[bx + W])) { v[bx] = bg[bx]; v[bx + W] = 2; lst.push(bx + W); }
  if (!lst.length) return 0;
  let passes = 0;
  for (;;) {
    let moved = false; passes++;
    for (let i = 0; i < lst.length; i++) {
      const e = lst[i]; if (e === 0) continue;
      if (e + W < v.length && fallable(v[e + W])) { v[e] = bg[e]; v[e + W] = 2; lst[i] = e + W; moved = true; } else lst[i] = 0;
    }
    if (!moved) return passes;
  }
}
export function crumbleGate(v, bg, rng, percent, rebound) {      // 2b39:03da
  drawFrame(v, rebound);
  if (rng.real() * 100 <= percent) { crumble(v, bg); return true; }
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
      drawTank(v, ox, oy, t.idx + 19);
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
  for (const [x, y] of ellipsePoints(cx + vp[0], cy + vp[1], r, r)) if (!clip || inVp(x, y, vp)) poke(v, (y * W + x) & 0xffff, color);
}
export function ringRestore(v, bg, cx, cy, r, vp = VIEWPORT, clip = true) {
  for (const [x, y] of ellipsePoints(cx + vp[0], cy + vp[1], r, r)) if (!clip || inVp(x, y, vp)) { const o = (y * W + x) & 0xffff; poke(v, o, peek(bg, o)); }
}

// ---------- обычный взрыв 318e:00e0 (оружие 1,2,3,4,11) ----------
export const RADIUS = { 1: 10, 2: 15, 3: 30, 4: 60, 11: 2 };
const K15 = 1.5, K18 = 1.7999999999992724, K07 = 0.6999999999998181;
function applyDamage(players, victim, shooter, dmg) {
  victim.shield -= dmg;
  if (victim.shield < 0) {
    if (victim.idx !== shooter) players[shooter - 1].score -= victim.shield * 10;
    victim.men += victim.shield; victim.shield = 0;
  }
}
export function explode(v, bg, players, x, y, hit, shooter, weapon, rng, sound) {
  if (!(weapon in RADIUS)) return null;
  const r = RADIUS[weapon], cx = trunc(x - 11), cy = trunc(y - 31);
  for (let i = 0; i <= r; i++) for (const dx of [1, -1, 0]) ring(v, cx + dx, cy, i, 0x82 + i);
  if (sound && rng) {
    const T = (r + 1) * (r + 2) / 2;
    for (let i = 0; i < r + 1 + 2 * T; i++) rng.word(500);
    for (let i = 0; i < T; i++) rng.word(250);
  }
  for (let i = r; i >= 0; i--) for (const dx of [1, -1, 0]) ringRestore(v, bg, cx + dx, cy, i);
  if (hit >= 20 && hit <= 29) applyDamage(players, players[hit - 20], shooter, 200);
  for (const p of players) {
    if (!p.alive) continue;
    const ddx = x - p.x, ddy = y - p.y, d = Math.sqrt(ddx * ddx + ddy * ddy);
    let dmg = 0;
    if (!(r * K15 < d)) dmg += trunc(r * K18 - d);
    if (r > d) dmg += 10 + 2 * trunc(r * K18 - d);
    if (r * K07 > d) dmg += 150;
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
  const ix = trunc(x), iy = trunc(y);
  ellipseRestoreVp(v, bg, ix, iy, 1, 1, vp, clip);
  pixBg(v, bg, ix, iy);
  crumble(v, bg);
}
const CRI_RADIUS = { 5: 4, 6: 4, 7: 8, 8: 8, 9: 20, 10: 20 }, CRI_FLUENT = new Set([6, 8, 10]);
const DIR = { 1: [0, -1], 2: [1, -1], 3: [1, 0], 4: [1, 1], 5: [0, 1], 6: [-1, 1], 7: [-1, 0], 8: [-1, -1] };
export function cri(v, bg, players, x, y, hit, shooter, weapon, rng, sound) {      // 6..10
  if (!(weapon in CRI_RADIUS)) return;
  if (hit >= 20 && hit <= 29) {          // 318e:091c — урон со щита, перелив в men (16 бит) и очки
    const dmg = rng.word(weapon * 6) + 1, vic = players[hit - 20];
    vic.shield -= dmg;
    if (vic.shield < 0) {
      vic.men = ((vic.men + (vic.shield & 0xffff)) << 16) >> 16;
      if (vic.idx !== shooter && shooter >= 1 && shooter <= players.length) players[shooter - 1].score -= vic.shield * 10;
      vic.shield = 0;
    }
    return;
  }
  if (hit !== 2) return;
  const radius = CRI_RADIUS[weapon], fluent = CRI_FLUENT.has(weapon);
  let cx = trunc(x), cy = trunc(y);
  while (![[-1, 0], [1, 0], [0, -1], [0, 1]].some(([dx, dy]) => atv(v, cx + dx, cy + dy) === 2)) cy++;
  const pts = Array.from({ length: 22 }, () => [0, 0]);
  for (let i = 1; i <= radius; i++) pts[i] = [cx, cy];
  for (;;) {
    for (let i = 1; i <= radius; i++) {
      const dirs = [], [px, py] = pts[i];
      for (let d = 1; d <= 8; d++) { if (d % 2 === 0 && !fluent) continue; const [dx, dy] = DIR[d]; if (atv(v, px + dx, py + dy) === 2) dirs.push(d); }
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
  const r = DIRT_RADIUS[weapon], lx = x - vp[0], ly = y - vp[1], cy = trunc(ly);
  const centers = [trunc(lx + 1), trunc(lx - 1), trunc(lx)];
  for (let i = 0; i <= r; i++) for (const cx of centers) ring(v, cx, cy, i, 2, vp);
}
export function explosiveDirt(v, bg, x, y, rng, sound, percent, vp = VIEWPORT) {   // 17
  const n = rng.word(100) + 300, rows = rng.word(8) + 3;
  const tx = trunc(x - vp[0]), ty = trunc(y - vp[1]), pts = [];
  for (let row = 1; row <= rows; row++) for (let c = 0; c < n; c++) {
    const span = rng.word(row * 10), jitter = trunc(rng.word(span + 1) - span / 2.0);
    pts.push([tx + jitter, ty - span + 2]);
  }
  for (const [px, py] of pts) {
    if (vp[0] <= px + vp[0] && px + vp[0] <= vp[2] && vp[1] <= py + vp[1] && py + vp[1] <= vp[3]) { const X = px + vp[0], Y = py + vp[1]; if (X >= 0 && X < W && Y >= 0 && Y < H) v[Y * W + X] = 2; }
    if (sound) rng.word(200);
  }
  if (rng.real() * 100.0 < percent * 2) crumble(v, bg);
}

// Laser 2583:140f..24c5 (оружие 5). shooter — объект танка; players — массив танков.
const LASER_P = 0.20000000000004547, BEAM = 0xfe;
const inField = (x, y) => x >= 11 && x <= 309 && y >= 31 && y <= 189;
function trigOf(a) { return TRIG[a in TRIG ? a : ((a % 360) + 360) % 360]; }
export function laser(v, bg, players, shooterIdx, rng, sound, rebound = false) {
  const t = players[shooterIdx - 1];
  let power = t.power; if (power === 0) return;
  if (power > t.energy) { power = t.energy; t.power = power; }
  t.energy -= power;
  const [bdx, bdy] = barrelOf(t.angle);
  line(v, t.x, t.y, t.x + bdx * t.facing, t.y - bdy, BEAM);
  drawTank(v, t.x, t.y, shooterIdx + 19);
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
    if (c === 2) {
      for (let k = 1; k <= 15; k++) {
        const gx = trunc(q(X - q(rng.word(20) * dx))), gy = trunc(q(Y - q(rng.word(20) * dy)));
        if (sound) rng.word((500 * k) & 0xffff);
        const gc = gp(gx, gy);
        if (inField(gx, gy) && !(gc >= 20 && gc <= 29) && gc !== BEAM) poke(v, off16(gx, gy), bg[off16(gx, gy)]);
      }
    }
    if (c > 19 && c < 30 && players[c - 20] && players[c - 20].men > 0) {
      counter -= 10;
      const vic = players[c - 20];
      if (vic.shield <= 0) {
        const pts = [];
        for (let k = 1; k <= 15; k++) {
          let sx, sy;
          for (;;) {
            sx = trunc(q(q(X - rng.word(40)) + 20)); sy = trunc(q(q(Y - rng.word(40)) + 20));
            const gc = gp(sx, sy);
            if (gc === c || gc < 20 || (gc !== BEAM && gc > 29)) break;
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
      if (dx < 0 && X <= 11 && dx !== 0) dx = -dx;
      if (dx > 0 && X >= 309 && dx !== 0) dx = -dx;
      if (dy < 0 && Y <= 31 && dy !== 0) dy = -dy;
      if (dy > 0 && Y >= 189 && dy !== 0) dy = -dy;
    } else if ((dx < 0 && X <= 11) || (dx > 0 && X >= 309) || (dy < 0 && Y <= 31) || (dy > 0 && Y >= 189)) done = true;
    if (!done) poke(v, off16(trunc(X), trunc(Y)), BEAM);
    if (counter <= 0) done = true;
    if (done) break;
  }
  for (let o = 64000; o > 0; o--) if (o < v.length && v[o] === BEAM) v[o] = bg[o];
}

// ---------- полёт снаряда 2583:01c0 (+ наведение 2583:06cf) ----------
const PI48 = real48ToFloat(new Uint8Array([0x82, 0x21, 0xa2, 0xda, 0x0f, 0x49]));
const D180 = real48ToFloat(new Uint8Array([0x88, 0x00, 0x00, 0x00, 0x00, 0x34]));
export const degToRad = (d) => q(q(q(d) / D180) * PI48);
const DIAMOND = [[-1, 0], [0, -1], [0, 0], [0, 1], [1, 0]];
const isHit = (c) => c === 2 || (c >= 20 && c <= 29);
const HERB = 1.0100000000002183;
export function flight(inp, getPixel, onStep = null) {
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
    const inBand = y < 189 && x < 309 && y > 33 && x > 11;
    if (inBand) {
      hit = 0; let stopped = false;
      for (const [dx, dy] of DIAMOND) {
        const cp = getPixel(px + dx, py + dy);
        if (isHit(cp)) {
          hit = cp;
          const tank = cp >= 20 && cp <= 29;
          let st = tank || sub === step || inp.power < fuse;
          if (cp === 2 && inp.power === fuse) st = false;
          if (st) {
            if (tank && inp.weapon >= 12 && inp.weapon <= 16) vy = q(-vy * 1.2);
            else { stop = tank ? 'tank' : 'terrain'; stopped = true; break; }
          }
        }
      }
      if (stopped) break;
    } else if (inp.rebound) {
      if (vx < 0 && x < 10) vx = q(-vx); if (vx > 0 && x > 310) vx = q(-vx);
      if (vy < 0 && y < 30) vy = q(-vy); if (vy > 0 && y > 190) vy = q(-vy);
    } else if (!guided) {
      if (vx > 1 && x > 310 && inp.wind > 0) y = 200;
      if (vx < 1 && x < 10 && inp.wind < 0) y = 200;
    }
    if (y < -5000 || y > 193) { stop = 'bounds'; break; }
  }
  return { positions, stop, hit, x, y };
}

// ---------- ветер на раунд (2583:2567..2675) ----------
const SPANS = [0, 20, 100, 300, 4000], WTHR = [0.1, 0.1, 0.05, 0.05].map(q);
export function generateWind(rng, mode) {
  let eff = mode === 5 ? rng.word(5) : mode;
  const span = SPANS[eff] || 0;
  let w = ((span >> 1) - rng.word(span)) << 16 >> 16;
  for (const th of WTHR) if (rng.real() < th) w = ((w << 2) & 0xffff) << 16 >> 16;
  return Math.max(-30000, Math.min(30000, w));
}
