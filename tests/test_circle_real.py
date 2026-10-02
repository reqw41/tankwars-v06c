"""T03 / открытый вопрос из T01b: рисует ли Circle (1827:11ea) в настоящей игре.

Вшитый VGA256 в стенде graph_env.make_graph_emu (без InitGraph) на SI=14h уходит в заглушку, и эллипс в
tests/test_graph.py рисует хук стенда. В настоящей игре (scripts/t03/gamerun.py, настоящий InitGraph) Circle
рисует сам — эталон снят из взрыва CRI: tests/fixtures/t03/circle_real.json.
"""
import json, os, sys
from pathlib import Path
import pytest

ROOT = Path(__file__).resolve().parents[1]
FX = json.loads((ROOT / 'tests/fixtures/t03/circle_real.json').read_text())


def test_real_circle_draws_full_ring():
    big = [c for c in FX if c['args'][2] >= 5]
    assert big, 'нет вызовов Circle с r>=5'
    for c in big:
        x, y, r = c['args']
        px = {tuple(p) for p in c['pixels']}
        assert px, 'Circle ничего не нарисовал'
        xs, ys = [p[0] for p in px], [p[1] for p in px]
        # центр (x,y) в координатах вьюпорта игры; размах ровно 2r+1 по обеим осям
        assert max(xs) - min(xs) == 2 * r and max(ys) - min(ys) == 2 * r


@pytest.mark.skipif(not os.environ.get('T03_LIVE'), reason='живой прогон игры; T03_LIVE=1')
def test_real_circle_live():
    sys.path.insert(0, str(ROOT / 'scripts' / 'probe'))
    from circle_real_probe import probe
    assert probe() == FX
