"""T05: анимации гибели танка (285c, Random(7)) — модель scripts/ref/death.py против настоящей игры.

death/   — 28 событий (по 4 на вариант), death_b/ — ещё 28: звук через раз, Explotions Kill выключен в каждом 4-м.
Сравнение: VRAM весь экран, men/щит/очки всех танков, RandSeed после анимации.
"""
import json, os, sys
from pathlib import Path
import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT / 'scripts' / 'ref'), str(ROOT / 'scripts' / 't03'), str(ROOT / 'scripts')]
import check_death  # noqa: E402

CASES = [(d, c) for d in ('death', 'death_b') for c in json.loads((ROOT / 'tests/fixtures/t05' / d / 'index.json').read_text())]


@pytest.mark.parametrize('d,c', CASES, ids=[f"{d}-{c['name']}" for d, c in CASES])
def test_death_matches_original(d, c):
    check_death.D = ROOT / 'tests/fixtures/t05' / d
    ex = (lambda c: {'wind': c.get('wind', 0), 'explosions_kill': bool(c.get('xkill', 0))}) if c['variant'] in (0, 1, 2, 3) else None
    pl, sd, bad, ts, want = check_death.run(c, ex)
    assert pl, ([t.men for t in ts], [t.men for t in want])
    assert sd
    assert not bad, f'{len(bad)} px'


def test_all_variants_sound_and_xkill_covered():
    assert {c['variant'] for _, c in CASES} == set(range(7))
    assert {c['sound'] for _, c in CASES} == {0, 1}
    assert {c.get('xkill') for _, c in CASES} >= {0, 1}
