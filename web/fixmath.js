// Целочисленная арифметика профиля Вектора. Только то, что 8080 делает подпрограммами:
// сложение, вычитание, сдвиги, умножение 16×16→32, деление 32/16, таблицы.
// Никаких Math.* с дробным результатом.
//
// Формат координат и скоростей — знаковый Q16.16 в 32 битах: значение = raw / 2^16.
// Диапазон ±32767.99998: y = −5000 и скорость 20 умещаются, запас до ±32768.
// Младший разряд 1/65536 ≈ 1.526e-5. Ветер 1 даёт 0.00002 за подшаг — это не кратно
// разряду, поэтому приращения тяжести и ветра копятся рациональным аккумулятором (dda),
// а не усечённой константой. Округление умножения и деления: до ближайшего, середина — от нуля.

export const FRAC = 16;
export const ONE = 65536;                 // 1.0
export const RAW_MIN = -0x80000000;
export const RAW_MAX = 0x7fffffff;

// Отладочная проверка разрядности. Переполнение — исключение, не усечение.
export let debug = true;
export function setDebug(on) { debug = on; }

/** raw — целое Q16.16 в диапазоне int32. */
export function guard(raw, op) {
  if (!debug) return raw;
  if (!Number.isInteger(raw) || raw < RAW_MIN || raw > RAW_MAX) {
    throw new Error(`fixmath: переполнение ${op}: ${raw}`);
  }
  return raw;
}

// --- константы Q16.16 (до ближайшего, середина — от нуля / Math.round) ---
// 1.5 точно; 1.2 → 78643.2; 1.01 → 66191.36; 1.8 → 117964.8; 0.7 → 45875.2;
// 0.1 → 6553.6; 0.007 → 458.752.
export const K15 = 98304;
export const K12 = 78643;
export const HERB = 66191;
export const K18 = 117965;
export const K07 = 45875;
export const VX0 = 32768;                 // 0.5 точно
export const VY0 = 6554;
export const G0 = 459;

// Пороги Random < p: сравниваются старшие 16 бит RandSeed. T = round(p · 65536).
// p = 1/2 режется поровну: «> 1/2» ↔ hi ≥ 32768, «≤ 1/2» ↔ hi < 32768.
export const TH = { p20: 13107, p10: 6554, p05: 3277, p50: 32768 };

// Синус 0..90° в Q16.16, 91·4 = 364 байта. Значение — round(sin_RTL(°)·2^16)
// из web/data/trig.json (второй компонент, Real48 RTL TP6). cos(d) = sin(90−d).
// sin(90) = 65536 ровно (1.0): в таблице это два слова 0001h,0000h.
export const SIN = new Int32Array([
  0, 1144, 2287, 3430, 4572, 5712, 6850, 7987, 9121, 10252, 11380, 12505, 13626, 14742, 15855,
  16962, 18064, 19161, 20252, 21336, 22415, 23486, 24550, 25607, 26656, 27697, 28729, 29753,
  30767, 31772, 32768, 33754, 34729, 35693, 36647, 37590, 38521, 39441, 40348, 41243, 42126,
  42995, 43852, 44695, 45525, 46341, 47143, 47930, 48703, 49461, 50203, 50931, 51643, 52339,
  53020, 53684, 54332, 54963, 55578, 56175, 56756, 57319, 57865, 58393, 58903, 59396, 59870,
  60326, 60764, 61183, 61584, 61966, 62328, 62672, 62997, 63303, 63589, 63856, 64104, 64332,
  64540, 64729, 64898, 65048, 65177, 65287, 65376, 65446, 65496, 65526, 65536,
]);

// Тангенс 0..89° в Q16.16, 90·4 = 360 байта. tan(d) = sin(d)/cos(d) тем же делением, что div().
// tan(90) нет: арктангенс конечного отношения не достигает 90°.
const TAN = new Int32Array(90);

// Заявленная абсолютная ошибка (в значении, не в raw). Проверяет web/test/fixmath_test.mjs.
export const CLAIM = {
  mul: 0.5 / 65536,
  div: 0.5 / 65536,
  idiv: 0.5 / 65536,
  sqrt: 0.5 / 65536,
  hypot: 0.5 / 65536,
  sin: 1 / 65536,          // относительно Math.sin; к RTL, из которого округляли, — 0.5 младшего разряда
  atanDeg: 1,              // градус; почти везде 0, на границе градуса — 1
};

// --- примитивы 16×16 и 32/16 ---

/** Беззнаковое 16×16 → 32. Входы берутся по младшим 16 битам. */
export function mul16u(a, b) {
  return (a & 0xffff) * (b & 0xffff);
}

