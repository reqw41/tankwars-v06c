"""Особое оружие Tank Wars 2.5. Каждая функция — эффект одного вызова, побитно с оригиналом.

Sonic Blaster (оружие 12, множество 318e:0080, код 318e:0f7e):
  палитра и звук (ГСЧ), затем дыра и полное осыпание 1062:027e.
  Эллипс 1691:0592(r=1) в координатах Trunc(x)+вьюпорт, Trunc(y)+вьюпорт;
  один пиксель 1691:0ae3 в абсолютных Trunc(x), Trunc(y); затем crumble.
"""
from __future__ import annotations

import math
from typing import Tuple

try:
    from explosion import ellipse_points
    from crumble import crumble
except ImportError:  # pragma: no cover
    from .explosion import ellipse_points
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
