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
except ImportError:  # pragma: no cover
    from .explosion import ellipse_points, ring
    from .crumble import crumble

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


def dirt_ball(v: bytearray, x: float, y: float, weapon: int, vp: Viewport = _FIELD) -> None:
    """Диск земли цветом 2. ГСЧ не тратит, игроков не трогает. Координаты — во вьюпорте (минус 11, 31)."""
    radius = DIRT_RADIUS[weapon]
    lx, ly = x - vp[0], y - vp[1]
    cy = math.trunc(ly)
    centers = (math.trunc(lx + 1), math.trunc(lx - 1), math.trunc(lx))
    for i in range(radius + 1):
        for cx in centers:
            ring(v, cx, cy, i, 2, vp)
