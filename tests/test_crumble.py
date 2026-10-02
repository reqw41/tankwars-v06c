"""T03: осыпание (2b39:03da -> 1062:027e) и падение танков (2b39:0020) — модель scripts/ref/crumble.py.

Эталоны из настоящей игры: scripts/probe/crumble_fixtures.py (ИИ Lobber x4, крупное оружие на взрывах,
Crumble% 100/50/10 и Inertia Dampener подменены на входе). Сравнение: VRAM побайтно, x/y/men, Dampener, RandSeed.
"""
import json, struct, sys, zlib
from pathlib import Path
import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts' / 'ref'))
sys.path.insert(0, str(ROOT / 'scripts' / 't03'))
from check_crumble import run_case  # noqa: E402
from player_rec import decode  # noqa: E402
from crumble import crumble  # noqa: E402

D = ROOT / 'tests/fixtures/t03/crumble'
IDX = json.loads((D / 'index.json').read_text())


@pytest.mark.parametrize('c', IDX, ids=lambda c: c['name'])
def test_matches_original(c):
    v, tanks, damp, rng = run_case(D, c)
    post = zlib.decompress((D / f"{c['name']}.post.z").read_bytes())
    want = [bytes.fromhex(h) for h in c['post']['players']]
    assert [(t.x, t.y, t.men) for t in tanks] == [(decode(w)['x'], decode(w)['y'], decode(w)['men']) for w in want]
    assert [damp[i + 1] for i in range(len(want))] == [struct.unpack_from('<i', w, 0x49)[0] for w in want]
    assert rng.seed == c['post']['seed']
    assert bytes(v) == post


def test_fixture_coverage():
    names = {c['event'] for c in IDX}
    assert names == {'crumble', 'fall'}
    big = [c for c in IDX if c['event'] == 'crumble' and c['vram_changed'] > 300]
    assert len(big) >= 3
    assert {c['pre']['percent'] for c in IDX if c['event'] == 'crumble'} >= {10, 50, 100}


def test_crumble_column_falls_until_support():
    v = bytearray(64000); bg = bytes([40]) * 64000
    for y in range(100, 105):
        v[y * 320 + 50] = 2              # висящий столбик земли
    v[150 * 320 + 50] = 2                # опора
    crumble(v, bg)
    col = [y for y in range(200) if v[y * 320 + 50] == 2]
    assert col == list(range(145, 151))
