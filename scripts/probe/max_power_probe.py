#!/usr/bin/env python3
"""Prove Maximum Power = 10×men via gamerun (computer players).

Stops after the pre-fire clamp store at 2583:2957 (before AI overwrites power).
Writes work/T02/max_power_probe.json.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts" / "probe"))
sys.path.insert(0, str(ROOT / "scripts" / "t03"))

from t03_common import boot_to_round, run_to, computer_keys  # noqa: E402
from tanks_probe import player  # noqa: E402

OUT = ROOT / "work" / "T02" / "max_power_probe.json"
CLAMP_AFTER = (0x2583, 0x295B)  # after mov [di+3f0a], cx


def _probe_clamp(men: int | None, power: int) -> dict:
    g = boot_to_round((0x0C1E, 0x0F32), players=2, players_keys=computer_keys(2, 2))
    run_to(g, 0x2583, 0x255B)
    p1 = 0x3EFC + 0x61 * 1
    if men is not None:
        g.ww(p1 + 0x14, men)
    g.ww(p1 + 0x0E, power)
    men_now = g.rw(p1 + 0x14)
    run_to(g, *CLAMP_AFTER)
    power_after = g.rw(p1 + 0x0E)
    expected = min(power, 10 * men_now) if power > 10 * men_now else power
    # clamp only when power > 10*men
    if power > 10 * men_now:
        expected = 10 * men_now
    else:
        expected = power
    return {
        "men": men_now,
        "power_injected": power,
        "power_after_clamp": power_after,
        "expected": expected,
        "ok": power_after == expected,
    }


def main() -> None:
    g0 = boot_to_round((0x0C1E, 0x0F32), players=2, players_keys=computer_keys(2, 2))
    run_to(g0, 0x2583, 0x255B)
    placed = [player(g0, i) for i in range(1, 3)]

    case_a = _probe_clamp(None, 5000)  # natural men=100 → clamp to 1000
    case_b = _probe_clamp(50, 999)  # → 500
    case_c = _probe_clamp(None, 200)  # below max → unchanged

    result = {
        "addresses": {
            "clamp_mul": "2583:2925",
            "clamp_store": "2583:2957",
            "after_store": "2583:295b",
            "ai_then_fireshot": "2583:2963 then 298b",
            "hud_max_power": "30b8:08a1 displays men*10",
            "adjust_clamp": "2b39:0425 power keys clamp to men*10",
        },
        "formula": "max_power = 10 * men  (DOC «100*MEN» is wrong for this binary)",
        "placed": placed,
        "case_a_men100_clamp_down": case_a,
        "case_b_men50_clamp_down": case_b,
        "case_c_below_max_unchanged": case_c,
        "all_ok": case_a["ok"] and case_b["ok"] and case_c["ok"],
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(result, indent=2))
    print(json.dumps(result, indent=2))
    print("WROTE", OUT)
    if not result["all_ok"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
