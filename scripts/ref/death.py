"""Анимации гибели танка Tank Wars 2.5 (оверлей 285c), выбор варианта Random(7) в 2583:2bb9.

К моменту вызова жертва уже alive=0 (2583:2b57). Все функции меняют VRAM, записи танков и ГСЧ так же,
как оригинал (сверка — tests/test_death.py). Танки — объекты tanks.Tank с полями shield/damp (dict в ref-моделях
передаются через атрибуты), список players: индекс 0 = игрок 1.

  0  285c:0020  разлёт 11 обломков, мини-воронки, кольца вокруг танка r<=30 и воронка r=30
  1  285c:0f61(0) / 3 285c:0f61(1)  «фейерверк» частиц
  2  285c:1da5
  4  285c:28d9  фонтан земли
  5  285c:2b76  погас и исчез
  6  285c:2c29  1..4 взрыва растущего калибра в точке танка (от имени «призрака» игрока 0)
"""
from __future__ import annotations

import math
from typing import List

try:
    from tanks import draw_tank_with_barrel, erase_tank, line, BARREL
    from explosion import explode, Player
except ImportError:  # pragma: no cover
    from .tanks import draw_tank_with_barrel, erase_tank, line, BARREL
    from .explosion import explode, Player


def erase_tank_barrel(v: bytearray, bg: bytes, t) -> None:
    """1062:06b7: стереть корпус и ствол из буфера фона."""
    erase_tank(v, bg, t.x, t.y)
    bdx, bdy = BARREL[t.angle % 361 if t.angle >= 0 else t.angle % 360]
    line(v, t.x, t.y, t.x + bdx * t.facing, t.y - bdy, 0, bg=bg)


def _redraw_all(v, tanks):
    for t in tanks:
        draw_tank_with_barrel(v, t)


def death5(v, bg, tanks, victim, rng, sound):
    """285c:2b76: палитра 0..100..0 (VRAM не меняет, ГСЧ не тратит), men = -1, стереть танк."""
    t = tanks[victim - 1]
    t.men = -1
    erase_tank_barrel(v, bg, t)


def death4(v, bg, tanks, victim, rng, sound):
    """285c:28d9: фонтан земли."""
    t = tanks[victim - 1]
    waves = rng.word(30) + 30
    for r in range(1, waves + 1):
        s = 10 * r
        n = rng.word(400)
        for _ in range(n):
            h = rng.word(s)
            dx = math.trunc((float(rng.word(h + 10)) - h / 2.0) - 5.0)
            y = t.y - h
            x = t.x + dx
            while y > 189 or x < 11 or y < 31 or x > 309:
                if x > 309:
                    x = 618 - x
                if y > 189:
                    y = 378 - y
                if y < 31:
                    y = 62 - y
                if x < 11:
                    x = 22 - x
            o = (y * 320 + x) & 0xFFFF
            if o < len(v):
                v[o] = 2
            if sound:
                rng.word(1000)
    _redraw_all(v, tanks)
    erase_tank_barrel(v, bg, t)


def death6(v, bg, tanks, victim, rng, sound):
    """285c:2c29: копия записи жертвы в слот 0, Random(10) -> 1..4 взрыва оружием 1..j в точке танка."""
    t = tanks[victim - 1]
    n = rng.word(10)
    count = 1 if n <= 1 else 2 if n <= 4 else 3 if n <= 7 else 4
    players = [Player(p.idx, p.x, p.y, p.men, getattr(p, 'shield', 0), getattr(p, 'score', 0), p.alive) for p in tanks]
    for j in range(1, count + 1):
        explode(v, bg, players, float(t.x), float(t.y), 2, 0, j, rng, sound)
        for p, q in zip(tanks, players):
            p.men, p.shield, p.score = q.men, q.shield, q.score
        _redraw_all(v, tanks)
    t.men = -1


# ---------- вариант 0: 285c:0020 ----------
VP = (11, 31, 309, 189)
G0 = 0.006999999999997897          # 285c:0339 Real48 79 37 89 41 60 65
VX0, VY0 = 0.5, 0.10000000000002274


