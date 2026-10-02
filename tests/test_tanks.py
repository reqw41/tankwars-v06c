"""T03: расстановка и посадка танков (2eef:0dbc..10c6) + рамка (2b39:0386) + ствол (1062:059f).

Полный конвейер начала раунда от сида: фон (из игры) -> рельеф (terrain.py) -> танки (tanks.py).
Эталон: VRAM оригинала на возврате в 2583:255b (SHA1 всего экрана) и поля игроков.
"""
import hashlib, json, sys, zlib
from pathlib import Path
import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts' / 'ref'))
from tprandom import TPRandom  # noqa: E402
from terrain import generate, render  # noqa: E402
from tanks import place_tanks, line, BARREL  # noqa: E402

FXD = ROOT / 'tests' / 'fixtures' / 't03' / 'placement'
IDX = json.loads((FXD / 'index.json').read_text())


@pytest.mark.parametrize('case', IDX, ids=lambda c: c['name'])
def test_round_start_vram_matches_original(case):
    bg = zlib.decompress((FXD / f"{case['name']}.bg.z").read_bytes())
    rng = TPRandom(case['seed'])
    v = render(generate(rng, case['players']), bytearray(bg))
    tanks = place_tanks(rng, case['players'], v, bg, rebound_walls=bool(case['rebound']))
    got = [{'x': t.x, 'y': t.y, 'power': t.power, 'angle': t.angle, 'facing': t.facing,
            'men': t.men, 'alive': 1} for t in tanks]
    assert got == case['tanks']
    if hashlib.sha1(bytes(v)).hexdigest() != case['vram_sha1']:
        orig = zlib.decompress((FXD / f"{case['name']}.vram.z").read_bytes())
        bad = [(k % 320, k // 320, orig[k], v[k]) for k in range(64000) if orig[k] != v[k]]
        pytest.fail(f'{len(bad)} px differ, first {bad[:5]}')


def test_fixtures_cover_both_wall_modes_and_players():
    assert {c['rebound'] for c in IDX} == {0, 1}
    assert {c['players'] for c in IDX} >= {2, 3, 4, 6, 8}


def test_barrel_table_quirks():
    # TP6 Cos(0)=0.99999999999454 -> Trunc(8*cos) = 7: ствол при 0° имеет длину 7, а не 8
    assert BARREL[0] == (7, 0)
    assert BARREL[90] == (0, 7)
    assert BARREL[45] == (5, 5)


@pytest.mark.parametrize('seg', [((0, 0), (5, 2)), ((0, 0), (2, 5)), ((5, 2), (0, 0)), ((0, 5), (5, 0)), ((3, 3), (3, 3))])
def test_line_endpoints(seg):
    v = bytearray(64000)
    (x1, y1), (x2, y2) = [(a + 50, b + 50) for a, b in seg]
    line(v, x1, y1, x2, y2, 7)
    assert v[y1 * 320 + x1] == 7 and v[y2 * 320 + x2] == 7
    assert sum(1 for b in v if b == 7) == max(abs(x2 - x1), abs(y2 - y1)) + 1
