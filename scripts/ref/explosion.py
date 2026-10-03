"""Модель обычного взрыва Tank Wars 2.5 (318e:00e0, ветка оружия из множества 318e:0000 = {1,2,3,4,11}).

Порядок (адреса Ghidra):
  0102..0147  радиус R по оружию: 1 Incinerator 10, 2 Mark II 15, 3 20 Kiloton 30, 4 5 Megaton 60, 11 Hand Grenade 2
  01c2        SetViewPort(11,31,309,189,clip) и копия в 1691 (E3AC..E3B4)
  01cc..0229  cx = Trunc(x-11), cy = Trunc(y-31) — координаты во вьюпорте
  0241..02c3  огонь: i=0..R, кольца 1691:025c радиуса i цветом 130+i вокруг (cx+1,cy), (cx-1,cy), (cx,cy)
  02c8..047b  три прохода по палитре (VRAM не меняется); при звуке тратят Random
  0480..04e7  воронка: i=R..0, кольца 1691:0592 восстанавливают пиксели из буфера фона, те же три центра
  04e9..05f2  прямое попадание (цвет 20..29): щит жертвы -= 200, перелив — со здоровья (+очки стрелявшему)
  0664..08ac  урон по расстоянию каждому живому танку (Hypot), сначала со щита
ГСЧ тратится только на звук (DS:81FF): Random(500) / Random(250) на каждом шаге анимации.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field
from typing import Dict, List, Optional

RADIUS = {1: 10, 2: 15, 3: 30, 4: 60, 11: 2}
STANDARD_WEAPONS = set(RADIUS)            # множество 318e:0000
FIRE_BASE_COLOR = 0x82
VIEWPORT = (11, 31, 309, 189)             # 318e:01af..01c2
K15, K18, K07 = 1.5, 1.7999999999992724, 0.6999999999998181   # Real48-константы 318e:0702/0728/07c0
TANK_COLORS = range(20, 30)
DIRECT_HIT = 200


@dataclass
class Player:
    idx: int
    x: int
    y: int
    men: int
    shield: int = 0      # LongInt +0x45
    score: int = 0       # LongInt +0x04
    alive: bool = True


def _mul32(a: int, b: int) -> int:
    """1691:0025: (DX:AX) * CX по модулю 2^32, CX — 16 бит без знака."""
    return (a * (b & 0xFFFF)) & 0xFFFFFFFF


def _s32(v: int) -> int:
    v &= 0xFFFFFFFF
    return v - (1 << 32) if v & 0x80000000 else v


def ellipse_points(x: int, y: int, rx: int, ry: int):
    """Последовательность точек 1691:025c/0592 (абсолютные координаты), побитная копия алгоритма средней точки."""
    a2 = rx * rx
    two_a2 = 2 * a2
    b2 = ry * ry
    two_b2 = 2 * b2
    # четыре точки: BR, TR, BL, TL
    br = [x, y + ry]
    tr = [x, y - ry]
    bl = [x, y + ry]
    tl = [x, y - ry]
    px = 0
    py = _s32(_mul32(two_a2, ry))
    p = _s32((a2 >> 2) + b2 - _mul32(a2, ry))
    yc = ry
    out = []

    def plot(cl: int, ch: int):
        br[0] += cl; br[1] -= ch
        tr[0] += cl; tr[1] += ch
        bl[0] -= cl; bl[1] -= ch
        tl[0] -= cl; tl[1] += ch
        out.extend((tuple(br), tuple(tr), tuple(bl), tuple(tl)))

    cl, ch = 0, 0
    while px - py < 0:                      # регион 1
        plot(cl, ch)
        cl, ch = 1, 0
        if p >= 0:
            ch = 1
            yc -= 1
            py -= two_a2
            p -= py
        px += two_b2
        p += px + b2
    t = a2 - b2
    t = t + (t >> 1)
    p += (t - px - py) >> 1                 # переход в регион 2 (03ce..03fb)
    while True:                             # регион 2
        plot(cl, ch)
        cl, ch = 0, 1
        if p < 0:
            cl = 1
            px += two_b2
            p += px
        py -= two_a2
        p -= py - a2
        yc -= 1
        if yc < 0:
            break
    return out


def _in_vp(pt, vp) -> bool:
    return vp[0] <= pt[0] <= vp[2] and vp[1] <= pt[1] <= vp[3]


def ring(v: bytearray, cx: int, cy: int, r: int, color: int, vp=VIEWPORT, clip=True):
    """1691:025c с центром во вьюпорте."""
    for pt in ellipse_points(cx + vp[0], cy + vp[1], r, r):
        if not clip or _in_vp(pt, vp):
            o = (pt[1] * 320 + pt[0]) & 0xFFFF
            if o < len(v):
                v[o] = color


def ring_restore(v: bytearray, bg: bytes, cx: int, cy: int, r: int, vp=VIEWPORT, clip=True):
    """1691:0592: те же точки, пиксель из буфера фона (используется только сегмент указателя)."""
    for pt in ellipse_points(cx + vp[0], cy + vp[1], r, r):
        if not clip or _in_vp(pt, vp):
            o = (pt[1] * 320 + pt[0]) & 0xFFFF
            if o < len(v):
                v[o] = bg[o]


def sound_random_calls(r: int) -> List[int]:
    """Аргументы Random(n), которые тратит анимация при включённом звуке, по порядку."""
    calls = [500] * (r + 1)                                  # 0244..026c
    calls += [500] * ((r + 1) * (r + 2) // 2)                # 02f6..031e
    calls += [500] * ((r + 1) * (r + 2) // 2)                # 0386..03ab
    calls += [250] * ((r + 1) * (r + 2) // 2)                # 0418..043d
    return calls


@dataclass
class ExplosionResult:
    radius: int
    cx: int
    cy: int
    damage: Dict[int, int] = field(default_factory=dict)


def explode(v: bytearray, bg: bytes, players: List[Player], x: float, y: float, hit_color: int,
            shooter: int, weapon: int, rng=None, sound: bool = False) -> Optional[ExplosionResult]:
    if weapon not in STANDARD_WEAPONS:
        return None
    r = RADIUS[weapon]
    cx = math.trunc(x - 11.0)
    cy = math.trunc(y - 31.0)
    for i in range(r + 1):
        for dx in (1, -1, 0):
            ring(v, cx + dx, cy, i, FIRE_BASE_COLOR + i)
    if sound and rng is not None:
        for n in sound_random_calls(r):
            rng.word(n)
    for i in range(r, -1, -1):
        for dx in (1, -1, 0):
            ring_restore(v, bg, cx + dx, cy, i)
    by_idx = {p.idx: p for p in players}
    res = ExplosionResult(r, cx, cy)

    def apply(victim: Player, dmg: int):
        victim.shield -= dmg
        if victim.shield < 0:
            if victim.idx != shooter and shooter in by_idx:   # shooter 0 — «призрак» гибели (285c:2c29)
                by_idx[shooter].score -= victim.shield * 10
            victim.men += victim.shield
            victim.shield = 0

    if hit_color in TANK_COLORS:
        apply(by_idx[hit_color - 19], DIRECT_HIT)
        res.damage[hit_color - 19] = DIRECT_HIT
    for p in players:
        if not p.alive:
            continue
        d = math.sqrt((x - p.x) ** 2 + (y - p.y) ** 2)
        dmg = 0
        if not (r * K15 < d):
            dmg += math.trunc(r * K18 - d)
        if r > d:
            dmg += 10 + 2 * math.trunc(r * K18 - d)
        if r * K07 > d:
            dmg += 150
        apply(p, dmg)
        res.damage[p.idx] = res.damage.get(p.idx, 0) + dmg
    return res
