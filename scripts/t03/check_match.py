"""Сверка межраундового цикла (scripts/ref/match.py) с событиями настоящей игры (scripts/probe/match_fixtures.py)."""
import sys, json
from pathlib import Path
sys.path[:0] = ['scripts/ref', 'scripts']
from match import shuffle, ai_shop, results
from tprandom import TPRandom


def run(path):
    ev = json.loads(Path(path).read_text())
    res = {'перетасовка': [0, 0], 'магазин': [0, 0], 'результаты': [0, 0]}
    for a, b in zip(ev, ev[1:]):
        n = len(a['recs']) - 1
        if a['event'] == 'shuffle' and b['event'] == 'round':
            rng = TPRandom(a['seed'])
            recs, ctrl = list(a['recs']), list(a['ctrl'])
            strat = list(a['strategy'])
            shuffle(rng, recs, strat, ctrl)
            ok = recs[1:] == b['recs'][1:] and ctrl[1:] == b['ctrl'][1:] and strat[1:] == b['strategy'][1:] and rng.seed == b['seed']
            res['перетасовка'][0] += ok; res['перетасовка'][1] += 1
        elif a['event'] == 'results' and b['event'] == 'shop':
            rng = TPRandom(a['seed'])
            recs = [bytes.fromhex(x) for x in a['recs']]
            ctrl, strat = list(a['ctrl']), list(a['strategy'])
            results(rng, recs, strat, ctrl, auto=True)
            ok = [x.hex() for x in recs[1:]] == b['recs'][1:] and ctrl[1:] == b['ctrl'][1:] and strat[1:] == b['strategy'][1:] and rng.seed == b['seed']
            res['результаты'][0] += ok; res['результаты'][1] += 1
        elif a['event'] == 'shop' and b['event'] == 'shuffle':
            for i in range(1, n + 1):
                rec = bytearray(bytes.fromhex(a['recs'][i])[0x0E:] + bytes(0x0E))
                went = False
                if a['ctrl'][i] == 3 and a['ai_buys']:
                    went = ai_shop(rec, a['strategy'][i])
                want = bytes.fromhex(b['recs'][i])[0x0E:] + bytes(0x0E)
                ok = bytes(rec) == want
                res['магазин'][0] += ok; res['магазин'][1] += 1
                if not ok:
                    d = [(hex(o), rec[o], want[o]) for o in range(0x61) if rec[o] != want[o]]
                    print('магазин: игрок', i, 'стратегия', a['strategy'][i], 'заходил', went, d[:12])
            if a['seed'] != b['seed']:
                print('магазин: RandSeed изменился')
    return res


if __name__ == '__main__':
    for p in sys.argv[1:]:
        for k, (a, b) in run(p).items():
            print(f'{p}: {k}: {a}/{b}')
