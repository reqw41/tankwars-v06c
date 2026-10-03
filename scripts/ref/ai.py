"""ИИ Tank Wars 2.5: 2cab:000d (через стаб 1049:0020) и цикл хода компьютера 2b39:0425 / 2b39:0f78.

Структура игрока (DS:8896 + 0x802*p): +0 число выстрелов (история), +2 флаг «план готов»,
+3 мощность, +5 угол, +7 направление, +9 оружие (план), +0x0b+10k — выстрел k: угол, мощность, направление,
x, y точки попадания; +0x7e6 цель, +0x7e8/+0x7ea dx/dy, +0x7ea+2k — оценки игроков.
Тип ИИ — по имени игрока: Mr. Stupid 1, Birdy Bonker 2 (скрытый), Rifleman 3, Lobber 4, Lob & Shoot 5
(без отражающих стен = 4, иначе 3), Windless Wit 6, Twanger 7 (без стен = 3).
Коды «нажатий»: 1/2 угол (± направление), 3/4 мощность −1/+1, 5 огонь, 6 развернуть, 7/8 оружие −1/+1.
"""
from __future__ import annotations

import math
import struct

AI_NAMES = {b'Mr. Stupid': 1, b'Birdy Bonker': 2, b'Rifleman': 3, b'Lobber': 4, b'Lob & Shoot': 5,
            b'Windless Wit': 6, b'Twanger': 7}
HIST_LEN = 0x802


class Hist:
    """Структура игрока 0x802 байт (bytearray)."""
    def __init__(self, raw: bytes):
        self.b = bytearray(raw)

    def w(self, o):
        return struct.unpack_from('<h', self.b, o)[0]

    def sw(self, o, v):
        struct.pack_into('<h', self.b, o, ((v + 0x8000) & 0xFFFF) - 0x8000)

    planned = property(lambda s: s.b[2], lambda s, v: s.b.__setitem__(2, v & 0xFF))
    power = property(lambda s: s.w(3), lambda s, v: s.sw(3, v))
    angle = property(lambda s: s.w(5), lambda s, v: s.sw(5, v))
    facing = property(lambda s: s.w(7), lambda s, v: s.sw(7, v))
    weapon = property(lambda s: s.w(9), lambda s, v: s.sw(9, v))


def ai_type(name: bytes, rebound: bool) -> int:
    t = AI_NAMES.get(name, 0)
    if t == 5:
        t = 3 if rebound else 4
    if t == 7 and not rebound:
        t = 3
    return t


def choose_code(p, h: Hist) -> int:
    """2cab:213e..2431 — выбор кода по плану. p — game.P (поля мощность/угол/... меняются: шаги ±90/±9)."""
    while p.ammo(h.weapon) < 1:
        h.weapon = h.weapon - 1
        if h.weapon < 0:
            h.weapon = 12
    if 10 * p.men < h.power:
        h.power = 10 * p.men
    if p.energy < h.power and h.weapon == 5:
        h.power = p.energy
    if h.power < 0:
        h.power = 0
    code = 5
    t = math.trunc((p.facing - 1) / 2.0)
    if p.angle < h.angle:
        code = 1 - t
    if p.angle > h.angle:
        code = t + 2
    if p.power > h.power:
        code = 3
    if p.power < h.power:
        code = 4
    if p.facing != h.facing:
        code = 6
    if p.weapon != h.weapon:
        code = 8
    if code == 3 and p.power - h.power > 99:
        p.power -= 90
    if code == 3 and p.power - h.power > 9:
        p.power -= 9
    if code == 4 and h.power - p.power > 99:
        p.power += 90
    if code == 4 and h.power - p.power > 9:
        p.power += 9
    if code == 5:
        h.planned = 0
    return code


