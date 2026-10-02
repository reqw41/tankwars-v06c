"""T04: особое оружие — модель scripts/ref/weapons.py против эталонов настоящей игры."""
import json, struct, sys, zlib
from pathlib import Path
import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts' / 'ref'))
from weapons import sonic, cri  # noqa: E402
from tprandom import TPRandom  # noqa: E402

FX = ROOT / 'tests' / 'fixtures' / 't04'


def _cases(kind):
    p = FX / kind / 'index.json'
    if not p.exists():
        return []
    return [(kind, c) for c in json.loads(p.read_text())]


SONIC = _cases('sonic')
CRI = _cases('cri')


def _load(kind, c):
    d = FX / kind
    v = bytearray(zlib.decompress((d / f"{c['name']}.pre.z").read_bytes()))
    bg = zlib.decompress((d / f"{c['name']}.bg.z").read_bytes())
    post = zlib.decompress((d / f"{c['name']}.post.z").read_bytes())
    return v, bg, post


def _vp(c):
    x1, y1, x2, y2, clip = struct.unpack_from('<4HB', bytes.fromhex(c['viewport']))
    return (x1, y1, x2, y2), clip


@pytest.mark.parametrize('kind,c', SONIC, ids=[c['name'] for _, c in SONIC])
def test_sonic_matches_original(kind, c):
    v, bg, post = _load(kind, c)
    vp, clip = _vp(c)
    rng = TPRandom(c['pre']['seed'])
    sonic(v, bg, c['x'], c['y'], rng, c['sound'], vp, bool(clip))
    assert c['pre']['players'] == c['post']['players']
    assert rng.seed == c['post']['seed']
    bad = [i for i in range(64000) if v[i] != post[i]]
    assert not bad, f'{len(bad)} px, first {bad[:8]}'


@pytest.mark.parametrize('kind,c', CRI, ids=[c['name'] for _, c in CRI])
def test_cri_matches_original(kind, c):
    v, bg, post = _load(kind, c)
    players = [bytearray.fromhex(h) for h in c['pre']['players']]
    rng = TPRandom(c['pre']['seed'])
    cri(v, bg, players, c['x'], c['y'], c['hit_color'], c['shooter'], c['weapon'], rng, c['sound'])
    assert [bytes(p).hex() for p in players] == c['post']['players']
    assert rng.seed == c['post']['seed']
    bad = [i for i in range(64000) if v[i] != post[i]]
    assert not bad, f'{len(bad)} px, first {(bad[0]%320, bad[0]//320) if bad else None}'
