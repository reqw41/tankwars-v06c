"""T03: обычный взрыв 318e:00e0 (оружие 1,2,3,4,11) — модель scripts/ref/explosion.py против оригинала.

Эталоны сняты в настоящей игре (scripts/probe/explosion_fixtures.py): вход/выход VRAM, записи игроков, RandSeed.
explosion/        — 16 взрывов в землю (ИИ Lobber, 3 игрока), оружие и звук подменены на входе
explosion_direct/ — 12 прямых попаданий в чужой танк (аргумент цвета подменён), щиты 0/50/150/400
"""
import json, sys, zlib
from pathlib import Path
import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts' / 'ref'))
from explosion import explode, Player, ellipse_points, RADIUS  # noqa: E402
from player_rec import decode  # noqa: E402
from tprandom import TPRandom  # noqa: E402

SETS = ['explosion', 'explosion_direct']
CASES = [(s, c) for s in SETS for c in json.loads((ROOT / 'tests/fixtures/t03' / s / 'index.json').read_text())]


@pytest.mark.parametrize('sd,c', CASES, ids=[f"{s}-{c['name']}-w{c['weapon']}" for s, c in CASES])
def test_explosion_matches_original(sd, c):
    d = ROOT / 'tests/fixtures/t03' / sd
    v = bytearray(zlib.decompress((d / f"{c['name']}.pre.z").read_bytes()))
    bg = zlib.decompress((d / f"{c['name']}.bg.z").read_bytes())
    post = zlib.decompress((d / f"{c['name']}.post.z").read_bytes())
    recs = [decode(bytes.fromhex(h)) for h in c['pre']['players']]
    ps = [Player(i + 1, r['x'], r['y'], r['men'], r['shield'], r['score'], bool(r['alive'])) for i, r in enumerate(recs)]
    rng = TPRandom(c['pre']['seed'])
    explode(v, bg, ps, c['x'], c['y'], c['hit_color'], c['shooter'], c['weapon'], rng, c['sound'])
    want = [decode(bytes.fromhex(h)) for h in c['post']['players']]
    assert [(p.men, p.shield, p.score) for p in ps] == [(w['men'], w['shield'], w['score']) for w in want]
    assert rng.seed == c['post']['seed']
    bad = [k for k in range(64000) if v[k] != post[k]]
    assert not bad, f'{len(bad)} px differ'


def test_coverage_of_fixtures():
    weapons = {c['weapon'] for _, c in CASES}
    assert weapons == set(RADIUS)
    assert any(c['sound'] for _, c in CASES) and any(not c['sound'] for _, c in CASES)
    assert any(20 <= c['hit_color'] <= 29 for _, c in CASES)
    # есть урон по чужому танку с начислением очков
    def score_changed(c):
        a = [decode(bytes.fromhex(h))['score'] for h in c['pre']['players']]
        b = [decode(bytes.fromhex(h))['score'] for h in c['post']['players']]
        return a != b
    assert any(score_changed(c) for _, c in CASES)


def test_ellipse_is_symmetric_circle():
    pts = set(ellipse_points(100, 100, 5, 5))
    assert (100, 105) in pts and (100, 95) in pts and (105, 100) in pts and (95, 100) in pts
    assert all((200 - x, y) in pts and (x, 200 - y) in pts for x, y in pts)
