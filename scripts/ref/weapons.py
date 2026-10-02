"""Особое оружие Tank Wars 2.5. Каждая функция — эффект одного вызова, побитно с оригиналом.

Sonic Blaster (оружие 12, множество 318e:0080, код 318e:0f7e):
  палитра и звук (ГСЧ), затем дыра и полное осыпание 1062:027e.
  Эллипс 1691:0592(r=1) в координатах Trunc(x)+вьюпорт, Trunc(y)+вьюпорт;
  один пиксель 1691:0ae3 в абсолютных Trunc(x), Trunc(y); затем crumble.
"""
from __future__ import annotations

import math
import struct
from typing import Tuple

try:
    from explosion import ellipse_points, ring
    from crumble import crumble
    from tanks import BARREL, SPRITE, line, W, draw_tank
except ImportError:  # pragma: no cover
    from .explosion import ellipse_points, ring
    from .crumble import crumble
    from .tanks import BARREL, SPRITE, line, W, draw_tank

Viewport = Tuple[int, int, int, int]  # x1, y1, x2, y2


def _pix(v: bytearray, bg: bytes, x: int, y: int) -> None:
    if not (0 <= x < 320 and 0 <= y < 200):
        return
    o = y * 320 + x
    v[o] = bg[o]


def ellipse_restore(v: bytearray, bg: bytes, x: int, y: int, rx: int, ry: int,
                    vp: Viewport, clip: bool = True) -> None:
    """1691:0592: центр += начало вьюпорта. Если clip и рамка не внутри — точки за вьюпортом отбрасываются."""
    cx, cy = x + vp[0], y + vp[1]
    inside = (not clip) or (vp[0] <= cx - rx and cx + rx <= vp[2] and vp[1] <= cy - ry and cy + ry <= vp[3])
    for px, py in ellipse_points(cx, cy, rx, ry):
        if inside or (vp[0] <= px <= vp[2] and vp[1] <= py <= vp[3]):
            _pix(v, bg, px, py)


def sonic_random(rng, sound: bool) -> None:
    """Расход RandSeed: два прохода по 100 (318e:0f7e и 0fc5). Палитра VRAM не меняет."""
    for _ in range(100):
        rng.word(64)
        if sound:
            rng.word(1000)
    for _ in range(100):
        rng.word(64)
        rng.word(64)
        if sound:
            rng.word(1000)


def sonic(v: bytearray, bg: bytes, x: float, y: float, rng, sound: bool,
          vp: Viewport = (11, 31, 309, 189), clip: bool = True) -> None:
    """Оружие 12. Игроков не меняет. Осыпание безусловное (не через Crumble%)."""
    sonic_random(rng, sound)
    ix, iy = math.trunc(x), math.trunc(y)
    ellipse_restore(v, bg, ix, iy, 1, 1, vp, clip)
    _pix(v, bg, ix, iy)
    crumble(v, bg)


# --- CRI 6..10 (318e:08d6). Оружие 5 в том же множестве — это Laser, сюда не доходит. ---
CRI_RADIUS = {5: 4, 6: 4, 7: 8, 8: 8, 9: 20, 10: 20}
CRI_FLUENT = {6, 8, 10}          # множество 318e:0060, диагонали
_DIR = {1: (0, -1), 2: (1, -1), 3: (1, 0), 4: (1, 1), 5: (0, 1), 6: (-1, 1), 7: (-1, 0), 8: (-1, -1)}


def _at(v: bytes, x: int, y: int) -> int:
    if not (0 <= x < 320 and 0 <= y < 200):
        return 0
    return v[y * 320 + x]


def _i16(b: bytes, o: int) -> int:
    return struct.unpack_from('<h', b, o)[0]


def _i32(b: bytes, o: int) -> int:
    return struct.unpack_from('<i', b, o)[0]


def _set16(b: bytearray, o: int, val: int) -> None:
    struct.pack_into('<h', b, o, (val + 0x8000) % 0x10000 - 0x8000)


