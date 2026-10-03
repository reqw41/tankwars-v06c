"""Проверка планировщиков ИИ: структура после первого вызова (план) и RandSeed."""
import sys, json, zlib, glob
from pathlib import Path
sys.path[:0] = ['scripts/ref', 'scripts']
from game import P
from ai import Hist, plan, ai_type, choose_code
from tprandom import TPRandom

only = sys.argv[1:] 
res = {}
for d in sorted(x for x in glob.glob('work/T05/ai_*') if Path(x).is_dir()):
    if only and not any(o in d for o in only):
        continue
    for c in json.loads((Path(d) / 'index.json').read_text()):
        recs = [bytes.fromhex(h) for h in c['recs']]
        ps = [P.from_rec(i, recs[i][0x0E:] + bytes(0x0E)) for i in range(1, len(recs))]
        p = ps[c['player'] - 1]
        name = recs[c['player']][1:1 + recs[c['player']][0]]
        h = Hist(bytes.fromhex(c['hist'])); h1 = Hist(bytes.fromhex(c['hist1']))
        v = bytearray(zlib.decompress((Path(d) / f"{c['name']}.v0.z").read_bytes()))
        bg = zlib.decompress((Path(d) / f"{c['name']}.bg.z").read_bytes())
        rng = TPRandom(c['seed0'])
        reb = bool(c['flags']['rebound'])
        t = ai_type(name, reb)
        key = f'{name.decode()} (тип {t})'
        res.setdefault(key, [0, 0])
        res[key][1] += 1
        if h.planned:
            res[key][0] += 1; continue          # план был готов заранее — планировщик не вызывался
        try:
            plan(v, bg, ps, p, h, rng, reb, name, wind=c['flags']['wind']) if 'wind' in plan.__code__.co_varnames else plan(v, bg, ps, p, h, rng, reb, name)
            code = choose_code(p, h)
        except NotImplementedError as e:
            continue
        flds = lambda x: (x.power, x.angle, x.facing, x.weapon, x.w(0x7E6), x.w(0))
        good = flds(h) == flds(h1) and rng.seed == c['seeds'][0] and code == c['codes'][0]
        res[key][0] += good
        if not good:
            print(d, c['name'], 'план', flds(h), 'ориг', flds(h1), 'rng', rng.seed == c['seeds'][0], 'код', code, c['codes'][0], 'стены', reb)
for k, (a, b) in res.items():
    print(f'{k}: {a}/{b}')
