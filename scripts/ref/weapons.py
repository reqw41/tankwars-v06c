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
    from tanks import BARREL, SPRITE, line, W
except ImportError:  # pragma: no cover
    from .explosion import ellipse_points, ring
    from .crumble import crumble
    from .tanks import BARREL, SPRITE, line, W

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


def laser(v: bytearray, bg: bytes, players: list, shooter: int, rng, sound: bool) -> None:
    """Энергия — слово +0x2B. power урезается до энергии. С вероятностью 0.2 men -= 1.

    При звуке на каждом шаге луча Random(12 * остаток), остаток = power*10, -10 за шаг.
    Попадание в землю (цвет 2, россыпь 15 точек) в этих эталонах не случалось.
    """
    rec = players[shooter - 1]
    power = _i16(rec, 0x0E)
    energy = _i16(rec, 0x2B)
    if power == 0:
        return
    if power > energy:
        power = energy
        _set16(rec, 0x0E, power)
    _set16(rec, 0x2B, energy - power)
    x, y = _i16(rec, 0), _i16(rec, 2)
    ang, facing = _i16(rec, 0x10), _i16(rec, 0x12)
    if rng.real() < _LASER_P:
        _set16(rec, 0x14, _i16(rec, 0x14) - 1)
    bdx, bdy = BARREL[ang]
    x2, y2 = x + bdx * facing, y - bdy
    buf = bytearray(W * 200)
    line(buf, x, y, x2, y2, 1)
    body = {(x + dx, y + dy) for dx, dy in SPRITE}
    for i in range(W * 200):
        if buf[i] and ((i % W, i // W) not in body):
            _pix(v, bg, i % W, i // W)
    # луч от дула. cos/sin — double; на эталонах Trunc совпал с Real48.
    a = math.radians(ang)
    cs, sn = math.cos(a), math.sin(a)
    px, py = x + facing * cs * 8.0, y - sn * 8.0
    counter = power * 10
    while counter > 0 and 10 < px < 310 and 30 < py < 190:
        counter -= 10
        if sound:
            rng.word((12 * counter) & 0xFFFF)
        ix, iy = math.trunc(px), math.trunc(py)
        _pix(v, bg, ix, iy)
        px += facing * cs
        py -= sn


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
