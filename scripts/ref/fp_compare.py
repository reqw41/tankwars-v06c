#!/usr/bin/env python3
"""Compare fixed-point flight formats vs Real48 reference (25 ballistics scenarios).

Formats:
  - 16.16 for x,y,vx,vy
  - 16.8 position + 8.8 velocity
  - 24.8 position + 8.16 velocity  (24-bit accumulators)

Writes work/T02/fp_compare.txt and .json; also prints a summary to stdout.
"""
from __future__ import annotations

import json
import math
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Dict, List, Optional, Tuple

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
sys.path.insert(0, str(ROOT / "scripts" / "ref"))
sys.path.insert(0, str(ROOT / "scripts" / "probe"))

from ballistics import (  # noqa: E402
    BARREL,
    BOUNCE_SCALE,
    DIAMOND,
    DIRT_COLOR,
    FlightInput,
    GRAVITY,
    POWER_DIV,
    SNAP_Y,
    STEP_DIV,
    StopReason,
    TANK_COLOR_HI,
    TANK_COLOR_LO,
    Terrain,
    WALL_BOTTOM,
    WALL_LEFT,
    WALL_RIGHT,
    WALL_TOP,
    WIND_DIV,
    Y_KILL_HI,
    Y_KILL_LO,
    deg_to_rad,
    q,
    trunc0,
)
from real48 import float_to_real48, real48_to_float  # noqa: E402
import flight_trace as ft  # noqa: E402

OUT = ROOT / "work" / "T02"


@dataclass
class FPFormat:
    name: str
    # position: value = raw / 2^pos_frac ; stored in pos_bits signed
    pos_frac: int
    pos_bits: int
    vel_frac: int
    vel_bits: int
    # rough 8080 cost: adds of that width + shifts for mul/div approximations
    cost_note: str


FORMATS = [
    FPFormat("16.16", 16, 32, 16, 32, "32-bit add/shift; mul via 16×16→32"),
    FPFormat("pos16.8_vel8.8", 8, 24, 8, 16, "24-bit pos add; 16-bit vel; cheap on 8080"),
    FPFormat("pos24.8_vel8.16", 8, 32, 16, 24, "32-bit pos; 24-bit vel (3-byte)"),
]


def _mask(bits: int) -> int:
    return (1 << bits) - 1


def _to_signed(v: int, bits: int) -> int:
    v &= _mask(bits)
    sign = 1 << (bits - 1)
    return v - (1 << bits) if v & sign else v


def _quantize(x: float, frac: int, bits: int) -> int:
    raw = int(round(x * (1 << frac)))
    return _to_signed(raw, bits)


def _to_float(raw: int, frac: int) -> float:
    return raw / float(1 << frac)


def _fp_mul(a: int, b: int, a_frac: int, b_frac: int, out_frac: int, out_bits: int) -> int:
    # (a/2^af)*(b/2^bf) = prod/2^(af+bf) → shift to out_frac
    prod = a * b
    sh = a_frac + b_frac - out_frac
    if sh >= 0:
        prod >>= sh
    else:
        prod <<= -sh
    return _to_signed(prod, out_bits)


def _fp_div(a: int, b: int, a_frac: int, b_frac: int, out_frac: int, out_bits: int) -> int:
    if b == 0:
        return 0
    # (a/2^af)/(b/2^bf) = a/b * 2^(bf-af) → want out_frac
    # prod = a * 2^(out_frac + b_frac - a_frac) / b
    sh = out_frac + b_frac - a_frac
    num = a << sh if sh >= 0 else a
    if sh < 0:
        # avoid losing bits: multiply numerator first when possible
        num = a
        den_shift = -sh
        # result = a / b / 2^den_shift
        qv = num // b
        qv >>= den_shift
    else:
        qv = num // b
    return _to_signed(qv, out_bits)