def apply_code(v, bg, p, code: int):
    """2b39:0577..0efe — применить код к записи игрока; меняет VRAM (ствол)."""
    try:
        from tanks import draw_tank_with_barrel, line, BARREL
    except ImportError:  # pragma: no cover
        from .tanks import draw_tank_with_barrel, line, BARREL

    def erase_barrel():
        bdx, bdy = BARREL[p.angle % 361 if p.angle >= 0 else p.angle % 360]
        line(v, p.x, p.y, p.x + bdx * p.facing, p.y - bdy, 0, bg=bg)

    if code in (7, 8):
        while True:
            if code == 7:
                p.weapon -= 1
            if code == 8:
                p.weapon += 1
            if p.weapon < 0:
                p.weapon = 17
            if p.weapon > 17:
                p.weapon = 0
            ok = p.ammo(p.weapon) > 0
            if p.ammo(p.weapon) < 100 and p.weapon == 5:
                ok = False
            if ok:
                break
    elif code in (1, 2):
        erase_barrel()
        if code == 2:
            p.angle -= p.facing
        if code == 1:
            p.angle += p.facing
        if p.angle > 90:
            p.facing = -p.facing
            p.angle = 180 - p.angle
        if p.angle < 0:
            p.facing = -p.facing
            p.angle = abs(p.angle)
        draw_tank_with_barrel(v, p)
    elif code in (3, 4):
        p.power += 1 if code == 4 else -1
        if p.power > 10 * p.men:
            p.power = 10 * p.men
        if p.power < 0:
            p.power = 0
        if p.power > p.energy and p.weapon == 5:
            p.power = p.energy
    elif code == 6:
        erase_barrel()
        p.facing = -p.facing
        draw_tank_with_barrel(v, p)


def computer_turn(v, bg, p, h: Hist, plan_fn, max_calls=5000):
    """2b39:0425 для компьютера: коды до огня. plan_fn(h) — планировщик ИИ (вызывается внутри, когда план не готов)."""
    codes = []
    for _ in range(max_calls):
        if p.ammo(p.weapon) <= 0 or (p.weapon == 5 and p.ammo(5) <= 100):
            code = 8                                         # 2b39:0f9d..0fef
        else:
            if not h.planned:
                plan_fn(h)
            code = choose_code(p, h)
        codes.append(code)
        apply_code(v, bg, p, code)
        if code == 5:
            break
    return codes


# ---------- планировщики (2cab:000d, ветки по типу) ----------
def _first_weapon(p, h: Hist):
    """Оружие 11 (Hand Grenade), затем последнее из 1..4, у которого есть патроны."""
    h.weapon = 11
    for w in range(1, 5):
        if p.ammo(w) > 0:
            h.weapon = w


def plan_stupid(v, bg, ps, p, h: Hist, rng, rebound: bool):
    """Тип 1, Mr. Stupid (2cab: ветка local_8 == 1)."""
    while True:
        h.facing = rng.word(3) - 1
        if abs(h.facing) == 1:
            break
    _first_weapon(p, h)
    h.angle = rng.word(90)
    h.power = rng.word(5000) + 20
    if not rebound:
        h.facing = -1 if len(ps) // 2 < p.idx else 1
        h.power = rng.word(250) + 50
    if 10 * p.men < h.power:
        h.power = 10 * p.men
    h.planned = 1


def plan_birdy(v, bg, ps, p, h: Hist, rng, rebound: bool):
    """Тип 2, Birdy Bonker: всегда вверх на 300."""
    h.weapon, h.facing, h.angle, h.power = 1, 1, 90, 300
    if 10 * p.men < h.power:
        h.power = 10 * p.men
    h.planned = 1


def _q(x: float) -> float:
    """Real48: мантисса 40 бит (округление к ближайшему)."""
    if x == 0:
        return 0.0
    m, e = math.frexp(x)
    return math.ldexp(round(m * (1 << 40)), e - 40)


def _shot(h: Hist, k: int):
    """Выстрел k истории: (угол, мощность, направление, x, y)."""
    o = 0x0b + 10 * k
    return h.w(o), h.w(o + 2), h.w(o + 4), h.w(o + 6), h.w(o + 8)


def _downgrade(p, h: Hist):
    """2cab:20b4: пока нет патронов — 4→3→2→1→11→0."""
    nxt = {11: 0, 1: 11, 2: 1, 3: 2, 4: 3}
    while p.ammo(h.weapon) < 1:
        h.weapon = nxt[h.weapon]