def _set32(b: bytearray, o: int, val: int) -> None:
    struct.pack_into('<i', b, o, (val + 0x80000000) % 0x100000000 - 0x80000000)


def _hit_shield(players: list, victim: int, shooter: int, dmg: int) -> None:
    """Щит +0x45, перелив в men +0x14 и очки стрелку +0x04 (как 318e:091c и обычный взрыв)."""
    rec = players[victim - 1]
    shield = _i32(rec, 0x45) - dmg
    if shield < 0:
        men = (_i16(rec, 0x14) + (shield & 0xFFFF)) & 0xFFFF
        _set16(rec, 0x14, men if men < 0x8000 else men - 0x10000)
        if victim != shooter and 1 <= shooter <= len(players):
            src = players[shooter - 1]
            _set32(src, 0x04, _i32(src, 0x04) - shield * 10)
        shield = 0
    _set32(rec, 0x45, shield)


def cri(v: bytearray, bg: bytes, players: list, x: float, y: float, hit: int,
        shooter: int, weapon: int, rng, sound: bool) -> None:
    """Цепная реакция. players — bytearray записей 0x61, индекс 0 = игрок 1.

    Прямое попадание (цвет 20..29, множество 318e:0040): урон Random(weapon*6)+1, без земли.
    Попадание в землю (цвет 2): R червей; D ({6,8,10}) ходят и по диагонали.
    Иной цвет — пусто.
    """
    if weapon not in CRI_RADIUS:
        return
    if 20 <= hit <= 29:
        _hit_shield(players, hit - 19, shooter, rng.word(weapon * 6) + 1)
        return
    if hit != 2:
        return
    radius = CRI_RADIUS[weapon]
    fluent = weapon in CRI_FLUENT
    cx, cy = math.trunc(x), math.trunc(y)
    while not any(_at(v, cx + dx, cy + dy) == 2 for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1))):
        cy += 1
    pts = [(0, 0)] * 22
    for i in range(1, radius + 1):
        pts[i] = (cx, cy)
    while True:
        for i in range(1, radius + 1):
            dirs = []
            px, py = pts[i]
            for d in range(1, 9):
                if d % 2 == 0 and not fluent:
                    continue
                dx, dy = _DIR[d]
                if _at(v, px + dx, py + dy) == 2:
                    dirs.append(d)
            if dirs:
                d = dirs[rng.word(len(dirs))]
                dx, dy = _DIR[d]
                nx, ny = px + dx, py + dy
                pts[i] = (nx, ny)
                if sound:
                    rng.word(500)
                _pix(v, bg, nx, ny)
            else:
                pts[i] = (0, 0)
        dead = 0
        for i in range(1, radius + 1):
            if pts[i][0] != 0:
                continue
            dead += 1
            j = 0
            while True:
                j += 1
                if (j != i and j <= 21 and pts[j][0] != 0) or j == 21:
                    break
            if j == 21:
                j = i
            pts[i] = pts[j]
        if dead == radius:
            return


# Шары грязи 13..16 (318e:10e4). Circle 1827:11ea, радиусы как у зажигательных.
# На r=7 пиксели Circle совпали с 1691-эллипсом (tests/fixtures/t03/circle_real.json).
DIRT_RADIUS = {13: 10, 14: 15, 15: 30, 16: 60}
_FIELD = (11, 31, 309, 189)


def explosive_dirt(v: bytearray, bg: bytes, x: float, y: float, rng, sound: bool,
                   percent: int, vp: Viewport = _FIELD) -> None:
    """Оружие 17 (318e:12a5). Грязь вверх, затем осыпание, если Random*100 < 2*Crumble%.

    Сравнение 318e:15b6 — jae: правый операнд Real(Crumble%*2), левый Random*100.
    Цвет попадания не читается. PutPixel отсекается вьюпортом включительно.
    """
    n = rng.word(100) + 300
    rows = rng.word(8) + 3
    tx, ty = math.trunc(x - vp[0]), math.trunc(y - vp[1])
    pts = []
    for row in range(1, rows + 1):
        for _col in range(n):
            span = rng.word(row * 10)
            jitter = math.trunc(rng.word(span + 1) - span / 2.0)
            pts.append((tx + jitter, ty - span + 2, row))
    x1, y1, x2, y2 = vp
    for px, py, row in pts:
        if x1 <= px + x1 <= x2 and y1 <= py + y1 <= y2:
            _pix_set(v, px + x1, py + y1, 2)
        if sound:
            rng.word(200)
    # 318e:15a1 Random; 15b6 jae — осыпать, когда Random*100 < percent*2
    if rng.real() * 100.0 < percent * 2:
        crumble(v, bg)