def simulate_fp(
    inp: FlightInput,
    terrain: Terrain,
    fmt: FPFormat,
) -> List[Tuple[int, int]]:
    pf, pb, vf, vb = fmt.pos_frac, fmt.pos_bits, fmt.vel_frac, fmt.vel_bits
    rad = deg_to_rad(inp.angle)
    # use float trig then quantize (same as Real48 path init sources)
    c = math.cos(rad)
    s = math.sin(rad)
    x = float(inp.tank_x) + c * BARREL * float(inp.facing)
    y = float(inp.tank_y) - s * BARREL
    vx = (float(inp.power) / POWER_DIV) * c * float(inp.facing)
    vy = (float(inp.power) / POWER_DIV) * s
    if abs(vy) > 1e-15:
        vy = -vy

    xi = _quantize(x, pf, pb)
    yi = _quantize(y, pf, pb)
    vxi = _quantize(vx, vf, vb)
    vyi = _quantize(vy, vf, vb)

    step_v = _quantize(STEP_DIV, vf, vb)  # for vel/step → need pos delta
    # delta_pos = vel / STEP : result in pos format
    g_add = _quantize(GRAVITY / STEP_DIV, vf, vb)
    w_add = _quantize(float(inp.wind) / WIND_DIV / STEP_DIV, vf, vb)
    fuse = 1000 - 2 * inp.men
    positions: List[Tuple[int, int]] = []

    one_pos = 1 << pf
    wall_l = _quantize(WALL_LEFT, pf, pb)
    wall_r = _quantize(WALL_RIGHT, pf, pb)
    wall_t = _quantize(WALL_TOP, pf, pb)
    wall_b = _quantize(WALL_BOTTOM, pf, pb)
    snap = _quantize(SNAP_Y, pf, pb)
    y_lo = _quantize(Y_KILL_LO, pf, pb)
    y_hi = _quantize(Y_KILL_HI, pf, pb)
    band_y_lo = _quantize(33.0, pf, pb)
    band_y_hi = _quantize(189.0, pf, pb)
    band_x_lo = _quantize(11.0, pf, pb)
    band_x_hi = _quantize(309.0, pf, pb)
    one_vel = _quantize(1.0, vf, vb)

    for _ in range(inp.max_steps):
        dx = _fp_div(vxi, step_v if step_v else 1, vf, vf, pf, pb)
        dy = _fp_div(vyi, step_v if step_v else 1, vf, vf, pf, pb)
        xi = _to_signed(xi + dx, pb)
        yi = _to_signed(yi + dy, pb)
        vyi = _to_signed(vyi + g_add, vb)
        vxi = _to_signed(vxi + w_add, vb)

        xf, yf = _to_float(xi, pf), _to_float(yi, pf)
        px, py = trunc0(xf), trunc0(yf)
        positions.append((px, py))

        in_band = (yi < band_y_hi) and (xi < band_x_hi) and (yi > band_y_lo) and (xi > band_x_lo)
        if in_band:
            for ddx, ddy in DIAMOND:
                cpix = terrain.get(px + ddx, py + ddy)
                if cpix == DIRT_COLOR or TANK_COLOR_LO <= cpix <= TANK_COLOR_HI:
                    is_tank = TANK_COLOR_LO <= cpix <= TANK_COLOR_HI
                    if inp.power < fuse or is_tank:
                        if inp.power == fuse and cpix == DIRT_COLOR:
                            continue
                        if is_tank and 12 <= inp.weapon <= 16:
                            # vy = -vy * 1.2
                            vyi = _fp_mul(-vyi, _quantize(BOUNCE_SCALE, vf, vb), vf, vf, vf, vb)
                        else:
                            return positions
        else:
            if inp.rebound:
                if vxi < 0 and xi < wall_l:
                    vxi = -vxi
                if vxi > 0 and xi > wall_r:
                    vxi = -vxi
                if vyi < 0 and yi < wall_t:
                    vyi = -vyi
                if vyi > 0 and yi > wall_b:
                    vyi = -vyi
            elif inp.guided == 0:
                if vxi > one_vel and xi > wall_r and inp.wind > 0:
                    yi = snap
                if vxi < one_vel and xi < wall_l and inp.wind < 0:
                    yi = snap

        if yi < y_lo or yi > y_hi:
            return positions
    return positions


def _ref_path(inp: FlightInput, terrain: Terrain) -> List[Tuple[int, int]]:
    from ballistics import simulate

    return simulate(inp, terrain).positions


