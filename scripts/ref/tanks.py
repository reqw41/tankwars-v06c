"""Модель танков Tank Wars 2.5: спрайт, стирание, ствол, линия 1691:08ef, расстановка и посадка в начале раунда.

Источники (адреса Ghidra):
  1062:03d2  нарисовать танк (x, y, цвет) — 33 пикселя, SPRITE
  1062:046a  стереть танк: те же пиксели из буфера фона (используется только сегмент указателя)
  1062:059f  танк + ствол: линия (x,y)-(x+dx*facing, y-dy) цветом игрока, dx/dy из data/barrel.json
  1691:08ef  линия (x1,y1,x2,y2,c) — Брезенхем, без отсечения, см. line()
  2eef:0dbc..10c6  расстановка: x, угол, мощность, здоровье, посадка с y=32
Цвет танка = номер игрока + 19 (игроки 1..10 -> 20..29).
"""
from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional

try:
    from tprandom import TPRandom
except ImportError:  # pragma: no cover
    from .tprandom import TPRandom

W = 320
SUPPORT = {2, 13}          # множество 2eef:08e9 и 2b39:0000: земля и рамка
# (dx, dy) относительно (x, y), порядок как в 1062:03d2
SPRITE = [(0, 0), (1, 0), (2, 0), (3, 0), (4, 0), (-1, 0), (-2, 0), (-3, 0), (-4, 0),
          (0, -1), (-2, -1), (-3, -1), (-4, -1), (2, -1), (3, -1), (4, -1),
          (0, -2), (-1, -2), (-2, -2), (-3, -2), (1, -2), (2, -2), (3, -2),
          (0, -3), (-1, -3), (-2, -3), (-3, -3), (1, -3), (2, -3), (3, -3),
          (0, -4), (-1, -4), (1, -4)]
BARREL = {int(k): tuple(v) for k, v in json.loads(
    (Path(__file__).parent / 'data' / 'barrel.json').read_text()).items()}


@dataclass
class Tank:
    idx: int
    x: int = 0
    y: int = 0
    angle: int = 90
    power: int = 200
    facing: int = 1
    men: int = 100
    alive: bool = True

    @property
    def color(self) -> int:
        return self.idx + 19


def _off(x: int, y: int) -> int:
    # как 1062:03d2: y*320+x в 16 битах (отрицательные смещения заворачиваются в сегменте A000)
    return (y * W + x) & 0xFFFF


def poke(v: bytearray, off: int, c: int):
    if off < len(v):
        v[off] = c


def peek(v: bytes, off: int) -> int:
    return v[off] if off < len(v) else 0


def draw_tank(v: bytearray, x: int, y: int, c: int):
    base = _off(x, y)
    for dx, dy in SPRITE:
        poke(v, (base + dy * W + dx) & 0xFFFF, c)


def erase_tank(v: bytearray, bg: bytes, x: int, y: int):
    base = _off(x, y)
    for dx, dy in SPRITE:
        o = (base + dy * W + dx) & 0xFFFF
        poke(v, o, peek(bg, o))


def line(v: bytearray, x1: int, y1: int, x2: int, y2: int, c: int):
    """Побитная копия 1691:08ef."""
    cx = x2 - x1
    if cx == 0:                                    # вертикаль
        ya, yb = sorted((y1, y2))
        o = _off(x1, ya)
        for _ in range(yb - ya + 1):
            poke(v, o, c)
            o = (o + W) & 0xFFFF
        return
    if cx < 0:
        cx = -cx
        x1, x2, y1, y2 = x2, x1, y2, y1
    bx = y2 - y1
    if bx == 0:                                    # горизонталь
        o = _off(x1, y1)
        for _ in range(cx + 1):
            poke(v, o, c)
            o = (o + 1) & 0xFFFF
        return
    step = W
    if bx < 0:
        bx, step = -bx, -W
    ymajor = bx > cx
    if ymajor:
        bx, cx = cx, bx
    d2 = 2 * bx
    err = d2 - cx
    d22 = d2 - 2 * cx
    o = _off(x1, y1)
    for _ in range(cx + 1):
        poke(v, o, c)
        o = (o + 1) & 0xFFFF
        if not ymajor:
            if err < 0:
                err += d2
            else:
                err += d22
                o = (o + step) & 0xFFFF
        else:
            o = (o + step) & 0xFFFF
            if err < 0:
                err += d2
                o = (o - 1) & 0xFFFF
            else:
                err += d22


def draw_tank_with_barrel(v: bytearray, t: Tank):
    """1062:059f (без 07a9 — та меняет только палитру)."""
    if not t.alive:
        return
    draw_tank(v, t.x, t.y, t.color)
    dx, dy = BARREL[t.angle % 361 if t.angle >= 0 else t.angle % 360]
    line(v, t.x, t.y, t.x + dx * t.facing, t.y - dy, t.color)


def rect(v: bytearray, x1: int, y1: int, x2: int, y2: int, c: int):
    """1691:0031 — контур из четырёх линий 1691:08ef."""
    line(v, x2, y1, x2, y2, c)
    line(v, x1, y1, x1, y2, c)
    line(v, x1, y2, x2, y2, c)
    line(v, x1, y1, x2, y1, c)


FRAME_COLOR = 13


def draw_frame(v: bytearray, rebound_walls: bool):
    """2b39:0386: рамка поля цветом 13; без отражающих стен — линия земли y=189 от 11 до 309."""
    rect(v, 8, 28, 312, 192, FRAME_COLOR)
    rect(v, 10, 30, 310, 190, FRAME_COLOR)
    if not rebound_walls:
        line(v, 11, 189, 309, 189, 2)


def supported_any(v: bytes, x: int, y: int) -> bool:
    return any(peek(v, _off(x + dx, y + 1)) in SUPPORT for dx in range(-4, 5))


def supported_all(v: bytes, x: int, y: int) -> bool:
    return all(peek(v, _off(x + dx, y + 1)) in SUPPORT for dx in range(-4, 5))


def place_tanks(rng: TPRandom, players: int, v: bytearray, bg: bytes, rebound_walls: bool = False) -> List[Tank]:
    """2eef:0dbc..10c6. v — VRAM после рельефа (меняется на месте), bg — буфер фона."""
    tanks = [Tank(i) for i in range(1, players + 1)]
    first = rng.word(28) + 16
    last = 0x131 - rng.word(28)
    tanks[0].x = first
    tanks[-1].x = last
    q = int((last - first) / (players - 1))       # IDIV: усечение к нулю
    for i in range(2, players):
        tanks[i - 1].x = (i - 1) * q + first
    for t in tanks:
        t.angle = 75 if t.idx in (1, players) else 90
        t.power = 200
        t.facing = -1 if t.idx == players else 1
        t.men = 100
        t.alive = True
        t.y = 32
        if not supported_any(v, t.x, t.y):
            while True:
                erase_tank(v, bg, t.x, t.y)
                t.y += 1
                draw_tank(v, t.x, t.y, t.color)
                if supported_all(v, t.x, t.y):
                    break
            draw_tank_with_barrel(v, t)
            draw_frame(v, rebound_walls)   # 2eef:109c -> 1045:0025 = 2b39:0386
    return tanks
