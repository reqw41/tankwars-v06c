"""Эталоны ИИ (2cab:000d через стаб 1049:0020): планирование и последовательность «нажатий» за ход.

На каждом ходе компьютера: снимок на первом вызове ИИ (экран, фон, записи игроков, структура истории игрока
0x8896+0x802*p, флаги, RandSeed), затем коды возврата всех вызовов ИИ за ход и состояние на 2583:2976
(после хода: угол/мощность/оружие и RandSeed). Тип ИИ задаётся именем игрока (вход): 'Birdy Bonker' — скрытый тип 2.
usage: ai_fixtures.py OUT_DIR N_TURNS AI_MENU_INDEX [NAME_OVERRIDE]
"""
import os
import json, struct, sys, zlib
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from t03_common import boot_to_round, computer_keys, ROOT  # noqa: E402
from tanks_probe import bg_buffer  # noqa: E402
from unicorn import UC_HOOK_CODE  # noqa: E402
from unicorn.x86_const import UC_X86_REG_SS, UC_X86_REG_SP, UC_X86_REG_AX  # noqa: E402

REC, ST = 0x3EEE, 0x61
HIST, HST = 0x8896, 0x802
FLAGS = {'rebound': (0x8200, 'B'), 'wind': (0x3EDE, 'h'), 'players': (0x3EDC, 'h')}


def capture(out: Path, n_turns, ai=2, name=None, players=4, dos_time=(0x4A11, 0x0B0B)):
    out.mkdir(parents=True, exist_ok=True)
    g = boot_to_round(dos_time, players=players, players_keys=computer_keys(players, ai))
    a_ai = g.ghidra_abs(0x2CAB) * 16 + 0x000D
    a_end = g.ghidra_abs(0x2583) * 16 + 0x2976
    st = {'ev': None, 'skip': None}

    def hk(uc, addr, size, d):
        if st['skip'] == addr:
            st['skip'] = None
            return
        st['ev'] = 'ai' if addr == a_ai else 'end'
        st['at'] = addr
        uc.emu_stop()
    g.uc.hook_add(UC_HOOK_CODE, hk, None, a_ai, a_ai)
    g.uc.hook_add(UC_HOOK_CODE, hk, None, a_end, a_end)
    idx, cur = [], None
    while len(idx) < n_turns:
        st['ev'] = None
        r = g.run(300_000_000)
        if r == 'exit' or r.startswith('error'):
            break
        if st['ev'] == 'ai':
            ss, sp = g.uc.reg_read(UC_X86_REG_SS), g.uc.reg_read(UC_X86_REG_SP)
            ret_off, ret_seg = struct.unpack('<HH', bytes(g.uc.mem_read(ss * 16 + sp, 4)))
            p = struct.unpack('<H', bytes(g.uc.mem_read(ss * 16 + sp + 4, 2)))[0]
            hp = HIST + HST * p
            if os.environ.get('TW_REBOUND'):          # принудительно включить отражающие стены
                g.uc.mem_write(g.ds * 16 + 0x8200, b'\x01')
            if name is not None and cur is None:
                nb = name.encode()
                g.uc.mem_write(g.ds * 16 + REC + ST * p, bytes([len(nb)]) + nb)
            if cur is None:
                cur = {'player': p, 'seed0': struct.unpack('<I', g.rd(0x3774, 4))[0],
                       'flags': {k: struct.unpack('<' + f, g.rd(a, struct.calcsize(f)))[0] for k, (a, f) in FLAGS.items()},
                       'recs': [g.rd(REC + ST * i, ST).hex() for i in range(0, players + 1)],
                       'hist': g.rd(hp, HST).hex(), 'v0': g.vram(), 'bg': bg_buffer(g), 'codes': [], 'seeds': []}
            # выполнить вызов ИИ до возврата
            st['skip'] = st['at']
            from t03_common import run_to
            run_to(g, g.to_ghidra(ret_seg), ret_off)
            cur['codes'].append(g.uc.reg_read(UC_X86_REG_AX))
            cur['seeds'].append(struct.unpack('<I', g.rd(0x3774, 4))[0])
            if len(cur['codes']) == 1:
                cur['hist1'] = g.rd(hp, HST).hex()
                cur['v1'] = g.vram()
        elif st['ev'] == 'end':
            if cur is not None:
                p = cur['player']
                name_ = f't{len(idx):02d}'
                (out / f'{name_}.v0.z').write_bytes(zlib.compress(cur['v0'], 9))
                (out / f'{name_}.v1.z').write_bytes(zlib.compress(cur['v1'], 9))
                (out / f'{name_}.bg.z').write_bytes(zlib.compress(cur['bg'], 9))
                rec_end = g.rd(REC + ST * p, ST).hex()
                idx.append({'name': name_, 'player': p, 'seed0': cur['seed0'], 'flags': cur['flags'], 'recs': cur['recs'],
                            'hist': cur['hist'], 'hist1': cur['hist1'], 'codes': cur['codes'], 'seeds': cur['seeds'],
                            'rec_end': rec_end, 'seed_end': struct.unpack('<I', g.rd(0x3774, 4))[0]})
                print(name_, 'игрок', p, 'вызовов', len(cur['codes']), 'коды', cur['codes'][:12], flush=True)
                cur = None
            st['skip'] = st['at']
    (out / 'index.json').write_text(json.dumps(idx, indent=1))


if __name__ == '__main__':
    capture(Path(sys.argv[1]), int(sys.argv[2]), ai=int(sys.argv[3]), name=sys.argv[4] if len(sys.argv) > 4 else None)
