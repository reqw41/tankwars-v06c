import sys, json, zlib
from pathlib import Path
sys.path.insert(0, 'scripts/ref')
from explosion import explode, Player
from player_rec import decode
from tprandom import TPRandom

def check(d):
    d = Path(d); ok = 0; idx = json.loads((d / 'index.json').read_text())
    for c in idx:
        pre = bytearray(zlib.decompress((d / f"{c['name']}.pre.z").read_bytes()))
        bg = zlib.decompress((d / f"{c['name']}.bg.z").read_bytes())
        post = zlib.decompress((d / f"{c['name']}.post.z").read_bytes())
        recs = [decode(bytes.fromhex(h)) for h in c['pre']['players']]
        ps = [Player(i + 1, r['x'], r['y'], r['men'], r['shield'], r['score'], bool(r['alive'])) for i, r in enumerate(recs)]
        rng = TPRandom(c['pre']['seed'])
        explode(pre, bg, ps, c['x'], c['y'], c['hit_color'], c['shooter'], c['weapon'], rng, c['sound'])
        exp = [decode(bytes.fromhex(h)) for h in c['post']['players']]
        got = [{'men': p.men, 'shield': p.shield, 'score': p.score} for p in ps]
        want = [{'men': e['men'], 'shield': e['shield'], 'score': e['score']} for e in exp]
        vdiff = [(k % 320, k // 320, post[k], pre[k]) for k in range(64000) if post[k] != pre[k]]
        good = not vdiff and got == want and rng.seed == c['post']['seed']
        ok += good
        print(c['name'], 'w', c['weapon'], 'vram', len(vdiff), vdiff[:3], 'pl', got == want, '' if got == want else (got, want), 'rng', rng.seed == c['post']['seed'])
    print('match', ok, '/', len(idx))

if __name__ == '__main__':
    check(sys.argv[1])
