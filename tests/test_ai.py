"""T05: ИИ (scripts/ref/ai.py) против настоящей игры.

tests/fixtures/t05/ai/<набор>/ — по 12 ходов компьютера: записи игроков, структура ИИ до (hist) и после первого вызова
2cab:000d (hist1), экран до/после, коды всех вызовов, RandSeed. Наборы: m1 Mr. Stupid, birdy Birdy Bonker, m2 Lobber,
m3 Rifleman, m4 Lob & Shoot, m5 Windless Wit (со стенами), m6r Twanger (со стенами).
"""
import json, sys, zlib
from pathlib import Path
import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT / 'scripts' / 'ref'), str(ROOT / 'scripts')]
from game import P  # noqa: E402
from ai import Hist, plan, choose_code, computer_turn  # noqa: E402
from tprandom import TPRandom  # noqa: E402

FX = ROOT / 'tests/fixtures/t05/ai'
CASES = [(d.name, c) for d in sorted(FX.iterdir()) if d.is_dir() for c in json.loads((d / 'index.json').read_text())]
IDS = [f"{d}-{c['name']}" for d, c in CASES]


def _z(d, c, kind):
    return zlib.decompress((FX / d / f"{c['name']}.{kind}.z").read_bytes())


@pytest.mark.parametrize('d,c', CASES, ids=IDS)
def test_plan_matches_original(d, c):
    recs = [bytes.fromhex(h) for h in c['recs']]
    ps = [P.from_rec(i, recs[i][0x0E:] + bytes(0x0E)) for i in range(1, len(recs))]
    p = ps[c['player'] - 1]
    name = recs[c['player']][1:1 + recs[c['player']][0]]
    h, h1 = Hist(bytes.fromhex(c['hist'])), Hist(bytes.fromhex(c['hist1']))
    if h.planned:
        pytest.skip('план готов до вызова')
    rng = TPRandom(c['seed0'])
    plan(bytearray(_z(d, c, 'v0')), _z(d, c, 'bg'), ps, p, h, rng, bool(c['flags']['rebound']), name)
    code = choose_code(p, h)
    f = lambda x: (x.power, x.angle, x.facing, x.weapon, x.w(0x7E6), x.w(0))
    assert f(h) == f(h1)
    assert rng.seed == c['seeds'][0]
    assert code == c['codes'][0]


@pytest.mark.parametrize('d,c', CASES, ids=IDS)
def test_code_loop_matches_original(d, c):
    p = P.from_rec(c['player'], bytes.fromhex(c['recs'][c['player']])[0x0E:] + bytes(0x0E))
    h = Hist(bytes.fromhex(c['hist1']))
    h.planned = 1
    codes = computer_turn(bytearray(_z(d, c, 'v1')), _z(d, c, 'bg'), p, h, lambda hh: None)
    end = P.from_rec(c['player'], bytes.fromhex(c['rec_end'])[0x0E:] + bytes(0x0E))
    assert codes == c['codes']
    assert (p.angle, p.power, p.facing, p.weapon) == (end.angle, end.power, end.facing, end.weapon)
