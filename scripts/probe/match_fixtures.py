"""Эталоны межраундового цикла 224b:327c: перетасовка (224b:25a7), раунд (2583:2531), бонус победителю,
результаты (224b:2641), магазин (224b:0e51). Ничего не подменяется, кроме числа раундов и флага «компьютеры покупают».
usage: match_fixtures.py OUT_DIR N_EVENTS [AI] [PLAYERS]
"""
import json, os, struct, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from t03_common import boot_to_round, computer_keys  # noqa: E402
from unicorn import UC_HOOK_CODE  # noqa: E402

REC, ST, HIST, HST = 0x3EEE, 0x61, 0x8896, 0x802
POINTS = {'shuffle': (0x224B, 0x25A7), 'round': (0x2583, 0x2531), 'results': (0x224B, 0x2641), 'shop': (0x224B, 0x0E51)}
TURN = {'fire': (0x2583, 0x2976), 'turn_end': (0x2583, 0x2CEE)}      # при TW_TRACE=1: трасса ходов в turns.json


def snap(g, n):
    return {'seed': struct.unpack('<I', g.rd(0x3774, 4))[0],
            'recs': [g.rd(REC + ST * i, ST).hex() for i in range(0, n + 1)],
            'ctrl': list(struct.unpack(f'<{n + 1}h', g.rd(0x8880, 2 * (n + 1)))),
            'strategy': [g.rw(HIST + HST * i + 0x800) for i in range(0, n + 1)],
            'hist_n': [g.rw(HIST + HST * i) for i in range(0, n + 1)],
            'winner': g.rw(0x3EEC), 'round': g.rw(0x3EEA), 'rounds': g.rw(0x3EE8), 'ai_buys': g.rd(0x8869, 1)[0]}


def capture(out: Path, n_events, ai=2, players=4, dos_time=(0x2A3B, 0x4C5D)):
    out.mkdir(parents=True, exist_ok=True)
    g = boot_to_round(dos_time, players=players, players_keys=computer_keys(players, ai))
    g.ww(0x3EE8, 6)
    g.uc.mem_write(g.ds * 16 + 0x8869, b'\x01')
    pts = dict(POINTS)
    trace = bool(os.environ.get('TW_TRACE'))
    if trace:
        pts.update(TURN)
    addr = {g.ghidra_abs(s) * 16 + o: k for k, (s, o) in pts.items()}
    turns = []
    st = {'ev': None, 'skip': None}

    def hk(uc, a, size, d):
        if st['skip'] == a:
            st['skip'] = None
            return
        st['ev'], st['at'] = addr[a], a
        uc.emu_stop()
    for a in addr:
        g.uc.hook_add(UC_HOOK_CODE, hk, None, a, a)
    ev = []
    while len(ev) < n_events:
        st['ev'] = None
        r = g.run(300_000_000)
        if st['ev'] is None:
            if r == 'exit' or r.startswith('error'):
                print('стоп', r, g.where(), flush=True)
                break
            continue
        if st['ev'] in TURN:
            sh = g.rd(0x885E, 1)[0]
            turns.append({'ev': st['ev'], 'after_event': len(ev), 'seed': struct.unpack('<I', g.rd(0x3774, 4))[0], 'shooter': sh,
                          'recs': [g.rd(REC + ST * i, ST).hex() for i in range(1, players + 1)],
                          'hist': g.rd(HIST + HST * sh, 0x80).hex(), 'wind': struct.unpack('<h', g.rd(0x3EDE, 2))[0], 'rebound': g.rd(0x8200, 1)[0]})
            st['skip'] = st['at']
            (out / 'turns.json').write_text(json.dumps(turns))
            continue
        s = snap(g, players)
        s['event'] = st['ev']
        ev.append(s)
        print(len(ev), st['ev'], 'раунд', s['round'], 'победитель', s['winner'], flush=True)
        st['skip'] = st['at']
        (out / 'events.json').write_text(json.dumps(ev, indent=1))


if __name__ == '__main__':
    a = sys.argv
    capture(Path(a[1]), int(a[2]), ai=int(a[3]) if len(a) > 3 else 2, players=int(a[4]) if len(a) > 4 else 4)