// Знаковое 32×32 → 64 через четыре mul16u. Знак выносится, модуль до 2^31 включительно
// (отрицание int32-минимума) режется на половины обычным делением, не сдвигом JS:
// оператор >> в JS сужает к int32 и ломает 2^31.
function mul32to64(a, b) {
  const neg = (a < 0) !== (b < 0);
  const ua = a < 0 ? -a : a;
  const ub = b < 0 ? -b : b;
  const a0 = ua & 0xffff, a1 = Math.floor(ua / 65536);
  const b0 = ub & 0xffff, b1 = Math.floor(ub / 65536);
  // a1, b1 — 0..32768. Произведения половин — точные числа JS (< 2^53).
  const p00 = mul16u(a0, b0);
  const p01 = mul16u(a0, b1);
  const p10 = mul16u(a1, b0);
  const p11 = mul16u(a1, b1);
  let r = (BigInt(p11) << 32n) + (BigInt(p01 + p10) << 16n) + BigInt(p00);
  return neg ? -r : r;
}

/** Беззнаковое 32/16 → [частное, остаток]. Частное может быть шире 16 бит (на 8080 это длинное деление). */
export function div32u16(n, d) {
  if (d >>> 0 !== d || d === 0 || d > 0xffff) throw new Error('fixmath: div32u16 делитель ' + d);
  if (n >>> 0 !== n) throw new Error('fixmath: div32u16 делимое ' + n);
  const q = Math.floor(n / d);
  return [q, n - q * d];
}

function roundDiv(num, den) {
  // num, den — BigInt. Частное до ближайшего, середина от нуля.
  if (den === 0n) throw new Error('fixmath: деление на 0');
  const neg = (num < 0n) !== (den < 0n);
  const an = num < 0n ? -num : num;
  const ad = den < 0n ? -den : den;
  const q = (an + (ad >> 1n)) / ad;
  return neg ? -q : q;
}

// --- Q16.16 ---

/** Целое число точек → Q16.16. */
export function fromInt(n) {
  if (debug && !Number.isInteger(n)) throw new Error('fixmath: fromInt не целое ' + n);
  return guard(n * ONE, 'fromInt');
}

/** Q16.16 → целое, усечение к нулю (как SYSTEM_Trunc). */
export function trunc(raw) {
  return Math.trunc(raw / ONE);
}

export function neg(a) { return guard(-a, 'neg'); }
export function abs(a) { return a < 0 ? guard(-a, 'abs') : a; }
export function add(a, b) { return guard(a + b, 'add'); }
export function sub(a, b) { return guard(a - b, 'sub'); }

/** Q16.16 × Q16.16 → Q16.16. Округление до ближайшего, середина от нуля. Ошибка ≤ 1/2 младшего разряда. */
export function mul(a, b) {
  const p = mul32to64(a, b);             // Q32.32
  const half = 1n << BigInt(FRAC - 1);
  const neg = p < 0n;
  const r = ((neg ? -p : p) + half) >> BigInt(FRAC);
  return guard(Number(neg ? -r : r), 'mul');
}

/** Q16.16 × маленькое целое. Точно, если произведение влезает в int32. */
export function mulInt(a, n) {
  if (debug && !Number.isInteger(n)) throw new Error('fixmath: mulInt не целое ' + n);
  return guard(a * n, 'mulInt');
}

/** Q16.16 / Q16.16 → Q16.16. Делимое — это (a<<16), 48 бит; делитель 32 бита.
 *  На 8080 — восстанавливающее деление сдвигом и вычитанием. Ошибка ≤ 1/2 младшего разряда.
 *  Деление на 0 даёт 0: так q() в вещественной модели обнуляет неконечный результат. */
export function div(a, b) {
  if (b === 0) return 0;
  return guard(Number(roundDiv(BigInt(a) << BigInt(FRAC), BigInt(b))), 'div');
}

/** Q16.16 / целое (делитель 1..65535) → Q16.16. Одно беззнаковое деление 32/16 со знаком.
 *  Округление до ближайшего, середина от нуля. Ошибка ≤ 1/2 младшего разряда. */
export function idiv(a, n) {
  if (!Number.isInteger(n) || n === 0) throw new Error('fixmath: idiv делитель ' + n);
  const neg = (a < 0) !== (n < 0);
  const an = a < 0 ? -a : a;
  const ad = n < 0 ? -n : n;
  if (ad > 0xffff) throw new Error('fixmath: idiv делитель шире 16 бит ' + n);
  const num = an + Math.floor(ad / 2);             // ≤ 2^31 + 2^15, влезает в 32 бита
  const [q] = div32u16(num, ad);
  return guard(neg ? -q : q, 'idiv');
}

/** Широкое Q16.16: произведение и частное в BigInt (до 64 бит). Нужно планировщику,
 *  когда квадрат времени не влезает в ±32768. На 8080 это те же mul16, только аккумулятор длиннее. */
