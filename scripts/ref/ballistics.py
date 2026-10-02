"""Tank Wars 2.5 projectile flight model (Real48-accurate + fixed-point).

Matches FUN_2583_01c0 physics: muzzle, integration, gravity, wind, walls, hits.
Pure Python — no unicorn dependency.
"""
from __future__ import annotations

import math
import struct
from dataclasses import dataclass, field
from enum import Enum
from typing import List, Optional, Sequence, Tuple

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
from real48 import float_to_real48, real48_to_float  # noqa: E402

# --- TP Real48 constants (from 2583:01c0 immediates) ---
_PI = real48_to_float(struct.pack("<HHH", 0x2182, 0xDAA2, 0x490F))
_180 = real48_to_float(struct.pack("<HHH", 0x88, 0, 0x3400))
BARREL = 10.0
POWER_DIV = 50.0
STEP_DIV = 10.0  # DS:3eb0 forced to 10 at shot start
GRAVITY = 0.1
WIND_DIV = 5000.0
BOUNCE_SCALE = 1.2  # weapons 12..16 vs tank colors

# Playfield / wall thresholds
WALL_LEFT = 10.0
WALL_RIGHT = 310.0
WALL_TOP = 30.0
WALL_BOTTOM = 190.0
Y_KILL_LO = -5000.0
Y_KILL_HI = 193.0
SNAP_Y = 200.0

# Hit colors: dirt=2; tank palette slots 20..29
DIRT_COLOR = 2
TANK_COLOR_LO = 20
TANK_COLOR_HI = 29

DIAMOND = ((-1, 0), (0, -1), (0, 0), (0, 1), (1, 0))


class StopReason(str, Enum):
    TERRAIN = "terrain"
    TANK = "tank"
    Y_BOUNDS = "y_bounds"
    MAX_STEPS = "max_steps"


@dataclass
class FlightInput:
    angle: int  # degrees; with facing, 0=horizon toward facing
    power: int
    facing: int  # +1 right / -1 left (DS player+0x3f0e)
    tank_x: int
    tank_y: int
    wind: int = 0  # signed DS:3ede
    rebound: bool = False  # DS:8200
    weapon: int = 1  # DS player+0x3f13
    guided: int = 0  # DS player+0x3f15 (>0 enables seek/special)
    men: int = 5  # DS player+0x3f10; hit thresh = 1000-2*men (see spec §5)
    max_steps: int = 20000


@dataclass
class FlightResult:
    positions: List[Tuple[int, int]]  # Trunc(x), Trunc(y) each integration step
    xs: List[float] = field(default_factory=list)
    ys: List[float] = field(default_factory=list)
    stop: StopReason = StopReason.MAX_STEPS
    hit_color: int = 0
    steps: int = 0
    # ranges observed (for fixed-point sizing)
    min_x: float = 0.0
    max_x: float = 0.0
    min_y: float = 0.0
    max_y: float = 0.0
    min_vx: float = 0.0
    max_vx: float = 0.0
    min_vy: float = 0.0
    max_vy: float = 0.0


def q(x: float) -> float:
    """Quantize through Turbo Pascal Real48."""
    return real48_to_float(float_to_real48(float(x)))


def deg_to_rad(deg: float) -> float:
    """GRAPHW_DegToRad: (deg / 180) * π  (Real48 constants)."""
    return q(q(q(deg) / _180) * _PI)


def trunc0(x: float) -> int:
    """SYSTEM_Trunc — toward zero."""
    return int(x) if x >= 0 else -int(-x)


# ---- Fixed-point (16.16) helpers ----
FP_SHIFT = 16
FP_ONE = 1 << FP_SHIFT


def to_fp(x: float) -> int:
    return int(round(x * FP_ONE))


def from_fp(x: int) -> float:
    return x / FP_ONE


def fp_mul(a: int, b: int) -> int:
    return (a * b) >> FP_SHIFT


def fp_div(a: int, b: int) -> int:
    if b == 0:
        return 0
    return (a << FP_SHIFT) // b