def _metrics(ref: List[Tuple[int, int]], got: List[Tuple[int, int]]) -> Dict:
    n = min(len(ref), len(got))
    max_dev = 0
    for i in range(n):
        dx = abs(ref[i][0] - got[i][0])
        dy = abs(ref[i][1] - got[i][1])
        max_dev = max(max_dev, dx, dy)
    # length mismatch counts as infinite-ish
    if len(ref) != len(got):
        max_dev = max(max_dev, abs(len(ref) - len(got)))
    r_imp = ref[-1] if ref else (0, 0)
    g_imp = got[-1] if got else (0, 0)
    return {
        "max_pixel_dev": max_dev,
        "impact_dx": g_imp[0] - r_imp[0],
        "impact_dy": g_imp[1] - r_imp[1],
        "ref_steps": len(ref),
        "fp_steps": len(got),
        "impact_match": r_imp == g_imp,
    }


def _input_terrain(sc: dict) -> Tuple[FlightInput, Terrain]:
    sc = dict(sc)
    sc.pop("label", None)
    terr = sc.pop("terrain", None)
    terrain = Terrain(bytearray(terr)) if terr is not None else Terrain.flat_ground(180)
    inp = FlightInput(
        angle=sc["angle"],
        power=sc["power"],
        facing=sc.get("facing", 1),
        tank_x=sc["tank_x"],
        tank_y=sc["tank_y"],
        wind=sc.get("wind", 0),
        rebound=sc.get("rebound", False),
        weapon=sc.get("weapon", 1),
        guided=sc.get("guided", 0),
        men=sc.get("men", 5),
    )
    return inp, terrain


def analyze_error_sources() -> str:
    """Explain structural FP error sources with script-computed examples."""
    lines = []
    # 1/5000 representability
    for frac, bits, label in [(16, 32, "16.16"), (8, 16, "8.8"), (16, 24, "8.16-in-24")]:
        w = 1.0 / 5000.0
        qv = _quantize(w, frac, bits)
        back = _to_float(qv, frac)
        lines.append(
            f"1/5000 as {label}: raw={qv} back={back!r} rel_err={(back - w) / w if w else 0:.6e}"
        )
    g = 0.01
    for frac, bits, label in [(16, 32, "16.16"), (8, 16, "8.8")]:
        qv = _quantize(g, frac, bits)
        back = _to_float(qv, frac)
        lines.append(f"0.01 gravity step as {label}: raw={qv} back={back!r}")
    # accumulation: N times add of quantized 0.01
    n = 1619
    acc16 = _quantize(0.0, 16, 32)
    g16 = _quantize(0.01, 16, 32)
    for _ in range(n):
        acc16 = _to_signed(acc16 + g16, 32)
    acc8 = _quantize(0.0, 8, 16)
    g8 = _quantize(0.01, 8, 16)
    for _ in range(n):
        acc8 = _to_signed(acc8 + g8, 16)
    true = 0.01 * n
    lines.append(
        f"after {n} adds of 0.01: true={true:.6f} 16.16={_to_float(acc16,16):.6f} "
        f"8.8={_to_float(acc8,8):.6f}"
    )
    return "\n".join(lines)


