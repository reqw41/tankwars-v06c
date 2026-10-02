"""Execution tests for Turbo Pascal 6 RTL Real48 / LongInt / Random (unicorn)."""
from __future__ import annotations

import math
import struct
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from real48 import (  # noqa: E402
    almost_equal,
    float_to_real48,
    float_to_regs,
    real48_to_float,
    regs_to_float,
)
from emu16 import (  # noqa: E402
    DS_SEG,
    Emu16,
    STACK_SEG,
    STACK_SP,
    call_far,
    result_real,
)

SYS = 0x1C5B


def _seed(emu: Emu16, seed: int = 1) -> None:
    emu.write_bytes(DS_SEG, 0x3774, struct.pack("<I", seed & 0xFFFFFFFF))


def _call_far_keepds(emu: Emu16, off: int, **regs):
    emu.set_regs(cs=SYS, ds=DS_SEG, es=DS_SEG, ss=STACK_SEG, sp=STACK_SP, **regs)
    emu.push16(0xF000)
    emu.push16(0x0000)
    return emu.run(SYS, off, stop_addrs=[(0xF000, 0x0000)])


def _real_binop(off: int, a: float, b: float) -> float:
    ax, bx, dx = float_to_regs(a)
    cx, si, di = float_to_regs(b)
    return result_real(call_far(Emu16(), SYS, off, ax=ax, bx=bx, dx=dx, cx=cx, si=si, di=di))


def _real_unary(off: int, a: float) -> float:
    ax, bx, dx = float_to_regs(a)
    return result_real(call_far(Emu16(), SYS, off, ax=ax, bx=bx, dx=dx))


def _long_to_regs(v: int):
    v &= 0xFFFFFFFF
    return v & 0xFFFF, (v >> 16) & 0xFFFF


def _regs_to_long(ax: int, dx: int) -> int:
    v = (ax & 0xFFFF) | ((dx & 0xFFFF) << 16)
    if v >= 0x80000000:
        v -= 0x100000000
    return v


# ---- real48 converter ----
@pytest.mark.parametrize(
    "x",
    [0.0, 1.0, -1.0, 0.5, -0.5, 2.0, math.pi, math.e, 123.456, -0.001, 1e6, -9999.25, 1e12, 1e30, -1e6],
)
def test_real48_roundtrip(x):
    y = real48_to_float(float_to_real48(x))
    assert almost_equal(x, y, 1.0)


# ---- Real arithmetic (≥6 inputs each) ----
REAL_CASES = [0.0, 1.0, -1.0, 2.5, -3.25, 100.0, -0.125, 7.0]


@pytest.mark.parametrize("a", REAL_CASES)
@pytest.mark.parametrize("b", [0.0, 1.0, -2.0, 3.5, -0.5, 10.0])
def test_real_add(a, b):
    got = _real_binop(0x112B, a, b)
    assert almost_equal(got, a + b, 1.0)


@pytest.mark.parametrize("a", REAL_CASES)
@pytest.mark.parametrize("b", [0.0, 1.0, -2.0, 3.5, -0.5, 10.0])
def test_real_sub(a, b):
    got = _real_binop(0x1131, a, b)
    assert almost_equal(got, a - b, 1.0)


@pytest.mark.parametrize("a", [1e6, 1e12, -1e6])
@pytest.mark.parametrize("b", [1.0, 2.0, -0.5])
def test_real_add_large(a, b):
    got = _real_binop(0x112B, a, b)
    assert almost_equal(got, a + b, 8.0)


@pytest.mark.parametrize("a", [1e6, 1e12])
@pytest.mark.parametrize("b", [2.0, 0.5])
def test_real_mul_large(a, b):
    got = _real_binop(0x113D, a, b)
    assert almost_equal(got, a * b, 8.0)


@pytest.mark.parametrize("a", [0.0, 1.0, -1.0, 15.0, -8.0, 100.0])
@pytest.mark.parametrize("b", [1.0, -2.0, 3.0, 0.5, 4.0, -5.0])
def test_real_div(a, b):
    got = _real_binop(0x1143, a, b)
    assert almost_equal(got, a / b, 1.0)