# Лазер, оружие 5, 2583:140f. Ствол — длина 8 (как 1062:059f). Луч идёт от дула шагом
# (facing*cos, -sin), пока 10<x<310 и 30<y<190. В конце все пиксели цвета 0xFE
# заменяются фоном (1062:0379): снаружи спрайта это стирает ствол и клетки луча.
_LASER_P = 0.20000000000004547   # Real48 7e cd cc cc cc 4c, 2583:1988


def _trig(a: int):
    """Cos/Sin(DegToRad(a)) ровно как RTL TP6 (data/trig.json, снято исполнением)."""
    global _TRIG
    if _TRIG is None:
        import json
        from pathlib import Path
        from real48 import real48_to_float
        raw = json.loads((Path(__file__).parent / 'data' / 'trig.json').read_text())
        _TRIG = {int(k): (real48_to_float(bytes.fromhex(c)), real48_to_float(bytes.fromhex(s)))
                 for k, (c, s) in raw.items()}
    return _TRIG[a % 360 if a not in _TRIG else a]


_TRIG = None
_K53, _R7, _R10, _R20 = 53.0, 7.0, 10.0, 20.0
_LX1, _LX2, _LY1, _LY2 = 11.0, 309.0, 31.0, 189.0      # стены луча 2583:21e9..2305
BEAM = 0xFE


def _voff(x: int, y: int) -> int:
    return (y * 320 + x) & 0xFFFF                       # 1691:0ac1/0b0a: y*256+y*64+x, 16 бит


def _vget(v, x, y) -> int:
    o = _voff(x, y)
    return v[o] if o < len(v) else 0


def _vput(v, x, y, c) -> None:
    o = _voff(x, y)
    if o < len(v):
        v[o] = c


def _in_field(x: int, y: int) -> bool:
    return 11 <= x <= 309 and 31 <= y <= 189


def _i32(b: bytes, o: int) -> int:
    return struct.unpack_from('<i', b, o)[0]


