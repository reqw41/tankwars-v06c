#!/usr/bin/env python3
"""Run original FUN_2583_01c0 in unicorn and record Trunc(x),Trunc(y) each step.

Writes JSON traces under work/T02/traces/. Uses a mirrored DS segment so high
game globals (0x81xx) do not overlap overlay code at 2583 in the flat image.
"""
from __future__ import annotations

import argparse
import json
import math
import struct
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
sys.path.insert(0, str(ROOT / "scripts" / "ref"))

from real48 import real48_to_float  # noqa: E402
from emu16 import (  # noqa: E402
    Emu16,
    STACK_SEG,
    STACK_SP,
    VGA_SEG,
    ghidra_to_linear,
)
from unicorn import UC_HOOK_CODE  # noqa: E402

FLIGHT_SEG = 0x2583
FLIGHT_OFF = 0x01C0
RECORD_OFF = 0x0B91  # after physics; curr x/y committed for draw/collision
SRC_DS = 0x1E0D
# Flat image: DS:0x7760 aliases 2583:0000 — mirror DS away from code.
MIRROR_DS = 0x5000

OUT_DIR = ROOT / "work" / "T02" / "traces"


def _patch_retf(emu: Emu16, seg: int, off: int, nargs_bytes: int = 0) -> None:
    if nargs_bytes:
        emu.write_bytes(
            seg, off, bytes([0xCA, nargs_bytes & 0xFF, (nargs_bytes >> 8) & 0xFF])
        )
    else:
        emu.write_bytes(seg, off, bytes([0xCB]))


def _stub_side_effects(emu: Emu16) -> None:
    """NOP sound/delay/draw/explosion; keep GetPixel (1691:0b0a) and RTL math."""
    stubs = [
        (0x17C5, 0x02C7, 2),  # CRT_Sound
        (0x17C5, 0x029C, 2),  # CRT_Delay
        (0x17C5, 0x02F4, 0),  # CRT_NoSound
        (0x1057, 0x0000, 0),  # palette tick
        (0x1062, 0x0213, 8),  # erase ball
        (0x1062, 0x0352, 10),  # trail
        (0x1062, 0x01E3, 4),  # put ball
        (0x1691, 0x0B2B, 8),  # DAC PutPixel helper
        (0x1691, 0x0AC1, 6),  # VGA PutPixel (would scribble if ES wrong)
        (0x1691, 0x0031, 10),  # fill/clear bar
        (0x1054, 0x0020, 16),  # explosion thunk
    ]
    for seg, off, n in stubs:
        _patch_retf(emu, seg, off, n)


def _write_player(
    emu: Emu16,
    ds: int,
    player: int,
    *,
    x: int,
    y: int,
    power: int,
    angle: int,
    facing: int,
    men: int = 5,
    weapon: int = 1,
    guided: int = 0,
) -> None:
    base = player * 0x61

    def w16(off: int, v: int) -> None:
        emu.write_u16(ds, off, v & 0xFFFF)

    w16(base + 0x3EFC, x)
    w16(base + 0x3EFE, y)
    w16(base + 0x3F0A, power)
    w16(base + 0x3F0C, angle)
    w16(base + 0x3F0E, facing)
    w16(base + 0x3F10, men)
    w16(base + 0x3F12, 1)  # alive / drawn
    w16(base + 0x3F13, weapon)
    w16(base + 0x3F15, guided)
    w16(base + 0x3F17, 0)
    w16(base + 0x3F19, 99)
    w16(base + 0x3F1B, 99)
    for i in range(20):
        w16(base + 0x3F1D + i * 2, 99)


def _fill_terrain(emu: Emu16, pixels: bytes) -> None:
    assert len(pixels) == 64000
    emu.write_bytes(VGA_SEG, 0, pixels)


def flat_ground(ground_y: int = 180, color: int = 2) -> bytes:
    v = bytearray(64000)
    for y in range(ground_y, 200):
        for x in range(320):
            v[y * 320 + x] = color
    return bytes(v)


def with_tank(
    ground_y: int, tank_x: int, tank_y: int, color: int = 21
) -> bytes:
    v = bytearray(flat_ground(ground_y))
    for dy in range(-3, 4):
        for dx in range(-5, 6):
            x, y = tank_x + dx, tank_y + dy
            if 0 <= x < 320 and 0 <= y < 200:
                v[y * 320 + x] = color
    return bytes(v)


