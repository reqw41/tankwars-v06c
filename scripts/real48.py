"""Turbo Pascal Real48 (6-byte real) ↔ Python float.

Layout (little-endian bytes b0..b5):
  b0       = biased exponent (0 ⇒ value is 0; bias = 129)
  b1..b5   = mantissa, MSB of b5 is the sign bit; implied integer bit = 1
  value    = (1 - 2*sign) * (1.mant) * 2^(exp-129)
"""
from __future__ import annotations

import math
import struct
from typing import Tuple


BIAS = 129
MANT_BITS = 39  # stored bits; +1 implied


def real48_to_float(data: bytes) -> float:
    if len(data) != 6:
        raise ValueError("Real48 needs 6 bytes")
    exp = data[0]
    if exp == 0:
        return 0.0
    mant = int.from_bytes(data[1:6], "little")
    sign = (mant >> 39) & 1
    frac = mant & ((1 << 39) - 1)
    # significand = 1.frac
    sig = (1 << 39) | frac
    val = math.ldexp(float(sig), exp - BIAS - 39)
    return -val if sign else val


def float_to_real48(x: float) -> bytes:
    if not math.isfinite(x) or x == 0.0:
        return bytes(6)
    sign = 1 if x < 0 else 0
    ax = abs(x)
    m, e = math.frexp(ax)  # ax = m * 2^e, 0.5 <= m < 1
    # Want (1.frac) * 2^(exp-129) with 1.frac in [1, 2)
    # m in [0.5, 1) → 2m in [1, 2), exponent adjustment: e-1
    m2 = m * 2.0
    exp = e - 1 + BIAS
    if exp <= 0:
        return bytes(6)
    if exp > 255:
        # overflow → max magnitude (TP raises runtime error; we saturate for tests)
        exp = 255
        frac = (1 << 39) - 1
    else:
        # m2 = 1.frac → frac bits
        scaled = m2 * float(1 << 39)
        n = int(scaled + 0.5)
        if n >= (1 << 40):
            n >>= 1
            exp += 1
            if exp > 255:
                exp = 255
                n = (1 << 40) - 1
        # clear implied bit
        frac = n & ((1 << 39) - 1)
        if exp > 255:
            exp = 255
    mant = frac | (sign << 39)
    return bytes([exp & 0xFF]) + mant.to_bytes(5, "little")


def pack_regs(data: bytes) -> Tuple[int, int, int]:
    """Return (AX, BX, DX) register triple for a Real48 value."""
    if len(data) != 6:
        raise ValueError("need 6 bytes")
    ax, bx, dx = struct.unpack("<HHH", data)
    return ax, bx, dx


def unpack_regs(ax: int, bx: int, dx: int) -> bytes:
    return struct.pack("<HHH", ax & 0xFFFF, bx & 0xFFFF, dx & 0xFFFF)


def regs_to_float(ax: int, bx: int, dx: int) -> float:
    return real48_to_float(unpack_regs(ax, bx, dx))


def float_to_regs(x: float) -> Tuple[int, int, int]:
    return pack_regs(float_to_real48(x))


def mantissa_ulps(a: float, b: float) -> float:
    """Approximate distance in Real48 mantissa LSBs between two values."""
    if a == 0 and b == 0:
        return 0.0
    ref = abs(a) if abs(a) >= abs(b) else abs(b)
    if ref == 0:
        return 0.0
    # frexp: ref = m * 2^e with 0.5 <= m < 1 → binary exponent of significand scale
    _m, e = math.frexp(ref)
    # ULP of Real48 at this magnitude: 2^(e-1-39)
    ulp = math.ldexp(1.0, e - 1 - MANT_BITS)
    return abs(a - b) / ulp


def almost_equal(a: float, b: float, ulps: float = 1.0) -> bool:
    if a == b:
        return True
    if not (math.isfinite(a) and math.isfinite(b)):
        return False
    # Quantize both to Real48: denormals / tiny IEEE values become 0
    ra, rb = float_to_real48(a), float_to_real48(b)
    if ra == rb:
        return True
    if ra == bytes(6) or rb == bytes(6):
        # one side is Real48-zero; accept if the other is also tiny after rounding
        return real48_to_float(ra) == 0.0 and real48_to_float(rb) == 0.0
    return mantissa_ulps(a, b) <= ulps + 1e-9


def almost_equal_real48(a: float, b: float, ulps: float = 1.0) -> bool:
    """Compare after quantizing the reference `b` to Real48."""
    return almost_equal(a, real48_to_float(float_to_real48(b)), ulps=ulps)