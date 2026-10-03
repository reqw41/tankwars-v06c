import sys, json, zlib, struct
from pathlib import Path
sys.path[:0] = ['scripts/ref', 'scripts']
import death
from tanks import Tank
from player_rec import decode
from tprandom import TPRandom

import os
D = Path(os.environ.get('DEATH_FX', 'tests/fixtures/t05/death'))


def load_tanks(hexes):
    ts = []
    for i, h in enumerate(hexes):
        r = decode(bytes.fromhex(h)); b = bytes.fromhex(h)
        t = Tank(i + 1, r['x'], r['y'], r['angle'], r['power'], r['facing'], r['men'], bool(r['alive']))
        t.shield = r['shield']; t.score = r['score']; t.damp = struct.unpack_from('<i', b, 0x49)[0]
        ts.append(t)
    return ts


def run(c, extra=None):
    ld = lambda n: zlib.decompress((D / f"{c['name']}.{n}.z").read_bytes())
    v = bytearray(ld('pre')); bg = ld('bg'); post = ld('post')
    ts = load_tanks(c['pre']['players'])
    rng = TPRandom(c['pre']['seed'])
    fn = getattr(death, f"death{c['variant']}")
    kw = extra(c) if extra else {}
    fn(v, bg, ts, c['victim'], rng, bool(c['sound']), **kw)
    want = load_tanks(c['post']['players'])
    pl = [(t.men, t.shield, t.score) for t in ts] == [(t.men, t.shield, t.score) for t in want]
    bad = [(k % 320, k // 320, post[k], v[k]) for k in range(64000) if post[k] != v[k]]
    return pl, rng.seed == c['post']['seed'], bad, ts, want


if __name__ == '__main__':
    only = set(int(a) for a in sys.argv[1:])
    for c in json.loads((D / 'index.json').read_text()):
        if only and c['variant'] not in only:
            continue
        if not hasattr(death, f"death{c['variant']}"):
            continue
        ex = (lambda c: {'wind': c.get('wind', 0), 'explosions_kill': bool(c.get('xkill', 0))}) if c['variant'] in (0, 1, 2, 3) else None
        pl, sd, bad, ts, want = run(c, ex)
        print(c['name'], 'игроки', pl, 'rng', sd, 'vram', len(bad), bad[:4], '' if pl else ([t.men for t in ts], [t.men for t in want]))
