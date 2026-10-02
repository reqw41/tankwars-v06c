"""Эталон генерации рельефа: сид и число игроков на входе 2eef:0a5a, VRAM на выходе цикла 2eef:0dbc."""
import json, struct, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from t03_common import boot_to_round, run_to, ROOT  # noqa: E402

TERRAIN_SEG = 0x2EEF


def probe(dos_time, players=2):
    g = boot_to_round(dos_time, players=players)
    run_to(g, TERRAIN_SEG, 0x0A5A)
    seed = struct.unpack('<I', g.rd(0x3774, 4))[0]
    players = g.rw(0x3EDC)
    before = g.vram()
    run_to(g, TERRAIN_SEG, 0x0DBC)
    after = g.vram()
    return {'dos_time': list(dos_time), 'seed': seed, 'players': players,
            'h_final': g.rw(0x3EAA), 'before': before, 'after': after, 'game': g}


if __name__ == '__main__':
    out = ROOT / 'work' / 'T03' / (sys.argv[2] if len(sys.argv) > 2 else 'terrain')
    out.mkdir(parents=True, exist_ok=True)
    for i in range(int(sys.argv[1]) if len(sys.argv) > 1 else 1):
        t = (0x0C1E + i * 0x0107, (0x0F32 + i * 0x1311) & 0xFFFF)
        p = probe(t, players=2 + i % 5)
        name = f'seed_{p["seed"]:08x}'
        (out / f'{name}.bin').write_bytes(p['after'])
        (out / f'{name}.json').write_text(json.dumps({k: p[k] for k in ('dos_time', 'seed', 'players', 'h_final')}))
        p['game'].save_png(out / f'{name}.png')
        print(name, p['players'], p['h_final'])
