"""Эталон расстановки танков: VRAM и буфер фона на 2eef:0dbc, итог на возврате в 2583:255b."""
import json, struct, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from t03_common import boot_to_round, run_to, ROOT  # noqa: E402

PLAYER_BASE, STRIDE = 0x3EFC, 0x61


def player(g, i):
    b = PLAYER_BASE + STRIDE * i
    s16 = lambda v: v - 0x10000 if v >= 0x8000 else v  # noqa: E731
    return {'x': g.rw(b), 'y': g.rw(b + 2), 'power': g.rw(b + 0x0E), 'angle': g.rw(b + 0x10),
            'facing': s16(g.rw(b + 0x12)), 'men': s16(g.rw(b + 0x14)), 'alive': g.rd(b + 0x16, 1)[0]}


def bg_buffer(g) -> bytes:
    seg = g.rw(0xE0B2)
    return bytes(g.uc.mem_read(seg * 16, 64000))


def probe(dos_time, players=2):
    g = boot_to_round(dos_time, players=players)
    run_to(g, 0x2EEF, 0x0A5A)
    seed = struct.unpack('<I', g.rd(0x3774, 4))[0]
    run_to(g, 0x2EEF, 0x0DBC)
    v_terrain, bg = g.vram(), bg_buffer(g)
    run_to(g, 0x2583, 0x255B)
    return {'dos_time': list(dos_time), 'seed': seed, 'players': players,
            'tanks': [player(g, i) for i in range(1, players + 1)],
            'vram_terrain': v_terrain, 'bg': bg, 'vram': g.vram(), 'game': g}
