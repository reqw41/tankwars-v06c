"""Tank Wars 2.5 round wind generation (FUN_2583_2531 @ 2583:2567..2675).

Modes DS:81f6 (menu None/Low/Norm/High/Gale/RND):
  0 None → span 0
  1 Low  → 20
  2 Norm → 100
  3 High → 300
  4 Gale → 4000
  5 RND  → RandomWord(5) picks 0..4 for this round

Algorithm (Real48 RandomReal thresholds 0.1,0.1,0.05,0.05):
  r = RandomWord(span)          # 0 if span=0
  wind = span//2 - r            # signed 16-bit idiv
  for p in (0.1, 0.1, 0.05, 0.05):
      if RandomReal() < p: wind *= 4
  clamp wind to [-30000, 30000]
"""
from __future__ import annotations

import struct
import sys
from collections import Counter
from dataclasses import dataclass
from enum import IntEnum
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Sequence, Tuple

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

from emu16 import (  # noqa: E402
    Emu16,
    STACK_SEG,
    STACK_SP,
)
from real48 import float_to_real48, real48_to_float  # noqa: E402

SRC_DS = 0x1E0D
MIRROR_DS = 0x5000
WIND_START = 0x2567  # after ClearDevice etc.; pure RNG → 3ede
WIND_END = 0x2675  # after clamp, before SetColor
SYS = 0x1C5B

SPANS = (0, 20, 100, 300, 4000)
THRESHOLDS = (0.1, 0.1, 0.05, 0.05)  # Real48 immediates cd7d / cd7c


class WindMode(IntEnum):
    NONE = 0
    LOW = 1
    NORM = 2
    HIGH = 3
    GALE = 4
    RND = 5


MODE_NAMES = {
    WindMode.NONE: "None",
    WindMode.LOW: "Low",
    WindMode.NORM: "Norm",
    WindMode.HIGH: "High",
    WindMode.GALE: "Gale",
    WindMode.RND: "RND",
}


def _as_i16(v: int) -> int:
    v &= 0xFFFF
    return v - 0x10000 if v >= 0x8000 else v


@dataclass
class WindStats:
    mode: int
    n: int
    values: List[int]
    min: int
    max: int
    hist: Dict[int, int]  # coarse buckets or raw counts for small ranges

    def histogram_buckets(self, width: int = 100) -> List[Tuple[int, int, int]]:
        """Return [(lo, hi, count), ...] covering [min,max]."""
        if not self.values:
            return []
        lo, hi = self.min, self.max
        if lo == hi:
            return [(lo, hi, len(self.values))]
        buckets: List[Tuple[int, int, int]] = []
        start = (lo // width) * width
        end = hi
        x = start
        while x <= end:
            a, b = x, x + width - 1
            c = sum(1 for v in self.values if a <= v <= b)
            if c:
                buckets.append((a, b, c))
            x += width
        return buckets


def generate_wind_emu(mode: int, seed: int) -> int:
    """Execute original instructions 2583:2567..2675 in unicorn; return DS:3ede."""
    emu = Emu16()
    ds = MIRROR_DS
    emu.write_bytes(ds, 0, emu.read_bytes(SRC_DS, 0, 0xF000))
    emu.write_bytes(ds, 0x3774, struct.pack("<I", seed & 0xFFFFFFFF))
    emu.write_u16(ds, 0x81F6, mode & 0xFFFF)
    emu.write_u16(ds, 0x81F8, 0)
    emu.write_u16(ds, 0x3EAE, 0)
    emu.write_u16(ds, 0x3EAC, 0)
    emu.write_u16(ds, 0x3EDE, 0)

    emu.set_regs(
        cs=0x2583,
        ds=ds,
        es=ds,
        ss=STACK_SEG,
        sp=STACK_SP,
        ax=0,
        bx=0,
        cx=0,
        dx=0,
        si=0,
        di=0,
        bp=0,
        flags=0x0202,
    )
    regs = emu.run(
        0x2583,
        WIND_START,
        stop_addrs=[(0x2583, WIND_END)],
        max_insns=5_000_000,
    )
    assert regs["cs"] == 0x2583 and regs["ip"] == WIND_END, regs
    return _as_i16(emu.read_u16(ds, 0x3EDE))


def generate_wind_model(mode: int, seed: int) -> int:
    """Same algorithm via unicorn RTL RandomWord/RandomReal (not the overlay code)."""
    from emu16 import call_far, result_real

    emu = Emu16()
    ds = SRC_DS
    emu.write_bytes(ds, 0x3774, struct.pack("<I", seed & 0xFFFFFFFF))

    def random_word(n: int) -> int:
        return call_far(emu, SYS, 0x15EA, stack_args=[n & 0xFFFF])["ax"] & 0xFFFF

    def random_real() -> float:
        return result_real(call_far(emu, SYS, 0x1600))

    eff = mode
    if eff == WindMode.RND:
        eff = random_word(5)
    span = SPANS[eff] if 0 <= eff < len(SPANS) else 0
    r = random_word(span)
    wind = _as_i16((span // 2) - r)
    for thr in THRESHOLDS:
        thr_q = real48_to_float(float_to_real48(thr))
        if random_real() < thr_q:
            wind = _as_i16((wind << 2) & 0xFFFF)  # two SHL as in asm
    if wind > 30000:
        wind = 30000
    if wind < -30000:
        wind = -30000
    return wind


def sample_mode(mode: int, seeds: Sequence[int]) -> WindStats:
    vals = [generate_wind_emu(mode, s) for s in seeds]
    return WindStats(
        mode=mode,
        n=len(vals),
        values=vals,
        min=min(vals) if vals else 0,
        max=max(vals) if vals else 0,
        hist=dict(Counter(vals)),
    )


def default_seeds(n: int = 1000, start: int = 1) -> List[int]:
    return list(range(start, start + n))


def run_distributions(
    n_per_mode: int = 1000, modes: Optional[Iterable[int]] = None
) -> Dict[str, WindStats]:
    modes = list(modes) if modes is not None else list(range(5))  # None..Gale
    seeds = default_seeds(n_per_mode)
    out: Dict[str, WindStats] = {}
    for m in modes:
        st = sample_mode(m, seeds)
        out[MODE_NAMES.get(WindMode(m), str(m))] = st
    return out


def format_report(stats: Dict[str, WindStats], bucket: int = 100) -> str:
    lines = []
    for name, st in stats.items():
        lines.append(f"## {name} (mode={st.mode}, n={st.n})")
        lines.append(f"min={st.min} max={st.max}")
        lines.append("histogram (bucket width %d):" % bucket)
        for a, b, c in st.histogram_buckets(bucket):
            lines.append(f"  [{a:+6d} .. {b:+6d}]: {c}")
        lines.append("")
    return "\n".join(lines)


if __name__ == "__main__":
    import argparse

    ap = argparse.ArgumentParser()
    ap.add_argument("-n", type=int, default=1000)
    ap.add_argument("--out", type=Path, default=ROOT / "work" / "T02" / "wind_dist.txt")
    args = ap.parse_args()
    stats = run_distributions(args.n)
    text = format_report(stats)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(text)
    # also JSON for report citation
    import json

    j = {
        name: {"mode": st.mode, "n": st.n, "min": st.min, "max": st.max}
        for name, st in stats.items()
    }
    args.out.with_suffix(".json").write_text(json.dumps(j, indent=2))
    print(text)
    print("wrote", args.out)