def laser(v: bytearray, bg: bytes, players: list, shooter: int, rng, sound: bool, rebound: bool = False) -> None:
    """Ход лазера 2583:140f..24c5 (оружие 5). players — записи игроков (bytearray 0x61), меняются на месте.

    Энергия +0x2B (слово) урезает power и уменьшается на power. Random < 0.2 -> men-1.
    Луч: старт (x + 7cos·facing, y − 7sin), шаг (cos e, −sin e), e = угол (facing>0) или 180−угол;
    счётчик 10·power, −10 за шаг. Земля (цвет 2): 15 «прожогов» Random(20) позади луча.
    Живой танк (20..29, men>0): ещё −10 счётчика; без щита — 15 искр Random(40) цветом жертвы и их стирание;
    щит −3 (перелив — со здоровья); луч откатывается на шаг. Стены: отражение (DS:8200) или конец.
    Пиксели луча — 0xFE; в конце все 0xFE по экрану (смещения 1..64000) заменяются фоном (1062:0379).
    """
    from ballistics import q
    rec = players[shooter - 1]
    power = _i16(rec, 0x0E)
    if power == 0:
        return
    energy = _i16(rec, 0x2B)
    if power > energy:
        power = energy
        _set16(rec, 0x0E, power)
    _set16(rec, 0x2B, energy - power)
    x0, y0 = _i16(rec, 0), _i16(rec, 2)
    ang, facing = _i16(rec, 0x10), _i16(rec, 0x12)
    bdx, bdy = BARREL[ang]
    line(v, x0, y0, x0 + bdx * facing, y0 - bdy, BEAM)                 # 157a: ствол цветом 0xFE
    draw_tank(v, x0, y0, shooter + 19)                                   # 159b
    counter = 10 * power
    eff = ang if facing > 0 else 180 - ang
    if rng.real() < _LASER_P:
        _set16(rec, 0x14, _i16(rec, 0x14) - 1)
    ca, sa = _trig(ang)
    X = q(float(x0) + q(q(ca * _R7) * float(facing)))
    Y = q(float(y0) - q(sa * _R7))
    dx, dy = _trig(eff)
    dy = -dy if dy != 0.0 else dy
    done = False
    while True:
        X = q(X + dx)
        Y = q(Y + dy)
        counter -= 10
        ix, iy = math.trunc(X), math.trunc(Y)
        c = _vget(v, ix, iy)
        if c == 2:
            for kk in range(1, 16):
                gx = math.trunc(q(X - q(float(rng.word(20)) * dx)))
                gy = math.trunc(q(Y - q(float(rng.word(20)) * dy)))
                if sound:
                    rng.word((500 * kk) & 0xFFFF)
                gc = _vget(v, gx, gy) if 0 <= gx < 320 and 0 <= gy < 200 else 0
                if _in_field(gx, gy) and not (20 <= gc <= 29) and gc != BEAM:
                    _vput(v, gx, gy, bg[_voff(gx, gy)])
        if 19 < c < 30 and _i16(players[c - 20], 0x14) > 0:
            counter -= 10
            vrec = players[c - 20]
            if _i32(vrec, 0x45) <= 0:
                pts = []
                for kk in range(1, 16):
                    while True:
                        sx = math.trunc(q(q(X - float(rng.word(40))) + _R20))
                        sy = math.trunc(q(q(Y - float(rng.word(40))) + _R20))
                        gc = _vget(v, sx, sy) if 0 <= sx < 320 and 0 <= sy < 200 else 0
                        if gc == c or gc < 20 or (gc != BEAM and gc > 29):
                            break
                    pts.append((sx, sy))
                    if sound:
                        rng.word((500 * kk) & 0xFFFF)
                    if _in_field(sx, sy):
                        _vput(v, sx, sy, c)
                for kk, (sx, sy) in enumerate(pts, 1):
                    if sound:
                        rng.word((500 * kk) & 0xFFFF)
                    if _in_field(sx, sy):
                        _vput(v, sx, sy, bg[_voff(sx, sy)])
            sh = _i32(vrec, 0x45) - 3
            if sh < 0:
                _set16(vrec, 0x14, _i16(vrec, 0x14) + sh)
                sh = 0
            struct.pack_into('<i', vrec, 0x45, sh)
            X = q(X - dx)
            Y = q(Y - dy)
        if sound:
            rng.word((12 * counter) & 0xFFFF)
        if counter <= 0:
            done = True
        conds = [(dx < 0 and X <= _LX1), (dx > 0 and X >= _LX2)]
        if rebound:
            if dx < 0 and X <= _LX1 and dx != 0.0:
                dx = -dx
            if dx > 0 and X >= _LX2 and dx != 0.0:
                dx = -dx
            if dy < 0 and Y <= _LY1 and dy != 0.0:
                dy = -dy
            if dy > 0 and Y >= _LY2 and dy != 0.0:
                dy = -dy
        else:
            if any(conds) or (dy < 0 and Y <= _LY1) or (dy > 0 and Y >= _LY2):
                done = True
        if not done:
            _vput(v, math.trunc(X), math.trunc(Y), BEAM)
        if counter <= 0:
            done = True
        if done:
            break
    for o in range(64000, 0, -1):
        if o < len(v) and v[o] == BEAM:
            v[o] = bg[o]


# Наведение в полёте, 2583:06cf, после интегрирования шага и до Trunc.
# 1 Herb's (множество 0180): если |dy|<=2, vy=0 и vx *= ±1.01.
# 2 Vick's (множество 01a0): если |dx|<=2, vx=0 и y += sign(dy)*0.5.
# 3 — оба, сначала Vick's.
_HERB = 1.0100000000002183
_HALF = 0.5


