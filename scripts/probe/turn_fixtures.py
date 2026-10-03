"""Эталоны целого хода: от решения игрока (2583:2976) до конца обработки смертей (2583:2cee).

Ничего не подменяется: ИИ (Lobber и др.) играет сам. Сохраняются экран, фон, записи игроков, RandSeed,
флаги раунда и номер стреляющего на входе и на выходе.
usage: turn_fixtures.py OUT_DIR N_TURNS [AI]
"""
import json, struct, sys, zlib
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from t03_common import boot_to_round, computer_keys, ROOT  # noqa: E402
from tanks_probe import bg_buffer  # noqa: E402
from unicorn import UC_HOOK_CODE  # noqa: E402

BASE, STRIDE = 0x3EFC, 0x61
FLAGS = {'rebound': (0x8200, 'B'), 'crumble': (0x3EE6, 'h'), 'fall': (0x8866, 'B'), 'xkill': (0x8203, 'B'),
         'sound': (0x81FF, 'B'), 'ball_inv': (0x8201, 'B'), 'trail': (0x8202, 'B'), 'wind': (0x3EDE, 'h'), 'players': (0x3EDC, 'h'), 'shooter': (0x885E, 'B')}


def snap(g, n):
    fl = {k: struct.unpack('<' + f, g.rd(a, struct.calcsize(f)))[0] for k, (a, f) in FLAGS.items()}
    return {'seed': struct.unpack('<I', g.rd(0x3774, 4))[0], 'players': [g.rd(BASE + STRIDE * i, STRIDE).hex() for i in range(1, n + 1)],
            'flags': fl}


def capture(out: Path, n_turns, ai=2, players=5, dos_time=(0x2A3B, 0x4C5D)):
    out.mkdir(parents=True, exist_ok=True)
    g = boot_to_round(dos_time, players=players, players_keys=computer_keys(players, ai))
    a_start = g.ghidra_abs(0x2583) * 16 + 0x2976
    a_end = g.ghidra_abs(0x2583) * 16 + 0x2CEE
    st = {'ev': None, 'skip': None}

    def hk(uc, addr, size, d):
        if st['skip'] == addr:             # продолжение с этого же адреса
            st['skip'] = None
            return
        st['ev'] = 'start' if addr == a_start else 'end'
        st['at'] = addr
        uc.emu_stop()
    g.uc.hook_add(UC_HOOK_CODE, hk, None, a_start, a_start)
    g.uc.hook_add(UC_HOOK_CODE, hk, None, a_end, a_end)
    idx, cur = [], None
    while len(idx) < n_turns:
        st['ev'] = None
        r = g.run(300_000_000)
        if st['ev'] is None:
            continue
        if r == 'exit' or r.startswith('error'):
            break
        if st['ev'] == 'start':
            cur = {'pre': snap(g, players), 'v0': g.vram(), 'bg': bg_buffer(g)}
            st['skip'] = st['at']
        elif st['ev'] == 'end' and cur is not None:
            name = f't{len(idx):02d}'
            post = snap(g, players)
            post['bg'] = None
            (out / f'{name}.bgpost.z').write_bytes(zlib.compress(bg_buffer(g), 9))
            for nm, data in (('pre', cur['v0']), ('bg', cur['bg']), ('post', g.vram())):
                (out / f'{name}.{nm}.z').write_bytes(zlib.compress(data, 9))
            nd = sum(a != b for a, b in zip(cur['v0'], g.vram()))
            idx.append({'name': name, 'pre': cur['pre'], 'post': post, 'ndiff': nd})
            pf = cur['pre']['flags']
            print(name, 'стрелок', pf['shooter'], 'px', nd, 'ветер', pf['wind'], 'стены', pf['rebound'], 'звук', pf['sound'], flush=True)
            cur = None
            st['skip'] = st['at']
    (out / 'index.json').write_text(json.dumps(idx, indent=1))


if __name__ == '__main__':
    capture(Path(sys.argv[1]), int(sys.argv[2]), ai=int(sys.argv[3]) if len(sys.argv) > 3 else 2)