@pytest.mark.parametrize("a", [0.0, 1.0, -1.0, 5.0, -3.0, 12.0])
def test_sqr(a):
    assert almost_equal(_real_unary(0x1137, a), a * a, 1.0)


@pytest.mark.parametrize(
    "a,b,zf,cf",
    [
        (1.0, 1.0, 1, 0),
        (1.0, 2.0, 0, 1),
        (2.0, 1.0, 0, 0),
        (-1.0, 1.0, 0, 1),
        (0.0, 0.0, 1, 0),
        (3.5, -3.5, 0, 0),
    ],
)
def test_real_cmp(a, b, zf, cf):
    ax, bx, dx = float_to_regs(a)
    cx, si, di = float_to_regs(b)
    regs = call_far(Emu16(), SYS, 0x114D, ax=ax, bx=bx, dx=dx, cx=cx, si=si, di=di)
    flags = regs["flags"]
    assert ((flags >> 6) & 1) == zf
    assert (flags & 1) == cf


@pytest.mark.parametrize("v", [0, 1, -1, 2, 100, -100, 123456, -999999])
def test_long_to_real(v):
    ax, dx = _long_to_regs(v)
    got = result_real(call_far(Emu16(), SYS, 0x1151, ax=ax, dx=dx, bx=0))
    assert almost_equal(got, float(v), 1.0)


@pytest.mark.parametrize(
    "v,exp",
    [
        (0.0, 0),
        (1.0, 1),
        (-1.0, -1),
        (3.7, 3),
        (-3.7, -3),
        (100.5, 100),
        (-2.3, -2),
        (1.9, 1),
        (40000.0, 40000),
        (-40000.0, -40000),
        (70000.5, 70000),
        (-70000.5, -70000),
    ],
)
def test_trunc(v, exp):
    ax, bx, dx = float_to_regs(v)
    regs = call_far(Emu16(), SYS, 0x1155, ax=ax, bx=bx, dx=dx)
    assert _regs_to_long(regs["ax"], regs["dx"]) == exp


@pytest.mark.parametrize(
    "v,exp",
    [
        (0.0, 0),
        (1.0, 1),
        (-1.0, -1),
        (3.7, 4),
        (-3.7, -4),
        (100.5, 101),
        (-2.3, -2),
        (1.5, 2),
        (-1.5, -2),
        (40000.4, 40000),
        (-40000.4, -40000),
        (70000.5, 70001),
        (-70000.5, -70001),
    ],
)
def test_round(v, exp):
    ax, bx, dx = float_to_regs(v)
    regs = call_far(Emu16(), SYS, 0x115B, ax=ax, bx=bx, dx=dx)
    assert _regs_to_long(regs["ax"], regs["dx"]) == exp


@pytest.mark.parametrize(
    "v,exp",
    [(4.75, 4.0), (-3.25, -3.0), (0.5, 0.0), (9.9, 9.0), (-0.1, 0.0), (0.0, 0.0)],
)
def test_int(v, exp):
    assert almost_equal(_real_unary(0x119F, v), exp, 1.0)


@pytest.mark.parametrize(
    "v,exp",
    [(4.75, 0.75), (-3.25, -0.25), (0.0, 0.0), (1.0, 0.0), (-1.5, -0.5), (100.125, 0.125)],
)
def test_frac(v, exp):
    assert almost_equal(_real_unary(0x11F0, v), exp, 1.0)


@pytest.mark.parametrize("v", [0.0, 1.0, 4.0, 9.0, 2.0, 0.25])
def test_sqrt(v):
    assert almost_equal(_real_unary(0x1204, v), math.sqrt(v), 1.0)


@pytest.mark.parametrize("v", [0.0, 1.0, -1.0, math.pi / 6, math.pi / 3, -0.5])
def test_cos(v):
    assert almost_equal(_real_unary(0x1263, v), math.cos(v), 8.0)