def plan_lobber(v, bg, ps, p, h: Hist, rng, rebound: bool):
    """Тип 4, Lobber (2cab:1b0b..213e): угол 75, мощность — линейная экстраполяция по двум последним выстрелам."""
    n_pl = len(ps)
    by = {t.idx: t for t in ps}
    target = p.idx
    h.weapon = 1 if p.ammo(1) >= 1 else 11
    best = 0x7FFF
    if abs(h.facing) != 1:
        h.facing = 1
    d = h.facing
    if (rng.real() <= 0.5) and h.w(0) == 1:
        d = -d
    if h.w(0) < 3:
        while True:
            target += d
            if target > n_pl:
                target = 1
            if target < 1:
                target = n_pl
            if target != p.idx and by[target].alive:
                break
    else:
        sx = _shot(h, h.w(0) - 1)[3]
        for k in range(1, n_pl + 1):
            if k != p.idx and abs(sx - by[k].x) < best and by[k].alive:
                target = k
                best = abs(sx - by[k].x)
    if target > n_pl:
        target = 1
    h.sw(0x7E6, target)
    if (h.facing == 1 and target < p.idx) or (h.facing == -1 and target > p.idx):
        h.sw(0, 1)
    h.facing = 1 if target > p.idx else -1
    n = h.w(0)
    if n == 1:
        h.angle = 75
        h.power = rng.word(100) + 100
        h.planned = 1
    elif n == 2:
        h.angle = 75
        h.power = rng.word(100) + 200
        h.planned = 1
    else:
        i, j = n - 2, n - 1
        si, sj = _shot(h, i), _shot(h, j)
        dx = (sj[3] - si[3]) or 1
        dp = (sj[1] - si[1]) or 1
        ratio = _q(dp / dx)
        miss = by[target].x - si[3]
        t = math.trunc(_q(miss * ratio))
        corr = int(math.fmod(t, 0x7FFF))
        h.planned = 1
        h.power = si[1] + corr
        if h.power < 0:
            h.power = -h.power * 2
        if abs(miss) > 5:
            h.weapon = 2
        if abs(miss) > 15:
            h.weapon = 3
        if abs(miss) > 30:
            h.weapon = 4
        _downgrade(p, h)


_RAD2DEG_PI = 3.1415926535883045     # Real48-константа π из GraphWrap (175e:0124)


def _hypot(a: float, b: float) -> float:
    return _q(math.sqrt(_q(_q(a * a) + _q(b * b))))


def _atan_deg(x: float) -> int:
    """Trunc(RadToDeg(ArcTan(x)))."""
    return math.trunc(_q(_q(_q(math.atan(x)) * 180.0) / _RAD2DEG_PI))


def _px(v, x, y):
    return v[y * 320 + x] if 0 <= x < 320 and 0 <= y < 200 else 0


def _put(v, x, y, c):
    if 0 <= x < 320 and 0 <= y < 200:
        v[y * 320 + x] = c


def plan_wit(v, bg, ps, p, h: Hist, rng, rebound: bool):
    """Тип 6, Windless Wit (2cab:014c..04df): точное решение параболы без ветра."""
    by = {t.idx: t for t in ps}
    while True:
        target = rng.word(len(ps)) + 1
        if target != p.idx and by[target].alive:
            break
    h.sw(0x7E6, target)
    t = by[target]
    dx, dy = t.x - p.x, t.y - p.y
    if dy < 0:
        dy += 4
    if dx > 0:
        dx -= 4
    if dx < 0:
        dx += 4
    h.sw(0x7E8, dx)
    h.sw(0x7EA, dy)
    r = rng.word(100) + 50
    vx = _q((r if target > p.idx else -r) / 50.0)
    tt = _q(dx / vx)
    vy = _q(_q(float(dy) - _q(_q(0.05000000000001137 * tt) * tt)) / tt)
    vy = _q(vy * 50.0)
    vx = _q(vx * 50.0)
    h.power = math.trunc(_hypot(vy, vx))
    h.angle = abs(_atan_deg(_q(vy / vx)))
    h.facing = 1 if target > p.idx else -1
    if 10 * p.men < h.power:
        h.power = 10 * p.men
    _first_weapon(p, h)
    h.planned = 1


