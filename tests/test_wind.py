"""Wind generation tests: model sequences match unicorn original @ 2583:2567."""
from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
sys.path.insert(0, str(ROOT / "scripts" / "ref"))

from wind import (  # noqa: E402
    MODE_NAMES,
    SPANS,
    WindMode,
    default_seeds,
    generate_wind_emu,
    generate_wind_model,
    run_distributions,
)

OUT = ROOT / "work" / "T02"


@pytest.mark.parametrize("mode", list(range(6)))
@pytest.mark.parametrize("seed", [1, 2, 7, 42, 99, 12345, 0xDEAD, 0xBEEF])
def test_wind_model_matches_emu(mode, seed):
    assert generate_wind_model(mode, seed) == generate_wind_emu(mode, seed)


def test_none_always_zero():
    for s in default_seeds(50):
        assert generate_wind_emu(WindMode.NONE, s) == 0


def test_spans_table():
    assert SPANS == (0, 20, 100, 300, 4000)


def test_distributions_gale_extremes():
    """≥1000 seeds per named mode; write artifacts for the report."""
    OUT.mkdir(parents=True, exist_ok=True)
    stats = run_distributions(1000)
    summary = {
        name: {"mode": st.mode, "n": st.n, "min": st.min, "max": st.max}
        for name, st in stats.items()
    }
    (OUT / "wind_dist.json").write_text(json.dumps(summary, indent=2))
    from wind import format_report

    (OUT / "wind_dist.txt").write_text(format_report(stats))
    assert summary["None"]["n"] >= 1000
    assert summary["None"]["min"] == 0 and summary["None"]["max"] == 0
    assert summary["Gale"]["n"] >= 1000
    # Gale can reach near clamp after ×4 amplifications
    assert summary["Gale"]["min"] <= -10000
    assert summary["Gale"]["max"] >= 10000
    assert set(summary) >= {"None", "Low", "Norm", "High", "Gale"}


def test_rnd_uses_modes_0_to_4():
    """RND (5) must produce winds consistent with some base mode."""
    # With many seeds, RND should not be stuck at 0 only
    vals = [generate_wind_emu(WindMode.RND, s) for s in default_seeds(200)]
    assert any(v != 0 for v in vals)
