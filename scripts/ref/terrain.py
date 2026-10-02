"""Модель генерации рельефа Tank Wars 2.5 (оверлей 2eef, участок 2eef:0a4f..0dbc).

Земля — цвет 2 в видеопамяти 320x200. Рисуются вертикальные столбцы от y = 190-h до y = 189
включительно (1691:08ef и Graph Line дают одни и те же пиксели). Состояние генератора:
  x = DS:3eb2 (столбец), h = DS:3eaa (высота над y=190), s = [bp-4] наклон -4..4, d = [bp-2] направление ±1.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import List

try:
    from tprandom import TPRandom
except ImportError:  # pragma: no cover
    from .tprandom import TPRandom

DIRT = 2
X_FIRST, X_END = 11, 0x136          # столбцы 11..309
GROUND_BASE = 190                    # верх столбца = 190 - h
GROUND_BOTTOM = 189
# Real48-константы сравнений (2eef:0d1c и 0d3a): 0.2 и 0.1 в точности как в Real48
P_STEER = 0.20000000000004547        # Real48 7e cd cc cc cc 4c (CX:SI:DI = cd7e cccc 4ccc)
P_FLIP = 0.10000000000002274         # Real48 7d cd cc cc cc 4c


@dataclass
class TerrainResult:
    columns: List[int] = field(default_factory=list)   # (x, top_y) в порядке рисования
    tops: dict = field(default_factory=dict)           # x -> top_y последнего рисования
    h_final: int = 0


def flat_margin(players: int) -> int:
    return 60 - 7 * (players - 2)


def generate(rng: TPRandom, players: int) -> TerrainResult:
    res = TerrainResult()
    d = 1 - 2 * rng.word(2)
    m = flat_margin(players)
    h = rng.word(150)
    s = 0
    x = X_FIRST

    def col(xx: int, hh: int):
        top = GROUND_BASE - hh
        res.columns.append((xx, top))
        res.tops[xx] = top

    def step_h(hh: int) -> int:
        return hh + 1 if s > 0 else hh - 1

    while x < X_END:
        if m + 11 > x or 0x135 - m < x:
            col(x, h)
            x += 1
            continue
        a = abs(s)
        if s == 0:
            col(x, h); x += 1; col(x, h); x += 1; col(x, h)
        if a == 1:
            col(x, h); x += 1; col(x, h); x += 1; h = step_h(h); col(x, h)
        if a == 2:
            col(x, h); x += 1; h = step_h(h); col(x, h); x += 1; h = step_h(h); col(x, h)
        if a == 3:
            col(x, h); x += 1; h = step_h(h); col(x, h); h = step_h(h)
        if a == 4:
            col(x, h); h = step_h(h); h = step_h(h)
        if rng.real() < P_STEER:
            s += d
        if rng.real() < P_FLIP or abs(s) > 4:
            d = -d
        s = max(-4, min(4, s))
        if h <= 20:
            d = 1
        if h >= 140:
            d = -1
        if h <= 3:
            s = 1
        if h >= 155:
            s = -1
        x += 1
    res.h_final = h
    return res


def render(res: TerrainResult, vram: bytearray | None = None) -> bytearray:
    """Нарисовать столбцы цветом 2 в буфер 320x200 (как 1691:08ef: от min(y) до max(y) включительно)."""
    v = vram if vram is not None else bytearray(64000)
    for x, top in res.columns:
        y0, y1 = sorted((top, GROUND_BOTTOM))
        for y in range(y0, y1 + 1):
            if 0 <= y < 200 and 0 <= x < 320:
                v[y * 320 + x] = DIRT
    return v
