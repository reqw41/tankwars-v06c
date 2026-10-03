import sys, json, zlib, os
from pathlib import Path
sys.path[:0] = ['scripts/ref', 'scripts']
from game import P, Flags, turn
from tprandom import TPRandom

D = Path(os.environ.get('TURN_FX', 'work/T05/turns'))


def run(c):
    ld = lambda n: zlib.decompress((D / f"{c['name']}.{n}.z").read_bytes())
    v = bytearray(ld('pre')); bg = bytearray(ld('bg')); post = ld('post')
    f = c['pre']['flags']
    fl = Flags(rebound=bool(f['rebound']), crumble=f['crumble'], fall=bool(f['fall']), xkill=bool(f['xkill']),
               sound=bool(f['sound']), wind=f['wind'], ball_visible=not f.get('ball_inv', 1), trail=bool(f.get('trail', 0)))
    ps = [P.from_rec(i + 1, bytes.fromhex(h)) for i, h in enumerate(c['pre']['players'])]
    rng = TPRandom(c['pre']['seed'])
    err = None
    try:
        turn(v, bg, ps, f['shooter'], rng, fl)
    except Exception as e:  # noqa: BLE001
        err = repr(e)
    want = [P.from_rec(i + 1, bytes.fromhex(h)) for i, h in enumerate(c['post']['players'])]
    key = lambda p: (p.x, p.y, p.men, p.alive, p.shield, p.score)
    pl = [key(p) for p in ps] == [key(p) for p in want]
    bad = [(k % 320, k // 320, post[k], v[k]) for k in range(64000) if post[k] != v[k] and 28 <= k // 320 <= 192 and 8 <= k % 320 <= 312]
    bgp = D / f"{c['name']}.bgpost.z"
    if bgp.exists():
        bpost = zlib.decompress(bgp.read_bytes())
        bad += [('bg', k % 320, k // 320) for k in range(64000) if bpost[k] != bg[k]]
    return err, pl, rng.seed == c['post']['seed'], bad, ps, want


if __name__ == '__main__':
    ok = 0
    idx = json.loads((D / 'index.json').read_text())
    for c in idx:
        err, pl, sd, bad, ps, want = run(c)
        good = not err and pl and sd and not bad
        ok += good
        f = c['pre']['flags']
        if not good:
            print(c['name'], 'w', ps[f['shooter'] - 1].weapon, 'ball_inv', f.get('ball_inv'), 'trail', f.get('trail'), err or '', 'pl', pl, 'rng', sd, 'vram', len(bad), bad[:3])
    print('match', ok, '/', len(idx))