def plan_rifleman(v, bg, ps, p, h: Hist, rng, rebound: bool):
    """Тип 3, Rifleman (2cab:0662..0e01): прямая наводка; цель — та, до которой меньше земли на луче."""
    by = {t.idx: t for t in ps}
    n_pl = len(ps)
    scr = bytearray(v)                       # лучи рисуются на экране и стираются в конце
    h.weapon = 1 if p.ammo(1) >= 1 else 11
    score = {}
    for k in range(1, n_pl + 1):
        t = by[k]
        s = 1000
        if t.y > p.y:
            s //= 10
        if k == p.idx or not t.alive:
            s = 0
        if s > 0:
            dx, dy = t.x - p.x, t.y - p.y
            dist = _hypot(float(dx), float(dy))
            for i in range(1, math.trunc(dist) + 1):
                X = p.x + math.trunc(_q(_q(dx / dist) * i))
                Y = p.y + math.trunc(_q(_q(dy / dist) * i))
                if _px(scr, X, Y) == 2:
                    s -= 1
                _put(scr, X, Y, k + 19)
        score[k] = s
        h.sw(0x7EA + 2 * k, s)
    best, target = -32767, 0
    for k in range(1, n_pl + 1):
        if score[k] > best:
            best, target = score[k], k
    h.sw(0x7E6, target)
    t = by[target]
    dx = t.x - p.x
    dy = p.y - t.y + 4
    dx = dx or 1
    dy = dy or 1
    h.sw(0x7E8, dx)
    h.sw(0x7EA, dy)
    sc = h.w(0x7EA + 2 * target)
    if sc > 990:
        for w, r in ((2, 15), (3, 30), (4, 60)):
            if _hypot(float(dx), float(dy)) > r and p.ammo(w) > 0:
                h.weapon = w
    if p.ammo(5) > 100 and sc <= 990:
        h.weapon = 5
    h.power = 1000
    h.angle = _atan_deg(_q(dy / dx))
    h.facing = -1 if target < p.idx else 1
    if h.angle < 0:
        h.angle = -h.angle
    if h.w(0x7EA) < 0:
        if rebound:
            h.angle = rng.word(70) + 10
        else:
            h.power = rng.word(100) + 200
            h.angle = 45
        h.weapon = 1
    h.planned = 1


def _vget(v, x, y):
    o = (y * 320 + x) & 0xFFFF
    return v[o] if o < 64000 else 0


def _vput(v, x, y, c):
    o = (y * 320 + x) & 0xFFFF
    if o < 64000:
        v[o] = c


CEILING = 28                                  # 2cab:0f23 — высота «потолка» для рикошета


def _twang_trace(scr, by, p, h: Hist, k: int, score: dict):
    """Луч от p вверх до потолка (земля −3 за пиксель) и от потолка до цели k (−1)."""
    t = by[k]
    dx, dy = t.x - p.x, p.y - t.y
    h.sw(0x7E8, dx)
    h.sw(0x7EA, dy)
    top = t.y - CEILING
    a = _q(math.atan(abs(_q((dy + 2 * top) / dx))))
    h.facing = -1 if k < p.idx else 1
    up = p.y - CEILING
    tan = _q(_q(math.sin(a)) / _q(math.cos(a)))
    ox = math.trunc(_q((h.facing * up) / tan))
    dist = _hypot(float(ox), float(up))
    for s in range(1, math.trunc(dist) + 1):
        X = math.trunc(_q(p.x + _q(_q(ox / dist) * s)))
        Y = math.trunc(_q(p.y - _q(_q(up / dist) * s)))
        if _vget(scr, X, Y) == 2:
            score[k] -= 3
        _vput(scr, X, Y, k + 19)
    lx, ly = p.x + ox, p.y - up
    ey, ex = t.y - ly, t.x - lx
    dist = _hypot(float(ex), float(ey))
    for s in range(1, math.trunc(dist) + 1):
        X = math.trunc(_q(lx + _q(_q(ex / dist) * s)))
        Y = math.trunc(_q(ly + _q(_q(ey / dist) * s)))
        if _vget(scr, X, Y) == 2:
            score[k] -= 1
        _vput(scr, X, Y, k + 19)