def guide_step(x, y, vx, vy, kind: int, target_x: int, target_y: int):
    """Один шаг коррекции. x,y,vx,vy уже Real48-значения после физики."""
    from ballistics import q
    dx = q(q(float(target_x)) - x)
    dy = q(q(float(target_y)) - y)
    if kind in (2, 3) and abs(dx) <= 2.0:
        vx = q(0.0)
        y = q(y + _HALF) if dy > 0 else q(y - _HALF)
    if kind in (1, 3) and abs(dy) <= 2.0:
        vy = q(0.0)
        prod = q(dx * vx)
        # 2583:0876 jae → +1.01 (dx*vx >= 0, уже летим к цели), иначе −1.01
        vx = q(vx * (_HERB if prod >= 0 else -_HERB))
    return x, y, vx, vy


def guided_positions(terrain_bytes: bytes, tank_x: int, tank_y: int, angle: int, power: int,
                     facing: int, men: int, kind: int, target_x: int, target_y: int,
                     wind: int = 0) -> list:
    """Пиксели Trunc(x), Trunc(y) на 2583:0b91 — тот же интегратор, что scripts/ref/ballistics.py."""
    from ballistics import (
        BARREL, DIAMOND, GRAVITY, POWER_DIV, STEP_DIV, WIND_DIV, Y_KILL_HI, Y_KILL_LO,
        _advance_substep, _hit_should_stop, _is_hit_color, deg_to_rad, q, trunc0,
    )
    import math
    from real48 import float_to_real48
    rad = deg_to_rad(angle)
    c = q(math.cos(rad))
    s = q(math.sin(rad))
    x = q(q(float(tank_x)) + q(q(c * BARREL) * float(facing)))
    y = q(q(float(tank_y)) - q(s * BARREL))
    vx = q(q(q(float(power) / POWER_DIV) * c) * float(facing))
    vy = q(q(float(power) / POWER_DIV) * s)
    if float_to_real48(vy)[0] != 0:
        vy = q(-vy)
    step = STEP_DIV
    fuse = 1000 - 2 * men
    sub = 1
    positions = []
    for _ in range(4000):
        sub = _advance_substep(sub, int(step))
        x = q(x + q(vx / step))
        y = q(y + q(vy / step))
        vy = q(vy + q(GRAVITY / step))
        vx = q(vx + q(q(float(wind) / WIND_DIV) / step))
        x, y, vx, vy = guide_step(x, y, vx, vy, kind, target_x, target_y)
        px, py = trunc0(x), trunc0(y)
        positions.append([px, py])
        in_band = (y < 189.0) and (x < 309.0) and (y > 33.0) and (x > 11.0)
        if in_band:
            for ddx, ddy in DIAMOND:
                cpix = terrain_bytes[(py + ddy) * 320 + (px + ddx)] if 0 <= px + ddx < 320 and 0 <= py + ddy < 200 else 0
                if _is_hit_color(cpix) and _hit_should_stop(power, fuse, cpix, sub, int(step)):
                    return positions
        if y < Y_KILL_LO or y > Y_KILL_HI:
            return positions
    return positions


def _pix_set(v: bytearray, x: int, y: int, color: int) -> None:
    if 0 <= x < 320 and 0 <= y < 200:
        v[y * 320 + x] = color


def dirt_ball(v: bytearray, x: float, y: float, weapon: int, vp: Viewport = _FIELD) -> None:
    """Диск земли цветом 2. ГСЧ не тратит, игроков не трогает. Координаты — во вьюпорте (минус 11, 31)."""
    radius = DIRT_RADIUS[weapon]
    lx, ly = x - vp[0], y - vp[1]
    cy = math.trunc(ly)
    centers = (math.trunc(lx + 1), math.trunc(lx - 1), math.trunc(lx))
    for i in range(radius + 1):
        for cx in centers:
            ring(v, cx, cy, i, 2, vp)