def _call0(rng):
    """285c:0000: вспышка цвета танка из случайного адреса памяти — Random(65535)."""
    rng.word(0xFFFF)


def _gp_vp(v, x, y):
    """Graph GetPixel во вьюпорте поля: (x+11, y+31)."""
    X, Y = x + VP[0], y + VP[1]
    return v[Y * 320 + X] if 0 <= X < 320 and 0 <= Y < 200 else 0


def _pp_vp(v, x, y, c):
    X, Y = x + VP[0], y + VP[1]
    if VP[0] <= X <= VP[2] and VP[1] <= Y <= VP[3]:
        v[Y * 320 + X] = c


def _replace_color(v, bg, lo, hi):
    """1062:0379 / 03a9: пиксели цвета lo..hi (смещения 1..64000) := фон."""
    for o in range(64000, 0, -1):
        if o < len(v) and lo <= v[o] <= hi:
            v[o] = bg[o]


def death0(v, bg, tanks, victim, rng, sound, wind=0, explosions_kill=False):
    from ballistics import q
    from explosion import ring, ring_restore
    t = tanks[victim - 1]
    color = victim + 19
    for _ in range(3):                      # три мигания палитрой по 5 шагов
        if sound:
            rng.word(500)
        _call0(rng)
    for _ in range(51):                     # 01ac..01d7
        if sound:
            rng.word(500)
        _call0(rng)
    tx, ty = t.x - 11, t.y - 31             # 0203..0231: координаты во вьюпорте (в записи)
    for _frag in range(11):
        if sound:
            rng.word(500)
        X, Y = q(float(tx)), q(float(ty))
        vx = q(VX0 - rng.real())
        vy = q(VY0 - rng.real())
        while True:
            done = False
            X = q(X + vx)
            Y = q(Y + vy)
            vy = q(vy + G0)
            vx = q(q(float(wind) / 5000.0) + vx)
            px, py = math.trunc(X), math.trunc(Y)
            c = _gp_vp(v, px, py)
            if c in (13, 2):
                done = True
            if explosions_kill and 20 <= c <= 29:
                vic = tanks[c - 20] if c - 20 < len(tanks) else None
                if vic is not None:
                    if getattr(vic, 'shield', 0) > 0:
                        done = True
                    else:
                        vic.men = vic.men - (rng.word(10) + 5)
            if py < 0 or py > 200 or px < 0 or px > 320:
                done = True
            _pp_vp(v, px, py, color)
            if done:
                break
        base = 10 * (rng.word(3) + 3)
        n = rng.word(10)
        k = 1 if n <= 2 else 2 if n <= 5 else 3 if n <= 7 else 4 if n == 8 else 5
        for r in range(0, 4 * k + 1):
            if sound:
                rng.word(2500)
            col = (base + 100 + r // k) & 0xFF
            ring(v, px, py, r, col)
            ring(v, px + 1, py, r, col)
        for r in range(4 * k, -1, -1):
            if sound:
                rng.word(2500)
            ring_restore(v, bg, px, py, r)
            ring_restore(v, bg, px + 1, py, r)
    r6 = 0
    for ae in range(5):                     # 06d4..083f: кольца вокруг танка, радиусы 1..30
        for b0 in range(3, 6):
            r6 += 1
            col = (10 * b0 + 100 + ae) & 0xFF
            ring(v, tx, ty, r6, col)
            ring(v, tx + 1, ty, r6, col)
            for _ in range(5):
                if sound:
                    rng.word((1300 - 40 * r6) & 0xFFFF)
                _call0(rng)
            ring(v, tx, ty, r6 + 1, col)
            ring(v, tx + 1, ty, r6 + 1, col)
            for _ in range(5):
                if sound:
                    rng.word((1300 - 40 * r6) & 0xFFFF)
                _call0(rng)
            r6 += 1
    for ae in range(4, -1, -1):             # 0842..095e: гаснущая палитра, 15 шагов
        for _ in range(4 - ae, -1, -1):
            if sound:
                rng.word(200)
            rng.word(63); rng.word(63); rng.word(63)
    for r in range(30, -1, -1):             # 0963..09d9: воронка r=30
        ring_restore(v, bg, tx, ty, r)
        ring_restore(v, bg, tx + 1, ty, r)
    _redraw_all(v, tanks)
    _replace_color(v, bg, color, color)     # 1062:03a9
    _replace_color(v, bg, 0x82, 0x9F)       # 1062:0379


# ---------- вариант 2: 285c:1da5 — 11 обломков летят одновременно ----------
def death2(v, bg, tanks, victim, rng, sound, wind=0, explosions_kill=False):
    from ballistics import q
    from explosion import ring, ring_restore
    t = tanks[victim - 1]
    color = victim + 19
    for _ in range(3):
        if sound:
            rng.word(500)
        _call0(rng)
    for _ in range(51):
        if sound:
            rng.word(500)
        _call0(rng)
    tx, ty = t.x - 11, t.y - 31
    X, Y, VXs, VYs, dead = [], [], [], [], []
    for _ in range(11):
        if sound:
            rng.word(500)
        X.append(q(float(tx))); Y.append(q(float(ty)))
        VXs.append(q(VX0 - rng.real()))
        VYs.append(q(VY0 - rng.real()))
        dead.append(False)
    end = [(0, 0)] * 11
    while True:
        any_alive = False
        for i in range(11):
            if dead[i]:
                continue
            X[i] = q(X[i] + VXs[i])
            Y[i] = q(Y[i] + VYs[i])
            VYs[i] = q(VYs[i] + G0)
            VXs[i] = q(q(float(wind) / 5000.0) + VXs[i])
            px, py = math.trunc(X[i]), math.trunc(Y[i])
            any_alive = True
            c = _gp_vp(v, px, py)
            if c in (13, 2):
                dead[i] = True
            if explosions_kill and 20 <= c <= 29:
                vic = tanks[c - 20] if c - 20 < len(tanks) else None
                if vic is not None:
                    if getattr(vic, 'shield', 0) >= 1:
                        dead[i] = True
                    else:
                        vic.men = vic.men - (rng.word(10) + 10)
            if py < 0 or py > 0x9E or px < 0 or px > 0x12A:
                dead[i] = True
            _pp_vp(v, px, py, color)
            if dead[i]:
                end[i] = (px, py)
        if not any_alive:
            break
    for i in range(11):
        px, py = end[i]
        base = 10 * (rng.word(3) + 3)
        n = rng.word(10)
        k = 1 if n <= 2 else 2 if n <= 5 else 3 if n <= 7 else 4 if n == 8 else 5
        for r in range(0, 4 * k + 1):
            if sound:
                rng.word(2500)
            _call0(rng)
            col = (base + 100 + r // k) & 0xFF
            ring(v, px, py, r, col)
            ring(v, px + 1, py, r, col)
        for r in range(4 * k, -1, -1):
            if sound:
                rng.word(2500)
            _call0(rng)
            ring_restore(v, bg, px, py, r)
            ring_restore(v, bg, px + 1, py, r)
    r6 = 0
    for ae in range(5):
        for b0 in range(3, 6):
            r6 += 1
            col = (10 * b0 + 100 + ae) & 0xFF
            ring(v, tx, ty, r6, col)
            for _ in range(5):
                if sound:
                    rng.word((1300 - 40 * r6) & 0xFFFF)
                _call0(rng)
            ring(v, tx, ty, r6 + 1, col)
            for _ in range(5):
                if sound:
                    rng.word((1300 - 40 * r6) & 0xFFFF)
                _call0(rng)
            r6 += 1
    for ae in range(4, -1, -1):
        for _ in range(4 - ae, -1, -1):
            if sound:
                rng.word(200)
            rng.word(63); rng.word(63); rng.word(63)
    for r in range(30, -1, -1):
        ring_restore(v, bg, tx, ty, r)
        ring_restore(v, bg, tx + 1, ty, r)
    _redraw_all(v, tanks)
    _replace_color(v, bg, color, color)
    _replace_color(v, bg, 0x82, 0x9A)


# ---------- варианты 1 и 3: 285c:0f61(mode 0 / 1) — «искры» и «брызги» ----------
def _vget(v, x, y):
    o = (y * 320 + x) & 0xFFFF
    return v[o] if o < len(v) else 0


def _vput(v, x, y, c):
    o = (y * 320 + x) & 0xFFFF
    if o < len(v):
        v[o] = c


def _particle_hit(v, tanks, x, y, rng, explosions_kill):
    """285c:0ac4/0e23: частица в танке без щита снимает Random(3) здоровья."""
    if not explosions_kill:
        return
    c = _vget(v, x, y)
    if 20 <= c <= 29 and c - 20 < len(tanks):
        vic = tanks[c - 20]
        if getattr(vic, 'shield', 0) <= 0:
            vic.men -= rng.word(3)


def _shape(kind, x0, y0, a, b):
    return {1: (x0 + b, y0 - a), 2: (x0 + b, y0 + a), 3: (x0 + a, y0 - b), 4: (x0 - a, y0 - b),
            5: (x0 + b + a, y0 - a), 6: (x0 + b - a, y0 - a), 7: (x0 + b + a, y0 + a),
            8: (x0 + b - a, y0 + a)}[kind]


def death_particles(v, bg, tanks, victim, rng, sound, mode, explosions_kill=False):
    t = tanks[victim - 1]
    bursts = rng.word(5) + 5
    for _ in range(bursts):
        m = rng.word(390) + 2
        kind = rng.word(8) + 1
        frames = []
        for f in range(1, 6):
            s = 10 * f
            pts = []
            for _i in range(m):
                a = rng.word(s)
                b = math.trunc((float(rng.word(a + 10)) - a / 2.0) - 5.0)
                pts.append(list(_shape(kind, t.x, t.y, a, b)))
            frames.append(pts)
        for pts in frames:                    # 1bb7..1d23: отражение внутрь поля (один проход)
            for p in pts:
                if p[0] > 309:
                    p[0] = 618 - p[0]
                if p[1] > 189:
                    p[1] = 378 - p[1]
                if p[1] < 31:
                    p[1] = 62 - p[1]
                if p[0] < 11:
                    p[0] = 22 - p[0]
        if mode == 0:                         # 285c:0a82
            for i in range(m):
                if sound:
                    rng.word(500)
                x, y = frames[0][i]
                _particle_hit(v, tanks, x, y, rng, explosions_kill)
                _vput(v, x, y, rng.word(14) + 1)
            for f in range(2, 6):
                for i in range(m):
                    if sound:
                        rng.word((500 * f) & 0xFFFF)
                    x, y = frames[f - 1][i]
                    _particle_hit(v, tanks, x, y, rng, explosions_kill)
                    _vput(v, x, y, rng.word(14) + 1)
                    px, py = frames[f - 2][i]
                    _vput(v, px, py, bg[(py * 320 + px) & 0xFFFF])
            for i in range(m):
                x, y = frames[4][i]
                _vput(v, x, y, bg[(y * 320 + x) & 0xFFFF])
        else:                                 # 285c:0dd4
            for f in range(1, 6):
                for i in range(m):
                    if sound:
                        rng.word((500 * f) & 0xFFFF)
                    x, y = frames[f - 1][i]
                    _particle_hit(v, tanks, x, y, rng, explosions_kill)
                    col = rng.word(14) + 0xC9
                    if col == 0xCA:
                        col = 2
                    _vput(v, x, y, col)
    _redraw_all(v, tanks)
    erase_tank_barrel(v, bg, t)
    _replace_color(v, bg, 0xC9, 0xDC)


def death1(v, bg, tanks, victim, rng, sound, wind=0, explosions_kill=False):
    death_particles(v, bg, tanks, victim, rng, sound, 0, explosions_kill)


def death3(v, bg, tanks, victim, rng, sound, wind=0, explosions_kill=False):
    death_particles(v, bg, tanks, victim, rng, sound, 1, explosions_kill)
