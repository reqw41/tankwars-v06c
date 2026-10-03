"""T05: межраундовый цикл (scripts/ref/match.py) против настоящей игры.

tests/fixtures/t05/match/{a,b,c}.json — события 224b:327c (scripts/probe/match_fixtures.py): вход в перетасовку, раунд,
экран результатов и магазин; на каждом — записи игроков, типы управления, стратегии закупки, RandSeed.
"""
import sys
from pathlib import Path
import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT / 'scripts' / 'ref'), str(ROOT / 'scripts' / 't03'), str(ROOT / 'scripts')]
import check_match  # noqa: E402


@pytest.mark.parametrize('name', ['a', 'b', 'c'])
def test_match_loop_matches_original(name):
    res = check_match.run(ROOT / 'tests/fixtures/t05/match' / f'{name}.json')
    for k, (ok, total) in res.items():
        assert total > 0 and ok == total, f'{k}: {ok}/{total}'