def plan_twanger(v, bg, ps, p, h: Hist, rng, rebound: bool):
    """Тип 7, Twanger (2cab:0e01..1b0b), только при отражающих стенах: выстрел рикошетом от потолка."""
    by = {t.idx: t for t in ps}
    n_pl = len(ps)
    scr = bytearray(v)
    h.weapon = 1
    score = {}
    for k in range(1, n_pl + 1):
        score[k] = 1000
        if k == p.idx or not by[k].alive:
            score[k] = -1
        if score[k] != -1:
            _twang_trace(scr, by, p, h, k, score)
    best, cnt = 0, 1
    rank = {k: 0 for k in range(1, n_pl + 1)}
    for k in range(1, n_pl + 1):
        if score[k] > best:
            cnt += 1
            best = score[k]
            rank[k] = cnt
        elif score[k] == best:
            rank[k] = cnt
    top_rank = max([0] + list(rank.values()))
    for k in rank:
        if rank[k] < top_rank:
            rank[k] = 0
    score = {k: 0 for k in range(1, 11)}
    for k in range(1, n_pl + 1):
        if rank[k]:
            score[k] = 1000 - math.trunc(_hypot(float(p.x - by[k].x), float(p.y - by[k].y)))
    best, target = 0, 0
    for k in range(1, n_pl + 1):
        if score[k] > best:
            best, target = score[k], k
    h.sw(0x7E6, target)
    scr = bytearray(v)
    score[target] = 1000
    _twang_trace(scr, by, p, h, target, score)
    for k in range(1, 11):
        h.sw(0x7EA + 2 * k, score[k])
    t = by[target]
    dx, dy = t.x - p.x, p.y - t.y
    h.sw(0x7E8, dx)
    h.sw(0x7EA, dy)
    top = t.y - CEILING
    h.power = rng.word(51) + 950
    h.angle = abs(_atan_deg(abs(_q((dy + 2 * top) / dx))))
    h.facing = -1 if target < p.idx else 1
    h.weapon = 1
    if score[target] > 990:
        for w, r in ((2, 15), (3, 30), (4, 60)):
            if _hypot(float(dx), float(dy)) > r and p.ammo(w) > 0:
                h.weapon = w
    if score[target] <= 990 and p.ammo(5) > 100:
        h.weapon = 5
    h.planned = 1


PLANNERS = {1: plan_stupid, 2: plan_birdy, 3: plan_rifleman, 4: plan_lobber, 6: plan_wit, 7: plan_twanger}


def plan(v, bg, ps, p, h: Hist, rng, rebound: bool, name: bytes):
    t = ai_type(name, rebound)
    fn = PLANNERS.get(t)
    if fn is None:
        raise NotImplementedError(f'ИИ типа {t}')
    fn(v, bg, ps, p, h, rng, rebound)


# ---------- история выстрелов (нужна Lobber) ----------
def turn_begin(h: Hist):
    """2583:27b9: в начале хода игрока счётчик истории +1 (у всех игроков, не только у компьютера)."""
    h.sw(0, h.w(0) + 1)


def record_shot(h: Hist, p, hit_x: float, hit_y: float):
    """2583:29ee..2af4: после выстрела — запись k = счётчик: точка остановки снаряда (Trunc Real DS:4332/4338;
    x > 32767 -> 0x7FFF), направление, мощность и угол игрока на момент выстрела."""
    o = 0x0b + 10 * h.w(0)
    tx = math.trunc(hit_x)
    h.sw(o + 6, 0x7FFF if tx > 0x7FFF else tx)
    h.sw(o + 8, math.trunc(hit_y))
    h.sw(o + 4, p.facing)
    h.sw(o + 2, p.power)
    h.sw(o, p.angle)
