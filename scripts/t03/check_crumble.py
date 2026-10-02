import sys, json, zlib, struct
from pathlib import Path
sys.path.insert(0, 'scripts/ref')
from crumble import crumble_gate, tanks_fall
from tanks import Tank
from player_rec import decode
from tprandom import TPRandom


def run_case(d, c):
    v = bytearray(zlib.decompress((d / f"{c['name']}.pre.z").read_bytes()))
    bg = zlib.decompress((d / f"{c['name']}.bg.z").read_bytes())
    recs = [bytes.fromhex(h) for h in c['pre']['players']]
    rng = TPRandom(c['pre']['seed'])
    tanks = []
    for i, raw in enumerate(recs):
        r = decode(raw)
        tanks.append(Tank(i + 1, r['x'], r['y'], r['angle'], r['power'], r['facing'], r['men'], bool(r['alive'])))
    damp = {i + 1: struct.unpack_from('<i', raw, 0x49)[0] for i, raw in enumerate(recs)}
    if c['event'] == 'crumble':
        crumble_gate(v, bg, rng, c['pre']['percent'], bool(c['pre']['rebound']))
    else:
        tanks_fall(v, bg, tanks, rng, bool(c['pre']['rebound']), damp)
    return v, tanks, damp, rng


def check(d):
    d = Path(d); ok = 0; idx = json.loads((d / 'index.json').read_text())
    for c in idx:
        v, tanks, damp, rng = run_case(d, c)
        post = zlib.decompress((d / f"{c['name']}.post.z").read_bytes())
        want = [bytes.fromhex(h) for h in c['post']['players']]
        wd = [decode(w) for w in want]
        got_t = [(t.x, t.y, t.men) for t in tanks]; want_t = [(w['x'], w['y'], w['men']) for w in wd]
        got_d = [damp[i + 1] for i in range(len(want))]; want_d = [struct.unpack_from('<i', w, 0x49)[0] for w in want]
        bad = [(k % 320, k // 320, post[k], v[k]) for k in range(64000) if post[k] != v[k]]
        good = not bad and got_t == want_t and got_d == want_d and rng.seed == c['post']['seed']
        ok += good
        print(c['name'], 'vram', len(bad), bad[:3], 'tanks', got_t == want_t, '' if got_t == want_t else (got_t, want_t),
              'damp', got_d == want_d, 'rng', rng.seed == c['post']['seed'])
    print('match', ok, '/', len(idx))


if __name__ == '__main__':
    check(sys.argv[1])
