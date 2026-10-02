"""Снятие взрывов 318e:00e0 из настоящей игры (ИИ против ИИ): состояние на входе и на выходе."""
import struct, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from t03_common import boot_to_round, run_to, computer_keys, ROOT  # noqa: E402
from tanks_probe import player, bg_buffer  # noqa: E402
sys.path.insert(0, str(ROOT / 'scripts'))
from real48 import real48_to_float  # noqa: E402
from unicorn.x86_const import UC_X86_REG_SS, UC_X86_REG_SP  # noqa: E402

EXPL = (0x318E, 0x00E0)


def snapshot(g, players):
    return {'seed': struct.unpack('<I', g.rd(0x3774, 4))[0], 'vram': g.vram(), 'bg': bg_buffer(g),
            'tanks': [player(g, i) for i in range(1, players + 1)],
            'weapon_of': [g.rd(0x3EFC + 0x61 * i + 0x17, 1)[0] for i in range(1, players + 1)]}


def next_explosion(g, players):
    run_to(g, *EXPL)
    ss, sp = g.uc.reg_read(UC_X86_REG_SS), g.uc.reg_read(UC_X86_REG_SP)
    st = bytes(g.uc.mem_read(ss * 16 + sp, 4 + 16))
    ret_off, ret_seg = struct.unpack('<HH', st[:4])
    hitc, y0, y1, y2, x0, x1, x2, shooter = struct.unpack('<8H', st[4:20])
    x = real48_to_float(struct.pack('<3H', x0, x1, x2))
    y = real48_to_float(struct.pack('<3H', y0, y1, y2))
    pre = snapshot(g, players)
    pre.update({'x': x, 'y': y, 'hit_color': hitc, 'shooter': shooter,
                'args_raw': [hitc, y0, y1, y2, x0, x1, x2, shooter]})
    run_to(g, g.to_ghidra(ret_seg), ret_off)
    post = snapshot(g, players)
    return pre, post


if __name__ == '__main__':
    g = boot_to_round((0x0C1E, 0x0F32), players=2, players_keys=computer_keys(2, 2))
    for k in range(6):
        pre, post = next_explosion(g, 2)
        nd = sum(1 for a, b in zip(pre['vram'], post['vram']) if a != b)
        print(k, f"x={pre['x']:.2f} y={pre['y']:.2f} hit={pre['hit_color']} shooter={pre['shooter']} weapons={pre['weapon_of']}",
              'men', [t['men'] for t in pre['tanks']], '->', [t['men'] for t in post['tanks']], 'vram changed', nd)
        g.save_png(ROOT / 'work' / 'T03' / 'frames' / f'expl_{k}.png')