def cycle_delay_estimate(max_steps: int = 1619) -> str:
    """CRT_Delay(3) per visible step → target step rate for 8080."""
    delay_ms = 3  # from 2583:01c0 CRT_Delay(3) when ball drawn / flying path
    steps_per_sec = 1000.0 / delay_ms
    flight_s = max_steps / steps_per_sec
    # 8080 @ 3 MHz: rough cycles/sec
    mhz = 3.0e6
    cycles_per_step_budget = mhz / steps_per_sec
    lines = [
        f"Cycle Delay in flight path: CRT_Delay(3) → {delay_ms} ms/step (ball-visible branch).",
        f"Target rate ≥ {steps_per_sec:.1f} steps/s to not run slower than original.",
        f"Longest recorded trace steps={max_steps} → ≈{flight_s:.2f}s wall time at that rate.",
        f"8080 @ 3 MHz budget ≈ {cycles_per_step_budget:.0f} cycles/step.",
        "Rough op costs (order-of-magnitude on 8080):",
        "  16-bit add ~ 10–20 cycles; 32-bit add ~ 40–60;",
        "  16×16 mul library ~ 150–300; 32-bit shift chain ~ 50–100.",
        "  One physics step ≈ 4 adds + 2 div-by-10 + wind/gravity adds.",
        "  16.16 with software mul/div: ~800–2000 cycles/step → OK vs ~9000 budget.",
        "  8.8/16.8 lighter (~400–800 cycles/step) if accuracy allows.",
    ]
    return "\n".join(lines)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    rows = []
    max_steps_seen = 0
    for sc0 in ft.SCENARIOS:
        label = sc0["label"]
        inp, terrain = _input_terrain(sc0)
        ref = _ref_path(inp, terrain)
        max_steps_seen = max(max_steps_seen, len(ref))
        entry = {"label": label, "ref_steps": len(ref), "formats": {}}
        for fmt in FORMATS:
            got = simulate_fp(inp, terrain, fmt)
            entry["formats"][fmt.name] = _metrics(ref, got)
        rows.append(entry)

    # aggregates
    summary = {"formats": {}, "scenarios": rows}
    for fmt in FORMATS:
        impact_ok = sum(1 for r in rows if r["formats"][fmt.name]["impact_match"])
        max_dev = max(r["formats"][fmt.name]["max_pixel_dev"] for r in rows)
        avg_dev = sum(r["formats"][fmt.name]["max_pixel_dev"] for r in rows) / len(rows)
        summary["formats"][fmt.name] = {
            "impact_matches": f"{impact_ok}/{len(rows)}",
            "max_of_max_pixel_dev": max_dev,
            "mean_max_pixel_dev": avg_dev,
            "cost_note": fmt.cost_note,
            "pos": f"{fmt.pos_bits}.{fmt.pos_frac}",
            "vel": f"{fmt.vel_bits}.{fmt.vel_frac}",
        }

    err = analyze_error_sources()
    timing = cycle_delay_estimate(max_steps_seen)
    summary["error_sources"] = err.splitlines()
    summary["timing"] = timing.splitlines()
    # recommendation
    f1616 = summary["formats"]["16.16"]
    f168 = summary["formats"]["pos16.8_vel8.8"]
    f248 = summary["formats"]["pos24.8_vel8.16"]
    summary["recommendation"] = (
        f"Prefer full **16.16** for x/y/vx/vy: impact {f1616['impact_matches']}, "
        f"max path pixel-dev {f1616['max_of_max_pixel_dev']}, fits 8080 cycle budget. "
        f"pos24.8+vel8.16 is a fallback ({f248['impact_matches']}, "
        f"max-dev {f248['max_of_max_pixel_dev']}) if 32-bit muls are too heavy. "
        f"pos16.8+vel8.8 is unsuitable for wind (1/5000 → 0 in 8.8; impact only "
        f"{f168['impact_matches']})."
    )

    (OUT / "fp_compare.json").write_text(json.dumps(summary, indent=2))
    lines = ["# Fixed-point comparison vs Real48", ""]
    lines.append("## Per-format summary")
    for name, s in summary["formats"].items():
        lines.append(
            f"- **{name}**: impact {s['impact_matches']}, "
            f"max pixel-dev {s['max_of_max_pixel_dev']}, "
            f"mean max-dev {s['mean_max_pixel_dev']:.2f}; {s['cost_note']}"
        )
    lines.append("")
    lines.append("## Per-scenario impact (dx,dy) / max_dev")
    for r in rows:
        parts = [r["label"]]
        for fmt in FORMATS:
            m = r["formats"][fmt.name]
            parts.append(
                f"{fmt.name}: dev={m['max_pixel_dev']} imp=({m['impact_dx']},{m['impact_dy']})"
            )
        lines.append(" | ".join(parts))
    lines.append("")
    lines.append("## Error sources")
    lines.append(err)
    lines.append("")
    lines.append("## Timing / 8080 budget")
    lines.append(timing)
    lines.append("")
    lines.append("## Recommendation")
    lines.append(summary["recommendation"])
    text = "\n".join(lines) + "\n"
    (OUT / "fp_compare.txt").write_text(text)
    print(text)


if __name__ == "__main__":
    main()
