"""Ballistics model vs original FUN_2583_01c0 unicorn traces (≥20 scenarios)."""
from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
sys.path.insert(0, str(ROOT / "scripts" / "ref"))
sys.path.insert(0, str(ROOT / "scripts" / "probe"))

from ballistics import FlightInput, Terrain, simulate  # noqa: E402
import flight_trace as ft  # noqa: E402

TRACES = ROOT / "work" / "T02" / "traces"
_TRACE_CACHE: dict = {}


def _scenario_ids():
    return [s["label"] for s in ft.SCENARIOS]


def _terrain_for(sc: dict) -> Terrain:
    terr = sc.get("terrain")
    if terr is not None:
        return Terrain(bytearray(terr))
    return Terrain.flat_ground(180)


def _input_for(sc: dict) -> FlightInput:
    return FlightInput(
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


def _load_or_trace(label: str, scenarios: dict) -> dict:
    if label in _TRACE_CACHE:
        return _TRACE_CACHE[label]
    path = TRACES / f"{label}.json"
    sc = dict(scenarios[label])
    sc.pop("label")
    terr = sc.pop("terrain", None)
    need = True
    if path.exists():
        tr = json.loads(path.read_text())
        # invalidate stale cache when scenario knobs change
        if (
            tr.get("angle") == sc.get("angle")
            and tr.get("power") == sc.get("power")
            and tr.get("facing", 1) == sc.get("facing", 1)
            and tr.get("tank_x") == sc.get("tank_x")
            and tr.get("tank_y") == sc.get("tank_y")
            and tr.get("wind", 0) == sc.get("wind", 0)
            and tr.get("rebound", False) == sc.get("rebound", False)
            and tr.get("men", 5) == sc.get("men", 5)
        ):
            need = False
    if need:
        tr = ft.trace_flight(label=label, terrain=terr, **sc)
        TRACES.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(tr))
    _TRACE_CACHE[label] = tr
    return tr


@pytest.fixture(scope="module")
def scenarios():
    return {s["label"]: s for s in ft.SCENARIOS}


@pytest.mark.parametrize("label", _scenario_ids())
def test_trajectory_pixel_match(label, scenarios):
    sc = dict(scenarios[label])
    sc.pop("label")
    tr = _load_or_trace(label, scenarios)
    res = simulate(_input_for(sc), _terrain_for(sc))
    orig = [tuple(p) for p in tr["positions"]]
    assert len(res.positions) == len(orig)
    assert res.positions == orig


def test_at_least_20_scenarios(scenarios):
    assert len(scenarios) >= 20


def test_required_coverage(scenarios):
    labels = set(scenarios)
    assert "a0_p200" in labels
    assert "a90_p200" in labels
    assert "a0_facem1_p200" in labels
    assert "a90_facem1_p200" in labels
    assert "a45_p1" in labels
    assert "a20_p1000" in labels or "a45_p500" in labels
    assert "wind0" in labels
    assert "wind_gale_pos" in labels and "wind_gale_neg" in labels
    assert "wind_gale_max" in labels and "wind_gale_min" in labels
    assert "hit_ground" in labels
    assert "hit_tank" in labels
    assert "wall_norebound" in labels
    assert "wall_rebound" in labels
    assert "high_arc" in labels
    # Addendum 3 dirt-fuse cases (pixel-matched via test_trajectory_pixel_match)
    for lab in (
        "fuse_m100_p700",
        "fuse_m100_p799",
        "fuse_m100_p800",
        "fuse_m100_p801",
        "fuse_m100_p900",
        "fuse_m100_p1000",
        "fuse_m50_p500",
        "fuse_m50_p899",
        "fuse_m50_p900",
        "fuse_m50_p901",
    ):
        assert lab in labels


def test_hit_tank_color(scenarios):
    tr = _load_or_trace("hit_tank", scenarios)
    assert tr["hit_color"] == 21


def test_fixed_point_impact_rate(scenarios):
    """16.16 port: count scenarios where impact pixel matches Real48/original."""
    matches = 0
    for label, sc0 in scenarios.items():
        sc = dict(sc0)
        sc.pop("label")
        tr = _load_or_trace(label, scenarios)
        res = simulate(_input_for(sc), _terrain_for(sc), fixed_point=True)
        if res.positions and tuple(tr["positions"][-1]) == res.positions[-1]:
            matches += 1
    assert matches >= 15
    out = ROOT / "work" / "T02"
    out.mkdir(parents=True, exist_ok=True)
    (out / "fp_impact_matches.txt").write_text(f"{matches}/{len(scenarios)}\n")


@pytest.mark.parametrize(
    "angle,power,facing,tx,ty",
    [
        (0, 100, 1, 80, 150),
        (90, 100, 1, 160, 160),
        (45, 200, -1, 200, 150),
    ],
)
def test_live_unicorn_spotcheck(angle, power, facing, tx, ty):
    """Spot-check: live unicorn vs model (not only cached JSON)."""
    tr = ft.trace_flight(
        angle=angle,
        power=power,
        facing=facing,
        tank_x=tx,
        tank_y=ty,
        wind=0,
        rebound=False,
        label="live",
    )
    res = simulate(
        FlightInput(
            angle=angle,
            power=power,
            facing=facing,
            tank_x=tx,
            tank_y=ty,
        ),
        Terrain.flat_ground(180),
    )
    assert res.positions == [tuple(p) for p in tr["positions"]]
