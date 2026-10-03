import sys, json, zlib, os
from pathlib import Path
sys.path[:0] = ['scripts/ref', 'scripts']
from game import P, round_start
from tprandom import TPRandom
D = Path(os.environ.get('RS_FX', 'work/T05/rstart'))
ok = 0
idx = json.loads((D / 'index.json').read_text())
for c in idx:
    ps = [P.from_rec(i + 1, bytes.fromhex(h)) for i, h in enumerate(c['pre']['players'])]
    cfg = c['pre']['cfg']
    rng = TPRandom(c['pre']['seed'])
    v, bg, reb, wind, first = round_start(rng, ps, cfg['walls_cfg'], cfg['bg_cfg'], cfg['wind_mode'])
    post = zlib.decompress((D / f"{c['name']}.post.z").read_bytes()); bgo = zlib.decompress((D / f"{c['name']}.bg.z").read_bytes())
    want = [P.from_rec(i + 1, bytes.fromhex(h)) for i, h in enumerate(c['post']['players'])]
    key = lambda p: (p.x, p.y, p.angle, p.power, p.facing, p.men, p.alive)
    vd = [(k % 320, k // 320) for k in range(64000) if post[k] != v[k] and 28 <= k // 320 <= 192 and 8 <= k % 320 <= 312]
    bd = sum(1 for k in range(64000) if bgo[k] != bg[k])
    good = (not vd and not bd and [key(p) for p in ps] == [key(p) for p in want] and rng.seed == c['post']['seed']
            and wind == c['post']['wind'] and int(reb) == c['post']['rebound'] and first == c['post']['first_raw'])
    ok += good
    print(c['name'], cfg, 'vram', len(vd), vd[:3], 'bg', bd, 'pl', [key(p) for p in ps] == [key(p) for p in want],
          'rng', rng.seed == c['post']['seed'], 'wind', wind, c['post']['wind'], 'reb', int(reb), c['post']['rebound'], 'first', first, c['post']['first_raw'])
    # какие ещё поля записи меняются в начале раунда
    for p0, w in zip([bytes.fromhex(h) for h in c['pre']['players']], [bytes.fromhex(h) for h in c['post']['players']]):
        chg = [o for o in range(0x61) if p0[o] != w[o]]
        if chg and c['name'] == 'r00':
            print('   поля записи меняются:', [hex(o) for o in chg])
print('match', ok, '/', len(idx))