def trace_flight(
    *,
    angle: int,
    power: int,
    facing: int = 1,
    tank_x: int = 50,
    tank_y: int = 150,
    wind: int = 0,
    rebound: bool = False,
    weapon: int = 1,
    guided: int = 0,
    men: int = 5,
    terrain: Optional[bytes] = None,
    player: int = 1,
    max_insns: int = 80_000_000,
    label: str = "",
) -> Dict[str, Any]:
    emu = Emu16()
    ds = MIRROR_DS
    emu.write_bytes(ds, 0, emu.read_bytes(SRC_DS, 0, 0xF000))
    _stub_side_effects(emu)

    _write_player(
        emu,
        ds,
        player,
        x=tank_x,
        y=tank_y,
        power=power,
        angle=angle,
        facing=facing,
        men=men,
        weapon=weapon,
        guided=guided,
    )
    for off, val in (
        (0x81FD, 0),
        (0x81FE, 0),
        (0x81FF, 0),  # sound off
        (0x8200, 1 if rebound else 0),
        (0x8201, 1),  # ball invisible → skip draw
        (0x8202, 0),  # no trail
    ):
        emu.write_bytes(ds, off, bytes([val]))
    emu.write_u16(ds, 0x3EDE, wind & 0xFFFF)
    emu.write_u16(ds, 0x3EDC, 1)
    emu.write_bytes(ds, 0x3774, struct.pack("<I", 0x12345678))  # RandSeed
    _fill_terrain(emu, terrain if terrain is not None else flat_ground())

    positions: List[Tuple[int, int]] = []
    floats: List[Tuple[float, float]] = []
    rec = ghidra_to_linear(FLIGHT_SEG, RECORD_OFF)

    def on_code(uc, address, size, data):  # noqa: ANN001
        if address != rec:
            return
        xb = bytes(uc.mem_read(ghidra_to_linear(ds, 0x4332), 6))
        yb = bytes(uc.mem_read(ghidra_to_linear(ds, 0x4338), 6))
        x = real48_to_float(xb)
        y = real48_to_float(yb)
        positions.append((int(math.trunc(x)), int(math.trunc(y))))
        floats.append((x, y))
        if len(positions) > 30000:
            uc.emu_stop()

    emu.uc.hook_add(UC_HOOK_CODE, on_code)
    emu.set_regs(
        cs=FLIGHT_SEG,
        ds=ds,
        es=ds,
        ss=STACK_SEG,
        sp=STACK_SP,
        flags=0x0202,
    )
    emu.push16(player)
    emu.push16(0xF000)
    emu.push16(0)
    regs = emu.run(
        FLIGHT_SEG,
        FLIGHT_OFF,
        stop_addrs=[(0xF000, 0)],
        max_insns=max_insns,
    )

    done = emu.read_bytes(ds, 0x81FD, 1)[0]
    hit = emu.read_u16(ds, 0x3EE4)
    # signed wind readback
    wraw = emu.read_u16(ds, 0x3EDE)
    wind_out = wraw - 0x10000 if wraw >= 0x8000 else wraw

    return {
        "label": label,
        "angle": angle,
        "power": power,
        "facing": facing,
        "tank_x": tank_x,
        "tank_y": tank_y,
        "wind": wind_out,
        "rebound": rebound,
        "weapon": weapon,
        "guided": guided,
        "men": men,
        "positions": positions,
        "n": len(positions),
        "done": done,
        "hit_color": hit,
        "cs_ip": f"{regs['cs']:04x}:{regs['ip']:04x}",
        "first": positions[:3],
        "last": positions[-3:] if positions else [],
    }