@pytest.mark.parametrize("v", [0.0, 1.0, -1.0, math.pi / 6, math.pi / 2, -0.5])
def test_sin(v):
    assert almost_equal(_real_unary(0x1276, v), math.sin(v), 8.0)


def test_cos_half_pi_near_zero():
    """TP Cos(π/2) rounds to exact 0; math.cos is ~1e-16."""
    assert abs(_real_unary(0x1263, math.pi / 2)) < 1e-10



@pytest.mark.parametrize("v", [0.0, 1.0, -1.0, 0.5, -0.5, 2.0])
def test_arctan(v):
    assert almost_equal(_real_unary(0x144D, v), math.atan(v), 8.0)


@pytest.mark.parametrize("v", [0.0, 1.0, -1.0, 3.5, -3.5, 100.0])
def test_abs(v):
    assert almost_equal(_real_unary(0x1619, v), abs(v), 1.0)


# ---- LongInt ----
@pytest.mark.parametrize(
    "a,b",
    [(0, 0), (2, 3), (100, 200), (-2, 3), (0x10000, 2), (12345, 67), (-100, -7)],
)
def test_long_mul(a, b):
    ax, dx = _long_to_regs(a)
    cx, bx = _long_to_regs(b)
    regs = call_far(Emu16(), SYS, 0x0A12, ax=ax, dx=dx, cx=cx, bx=bx)
    assert _regs_to_long(regs["ax"], regs["dx"]) == a * b


@pytest.mark.parametrize(
    "a,b",
    [(100, 5), (-100, 5), (100, -5), (-100, -5), (0x20000, 2), (1, 1)],
)
def test_long_div(a, b):
    ax, dx = _long_to_regs(a)
    cx, bx = _long_to_regs(b)
    regs = call_far(Emu16(), SYS, 0x0A2D, ax=ax, dx=dx, cx=cx, bx=bx)
    assert _regs_to_long(regs["ax"], regs["dx"]) == a // b


@pytest.mark.parametrize(
    "a,b,quot,rem",
    [
        (-7, 2, -3, -1),
        (7, 2, 3, 1),
        (-7, -2, 3, -1),
        (7, -2, -3, 1),
        (10, 3, 3, 1),
        (-10, 3, -3, -1),
    ],
)
def test_long_div_rem(a, b, quot, rem):
    """LongDiv: DX:AX = quotient (DX=hi); rem in CX=lo / BX=hi (same layout as divisor)."""
    ax, dx = _long_to_regs(a)
    cx, bx = _long_to_regs(b)
    regs = call_far(Emu16(), SYS, 0x0A2D, ax=ax, dx=dx, cx=cx, bx=bx)
    assert _regs_to_long(regs["ax"], regs["dx"]) == quot
    assert _regs_to_long(regs["cx"], regs["bx"]) == rem


# ---- Random ----
def test_random_real_range():
    emu = Emu16()
    _seed(emu, 1)
    vals = []
    for _ in range(12):
        regs = _call_far_keepds(emu, 0x1600)
        vals.append(result_real(regs))
    assert len(vals) >= 6
    assert all(0.0 <= v < 1.0 for v in vals)
    assert len(set(round(v, 9) for v in vals)) > 1


def test_random_word_range():
    emu = Emu16()
    _seed(emu, 42)
    vals = []
    for _ in range(20):
        emu.set_regs(cs=SYS, ds=DS_SEG, es=DS_SEG, ss=STACK_SEG, sp=STACK_SP)
        emu.push16(100)
        emu.push16(0xF000)
        emu.push16(0)
        regs = emu.run(SYS, 0x15EA, stop_addrs=[(0xF000, 0)])
        vals.append(regs["ax"])
    assert all(0 <= v < 100 for v in vals)
    assert len(set(vals)) > 1


# Count of distinct RTL entry points exercised by execution tests above:
# RealAdd, RealSub, RealMul, RealDiv, Sqr, RealCmp, LongToReal, Trunc, Round,
# Int, Frac, Sqrt, Sin, Cos, ArcTan, Abs, LongMul, LongDiv, RandomReal, RandomWord
# = 20 functions
