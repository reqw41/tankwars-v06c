"""Осыпание земли и падение танков Tank Wars 2.5.

1062:027e  TW_Crumble(list, bg) — см. crumble()
2b39:03da  вход: рамка (2b39:0386), затем Random*100 <= Crumble% (DS:3EE6) -> TW_Crumble
2b39:0020  TW_TanksFall — см. tanks_fall()
"""
from __future__ import annotations

from typing import List, Optional

try:
    from tanks import (SUPPORT, Tank, draw_frame, draw_tank, erase_tank, draw_tank_with_barrel, line, BARREL, peek, _off)
except ImportError:  # pragma: no cover
    from .tanks import (SUPPORT, Tank, draw_frame, draw_tank, erase_tank, draw_tank_with_barrel, line, BARREL, peek, _off)

DIRT = 2
LIST_CAP = 9999
SCAN_FROM = 0xEEC0          # 191*320: сканирование снизу вверх до смещения 1
PERCENT = 100.0             # Real48 87 00 00 00 00 48


def _fallable(c: int) -> bool:
    return c == 0 or 30 <= c <= 99


def crumble(v: bytearray, bg: bytes) -> int:
    """1062:027e. Возвращает число проходов второй фазы. Список ограничен 9999 (переполнение не моделируется)."""
    lst: List[int] = []
    for bx in range(SCAN_FROM, 0, -1):
        if v[bx] == DIRT and _fallable(v[bx + 320]):
            v[bx] = bg[bx]
            v[bx + 320] = DIRT
            lst.append(bx + 320)
    passes = 0
    if not lst:
        return 0
    while True:
        moved = False
        passes += 1
        for i, e in enumerate(lst):
            if e == 0:
                continue
            if e + 320 < len(v) and _fallable(v[e + 320]):
                v[e] = bg[e]
                v[e + 320] = DIRT
                lst[i] = e + 320
                moved = True
            else:
                lst[i] = 0
        if not moved:
            return passes


def crumble_gate(v: bytearray, bg: bytes, rng, percent: int, rebound_walls: bool) -> bool:
    """2b39:03da: рамка, затем RandomReal*100 <= percent -> crumble. Вызывается, только если percent > 0."""
    draw_frame(v, rebound_walls)
    if rng.real() * PERCENT <= percent:
        crumble(v, bg)
        return True
    return False


def _sup(v: bytes, x: int, y: int) -> bool:
    return peek(v, _off(x, y + 1)) in SUPPORT


def tanks_fall(v: bytearray, bg: bytes, tanks: List[Tank], rng, rebound_walls: bool,
               dampener: Optional[dict] = None) -> None:
    """2b39:0020. dampener: idx -> LongInt Inertia Dampener (+0x49), уменьшается вместо здоровья."""
    dampener = dampener if dampener is not None else {}
    draw_frame(v, rebound_walls)
    for t in tanks:
        falling = t.alive
        for dx in range(-3, 4):
            if _sup(v, t.x + dx, t.y):
                falling = False
        if _sup(v, t.x - 4, t.y) and _sup(v, t.x + 4, t.y):
            falling = False
        if not falling:
            draw_tank_with_barrel(v, t)       # 2b39:0112 -> 036f: перерисовка всех живых танков (059f)
            continue
        bdx, bdy = BARREL[t.angle % 361 if t.angle >= 0 else t.angle % 360]
        line(v, t.x, t.y, t.x + bdx * t.facing, t.y - bdy, 0, bg=bg)      # 1691:09cb — стереть ствол
        while True:
            ox, oy = t.x, t.y
            draw_tank(v, ox, oy, t.color)
            landed = True
            t.y += 1
            if _sup(v, t.x + 4, t.y):
                t.x -= 1
            if _sup(v, t.x - 4, t.y):
                t.x += 1
            for dx in range(-4, 5):
                if not _sup(v, t.x + dx, t.y):
                    landed = False
            if dampener.get(t.idx, 0) > 0:
                dampener[t.idx] -= 1
            else:
                t.men -= rng.word(3) + 1
            erase_tank(v, bg, ox, oy)
            if landed:
                break
        draw_tank_with_barrel(v, t)