SCENARIOS: List[Dict[str, Any]] = [
    # angles at 0 / 90 / 180 family
    dict(label="a0_p200", angle=0, power=200, facing=1, tank_x=40, tank_y=150),
    dict(label="a90_p200", angle=90, power=200, facing=1, tank_x=160, tank_y=160),
    # angle is always 0..90; facing ±1 covers the other half (not literal 180°)
    dict(label="a0_facem1_p200", angle=0, power=200, facing=-1, tank_x=280, tank_y=150),
    dict(label="a90_facem1_p200", angle=90, power=200, facing=-1, tank_x=160, tank_y=160),
    dict(label="a45_p200", angle=45, power=200, facing=1, tank_x=50, tank_y=150),
    dict(label="a30_p150", angle=30, power=150, facing=1, tank_x=60, tank_y=155),
    dict(label="a60_p250", angle=60, power=250, facing=1, tank_x=70, tank_y=150),
    dict(label="a75_p100", angle=75, power=100, facing=1, tank_x=80, tank_y=150),
    # min / max power
    dict(label="a45_p1", angle=45, power=1, facing=1, tank_x=100, tank_y=140),
    dict(label="a45_p500", angle=45, power=500, facing=1, tank_x=40, tank_y=160),
    dict(label="a20_p1000", angle=20, power=1000, facing=1, tank_x=30, tank_y=150, men=10),
    # wind
    dict(label="wind0", angle=50, power=220, facing=1, tank_x=50, tank_y=150, wind=0),
    dict(label="wind_pos", angle=50, power=220, facing=1, tank_x=50, tank_y=150, wind=2000),
    dict(label="wind_neg", angle=50, power=220, facing=1, tank_x=50, tank_y=150, wind=-2000),
    # Gale extremes from work/T02/wind_dist.json (n=1000): min=-29184 max=28960
    dict(label="wind_gale_pos", angle=40, power=300, facing=1, tank_x=40, tank_y=150, wind=28960),
    dict(label="wind_gale_neg", angle=40, power=300, facing=-1, tank_x=280, tank_y=150, wind=-29184),
    dict(label="wind_gale_max", angle=50, power=220, facing=1, tank_x=100, tank_y=150, wind=28960),
    dict(label="wind_gale_min", angle=50, power=220, facing=1, tank_x=100, tank_y=150, wind=-29184),
    # terrain / tank hits
    dict(label="hit_ground", angle=35, power=180, facing=1, tank_x=50, tank_y=150),
    dict(
        label="hit_tank",
        angle=45,
        power=200,
        facing=1,
        tank_x=50,
        tank_y=150,
        # tank parked on a45_p200 arc around pixel (120,104)
        terrain=with_tank(180, 120, 104, 21),
    ),
    # walls
    dict(
        label="wall_norebound",
        angle=5,
        power=400,
        facing=1,
        tank_x=300,
        tank_y=100,
        rebound=False,
    ),
    dict(
        label="wall_rebound",
        angle=10,
        power=350,
        facing=1,
        tank_x=300,
        tank_y=80,
        rebound=True,
    ),
    dict(
        label="wall_rebound_left",
        angle=10,
        power=350,
        facing=-1,
        tank_x=20,
        tank_y=80,
        rebound=True,
    ),
    # go above screen and return
    dict(label="high_arc", angle=85, power=400, facing=1, tank_x=100, tank_y=170),
    dict(label="high_arc_wind", angle=80, power=450, facing=1, tank_x=80, tank_y=170, wind=-1500),
    # extras for ≥20
    dict(label="a15_p80", angle=15, power=80, facing=1, tank_x=55, tank_y=150),
    dict(label="a88_p120", angle=88, power=120, facing=1, tank_x=160, tank_y=160),
    dict(label="a5_p50", angle=5, power=50, facing=-1, tank_x=200, tank_y=150),
]


def run_all(out_dir: Path = OUT_DIR) -> List[Dict[str, Any]]:
    out_dir.mkdir(parents=True, exist_ok=True)
    results = []
    for sc in SCENARIOS:
        sc = dict(sc)
        label = sc.pop("label")
        terr = sc.pop("terrain", None)
        print(f"trace {label} ...", flush=True)
        tr = trace_flight(label=label, terrain=terr, **sc)
        results.append(tr)
        (out_dir / f"{label}.json").write_text(json.dumps(tr, indent=2))
        print(f"  n={tr['n']} last={tr['last']} hit={tr['hit_color']}")
    summary = [{"label": r["label"], "n": r["n"], "last": r["last"], "hit": r["hit_color"]} for r in results]
    (out_dir / "summary.json").write_text(json.dumps(summary, indent=2))
    return results


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--one", help="run single scenario label")
    ap.add_argument("--out", type=Path, default=OUT_DIR)
    args = ap.parse_args()
    if args.one:
        sc = next(s for s in SCENARIOS if s["label"] == args.one)
        sc = dict(sc)
        label = sc.pop("label")
        terr = sc.pop("terrain", None)
        tr = trace_flight(label=label, terrain=terr, **sc)
        args.out.mkdir(parents=True, exist_ok=True)
        (args.out / f"{label}.json").write_text(json.dumps(tr, indent=2))
        print(json.dumps({k: tr[k] for k in ("label", "n", "first", "last", "hit_color", "done")}, indent=2))
    else:
        run_all(args.out)


if __name__ == "__main__":
    main()