class Terrain:
    """320×200 GetPixel oracle. Default: empty sky (0)."""

    def __init__(self, pixels: Optional[bytearray] = None):
        self.pixels = pixels if pixels is not None else bytearray(64000)

    @classmethod
    def flat_ground(cls, ground_y: int = 180, color: int = DIRT_COLOR) -> "Terrain":
        t = cls()
        for y in range(ground_y, 200):
            for x in range(320):
                t.pixels[y * 320 + x] = color
        return t

    @classmethod
    def with_tank(
        cls, ground_y: int, tank_x: int, tank_y: int, color: int = 21
    ) -> "Terrain":
        t = cls.flat_ground(ground_y)
        for dy in range(-3, 4):
            for dx in range(-5, 6):
                x, y = tank_x + dx, tank_y + dy
                if 0 <= x < 320 and 0 <= y < 200:
                    t.pixels[y * 320 + x] = color
        return t

    def get(self, x: int, y: int) -> int:
        if x < 0 or x >= 320 or y < 0 or y >= 200:
            return 0
        return self.pixels[y * 320 + x]


def _is_hit_color(c: int) -> bool:
    return c == DIRT_COLOR or (TANK_COLOR_LO <= c <= TANK_COLOR_HI)


def simulate(
    inp: FlightInput,
    terrain: Optional[Terrain] = None,
    *,
    fixed_point: bool = False,
) -> FlightResult:
    """Integrate one shot. fixed_point=True uses 16.16 instead of Real48."""
    if fixed_point:
        return _simulate_fp(inp, terrain or Terrain())
    return _simulate_real48(inp, terrain or Terrain())


def _simulate_real48(inp: FlightInput, terrain: Terrain) -> FlightResult:
    rad = deg_to_rad(inp.angle)
    c = q(math.cos(rad))
    s = q(math.sin(rad))

    x = q(q(float(inp.tank_x)) + q(q(c * BARREL) * float(inp.facing)))
    y = q(q(float(inp.tank_y)) - q(s * BARREL))
    vx = q(q(q(float(inp.power) / POWER_DIV) * c) * float(inp.facing))
    vy = q(q(float(inp.power) / POWER_DIV) * s)
    # SYSTEM_Sin non-zero → xor DH (negate) for screen-Y (down positive)
    if float_to_real48(vy)[0] != 0:
        vy = q(-vy)

    step = STEP_DIV
    fuse = 1000 - 2 * inp.men
    positions: List[Tuple[int, int]] = []
    xs: List[float] = []
    ys: List[float] = []
    hit_color = 0
    stop = StopReason.MAX_STEPS
    mn_x = mx_x = x
    mn_y = mx_y = y
    mn_vx = mx_vx = vx
    mn_vy = mx_vy = vy

    for i in range(inp.max_steps):
        # x += vx/step; y += vy/step; vy += 0.1/step; vx += wind/5000/step
        x = q(x + q(vx / step))
        y = q(y + q(vy / step))
        vy = q(vy + q(GRAVITY / step))
        vx = q(vx + q(q(float(inp.wind) / WIND_DIV) / step))

        px, py = trunc0(x), trunc0(y)
        positions.append((px, py))
        xs.append(x)
        ys.append(y)
        mn_x, mx_x = min(mn_x, x), max(mx_x, x)
        mn_y, mx_y = min(mn_y, y), max(mx_y, y)
        mn_vx, mx_vx = min(mn_vx, vx), max(mx_vx, vx)
        mn_vy, mx_vy = min(mn_vy, vy), max(mx_vy, vy)

        # Walls / off-screen wind snap (only when NOT in collision band)
        in_band = (y < 189.0) and (x < 309.0) and (y > 33.0) and (x > 11.0)
        if in_band:
            hit_color = 0
            for dx, dy in DIAMOND:
                cpix = terrain.get(px + dx, py + dy)
                if _is_hit_color(cpix):
                    hit_color = cpix
                    # done if power < thresh OR tank (palette wrap handled in original via 3eac==3eb0)
                    is_tank = TANK_COLOR_LO <= cpix <= TANK_COLOR_HI
                    if inp.power < fuse or is_tank:
                        # power==thresh and dirt → cancel stop (2583:0d6c)
                        if inp.power == fuse and cpix == DIRT_COLOR:
                            pass
                        else:
                            # weapons 12..16 bounce on tank colors
                            if is_tank and 12 <= inp.weapon <= 16:
                                vy = q(-vy * BOUNCE_SCALE)
                            else:
                                stop = StopReason.TANK if is_tank else StopReason.TERRAIN
                                break
            if stop != StopReason.MAX_STEPS:
                break
        else:
            if inp.rebound:
                if vx < 0 and x < WALL_LEFT:
                    vx = q(-vx)
                if vx > 0 and x > WALL_RIGHT:
                    vx = q(-vx)
                if vy < 0 and y < WALL_TOP:
                    vy = q(-vy)
                if vy > 0 and y > WALL_BOTTOM:
                    vy = q(-vy)
            else:
                # no rebound: wind suck to y=200 when blown past sides (unguided)
                if inp.guided == 0:
                    if vx > 1.0 and x > WALL_RIGHT and inp.wind > 0:
                        y = SNAP_Y
                    if vx < 1.0 and x < WALL_LEFT and inp.wind < 0:
                        # asm: vx < 1 (incl. negative) and x < 10 and wind < 0
                        y = SNAP_Y

        if y < Y_KILL_LO or y > Y_KILL_HI:
            stop = StopReason.Y_BOUNDS
            break

    return FlightResult(
        positions=positions,
        xs=xs,
        ys=ys,
        stop=stop,
        hit_color=hit_color,
        steps=len(positions),
        min_x=mn_x,
        max_x=mx_x,
        min_y=mn_y,
        max_y=mx_y,
        min_vx=mn_vx,
        max_vx=mx_vx,
        min_vy=mn_vy,
        max_vy=mx_vy,
    )