export function mulWide(a, b) {
  const p = mul32to64(a, b);
  const half = 1n << BigInt(FRAC - 1);
  const neg = p < 0n;
  const r = ((neg ? -p : p) + half) >> BigInt(FRAC);
  return neg ? -r : r;
}
export function divWide(num, den) {
  if (den === 0n) return 0n;
  return roundDiv(num << BigInt(FRAC), den);
}
export function narrow(w, op) { return guard(Number(w), op); }

/** Целый квадратный корень Q16.16, аргумент ≥ 0. sqrt(raw/2^16) = isqrt(raw·2^16) / 2^16,
 *  то есть isqrt(raw<<16). Ньютон, на 8080 — деления. Округление до ближайшего, середина вверх. Ошибка ≤ 1/2 разряда. */
export function sqrt(raw) {
  if (raw < 0) throw new Error('fixmath: sqrt < 0');
  if (raw === 0) return 0;
  return guard(Number(isqrtRound(BigInt(raw) << BigInt(FRAC))), 'sqrt');
}

/** Гипотенуза двух Q16.16. Сумма квадратов копится в 64 битах (Q32.32), корень — снова Q16.16.
 *  Квадрат расстояния в 300 точек в Q16.16 не влезает, поэтому квадрат не сужается. */
export function hypot(a, b) {
  const s = BigInt(a) * BigInt(a) + BigInt(b) * BigInt(b);
  if (s === 0n) return 0;
  return guard(Number(isqrtRound(s)), 'hypot');
}

function isqrtFloor(n) {
  if (n < 2n) return n;
  let x = n, y = (x + 1n) >> 1n;
  while (y < x) { x = y; y = (x + n / x) >> 1n; }
  return x;
}
function isqrtRound(n) {
  const r = isqrtFloor(n);
  const lo = n - r * r;
  const hi = (r + 1n) * (r + 1n) - n;
  return lo >= hi ? r + 1n : r;       // середина — вверх (от нуля)
}

/** trunc(n − m/2) к нулю. m/2 точно в Q16.16: половина — это m·32768. n, m — обычные целые. */
export function truncSubHalf(n, m) {
  const raw = n * ONE - m * (ONE >> 1);
  if (!Number.isSafeInteger(raw)) throw new Error('fixmath: truncSubHalf ' + raw);
  return Math.trunc(raw / ONE);
}

/** Аккумулятор рационального приращения. rem += inc; q = trunc(rem/den); rem -= q·den.
 *  Среднее q за много шагов равно inc/den, остаток ограничен. rem — обычное целое. */
export function dda(rem, inc, den) {
  const r = rem + inc;
  const q = Math.trunc(r / den);
  return [r - q * den, q];
}

// Тяжесть подшага: +0.01 = +1/100 к скорости. 0.01·2^16 = 655.36 = 16384/25.
export const G_INC = 16384, G_DEN = 25;
// Ветер подшага: +wind/50000. wind·2^16/50000 = wind·4096/3125.
export const W_MUL = 4096, W_DEN = 3125;

/** [cos, sin] угла в градусах, Q16.16. Отрицательные и ≥360 сворачиваются. Вне 0..90 — симметрия. */
export function sincos(deg) {
  let d = deg % 360;
  if (d < 0) d += 360;
  const q = (d / 90) | 0;
  const r = d - q * 90;
  const s = SIN[r];
  const c = SIN[90 - r];
  if (q === 0) return [c, s];
  if (q === 1) return [-s, c];
  if (q === 2) return [-c, -s];
  return [s, -c];
}

/** Арктангенс отношения Q16.16, целые градусы −89..89, усечение к нулю.
 *  Поиск наибольшего d, для которого tan(d) ≤ |x|. Ошибка относительно trunc(atan·180/π) — не больше 1°. */
export function atanDeg(raw) {
  const neg = raw < 0;
  const a = neg ? -raw : raw;
  let lo = 0, hi = 89;
  while (lo < hi) {
    const mid = (lo + hi + 1) >> 1;
    if (TAN[mid] <= a) lo = mid;
    else hi = mid - 1;
  }
  return neg ? -lo : lo;
}

/** Старшие 16 бит следующего RandSeed, 0..65535. Один шаг LCG. */
export function rndHi(rng) { return rng._next() >>> 16; }

/** Random < p, p задан порогом старших 16 бит. */
export function rndLt(rng, thresh) { return rndHi(rng) < thresh; }

/** (hi/65536) ≤ numer/denom. Для «Random·100 ≤ percent»: numer=percent, denom=100. */
export function rndLeRatio(rng, numer, denom) {
  return rndHi(rng) * denom <= numer * 65536;
}
/** (hi/65536) < numer/denom. */
export function rndLtRatio(rng, numer, denom) {
  return rndHi(rng) * denom < numer * 65536;
}

/** Случайная дробь [0, 1) в Q16.16: старшие 16 бит RandSeed как есть. */
export function rndUnit(rng) { return rndHi(rng); }

for (let d = 0; d < 90; d++) TAN[d] = div(SIN[d], SIN[90 - d]);