def _simulate_fp(inp: FlightInput, terrain: Terrain) -> FlightResult:
    """16.16 fixed-point port candidate (same control flow)."""
    rad = math.radians(inp.angle)
    c = to_fp(math.cos(rad))
    s = to_fp(math.sin(rad))
    barrel = to_fp(BARREL)
    facing = to_fp(float(inp.facing))
    x = to_fp(float(inp.tank_x)) + fp_mul(fp_mul(c, barrel), facing)
    y = to_fp(float(inp.tank_y)) - fp_mul(s, barrel)
    pdiv = to_fp(POWER_DIV)
    power = to_fp(float(inp.power))
    speed = fp_div(power, pdiv)
    vx = fp_mul(fp_mul(speed, c), facing)
    vy = -fp_mul(speed, s) if s != 0 else 0

    step = to_fp(STEP_DIV)
    g_step = fp_div(to_fp(GRAVITY), step)
    w_step = fp_div(fp_div(to_fp(float(inp.wind)), to_fp(WIND_DIV)), step)
    fuse = 1000 - 2 * inp.men
    positions: List[Tuple[int, int]] = []
    hit_color = 0
    stop = StopReason.MAX_STEPS

    for _ in range(inp.max_steps):
        x += fp_div(vx, step)
        y += fp_div(vy, step)
        vy += g_step
        vx += w_step
        px, py = x >> FP_SHIFT, y >> FP_SHIFT  # trunc toward −∞ for neg; OK for playfield
        if x < 0:
            px = -((-x) >> FP_SHIFT)
        if y < 0:
            py = -((-y) >> FP_SHIFT)
        positions.append((px, py))

        xf, yf = from_fp(x), from_fp(y)
        in_band = (yf < 189.0) and (xf < 309.0) and (yf > 33.0) and (xf > 11.0)
        if in_band:
            hit_color = 0
            for dx, dy in DIAMOND:
                cpix = terrain.get(px + dx, py + dy)
                if _is_hit_color(cpix):
                    hit_color = cpix
                    is_tank = TANK_COLOR_LO <= cpix <= TANK_COLOR_HI
                    if inp.power < fuse or is_tank:
                        if inp.power == fuse and cpix == DIRT_COLOR:
                            pass
                        elif is_tank and 12 <= inp.weapon <= 16:
                            vy = -fp_mul(vy, to_fp(BOUNCE_SCALE))
                        else:
                            stop = StopReason.TANK if is_tank else StopReason.TERRAIN
                            break
            if stop != StopReason.MAX_STEPS:
                break
        else:
            if inp.rebound:
                if vx < 0 and xf < WALL_LEFT:
                    vx = -vx
                if vx > 0 and xf > WALL_RIGHT:
                    vx = -vx
                if vy < 0 and yf < WALL_TOP:
                    vy = -vy
                if vy > 0 and yf > WALL_BOTTOM:
                    vy = -vy
            elif inp.guided == 0:
                if from_fp(vx) > 1.0 and xf > WALL_RIGHT and inp.wind > 0:
                    y = to_fp(SNAP_Y)
                if from_fp(vx) < 1.0 and xf < WALL_LEFT and inp.wind < 0:
                    y = to_fp(SNAP_Y)

        if yf < Y_KILL_LO or yf > Y_KILL_HI:
            stop = StopReason.Y_BOUNDS
            break

    return FlightResult(
        positions=positions,
        stop=stop,
        hit_color=hit_color,
        steps=len(positions),
    )


def impact_pixel(result: FlightResult) -> Optional[Tuple[int, int]]:
    if not result.positions:
        return None
    return result.positions[-1]
