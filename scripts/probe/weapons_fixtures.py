"""Эталоны особого оружия из настоящей игры (вход события подменяется, дальше — оригинал).

Взрывные виды (6–10, 12, 13–16, 17) снимаются на входе 318e:00e0, как explosion_fixtures.py.
usage: weapons_fixtures.py OUT_DIR WEAPON [WEAPON ...]
"""
import json, struct, sys, zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from t03_common import boot_to_round, run_to, computer_keys, ROOT  # noqa: E402
from tanks_probe import bg_buffer  # noqa: E402

sys.path.insert(0, str(ROOT / 'scripts'))
from real48 import real48_to_float  # noqa: E402
from unicorn.x86_const import UC_X86_REG_SS, UC_X86_REG_SP  # noqa: E402

BASE, STRIDE = 0x3EFC, 0x61


def players_raw(g, n):
    return [g.rd(BASE + STRIDE * i, STRIDE).hex() for i in range(1, n + 1)]


def capture(weapons, out: Path, players=3, dos_time=(0x0D2F, 0x1A44)):
    """На каждое оружие три события: земля без звука, земля со звуком, прямое попадание со звуком."""
    out.mkdir(parents=True, exist_ok=True)
    g = boot_to_round(dos_time, players=players, players_keys=computer_keys(players, 2))
    idx = []
    modes = [('ground', False), ('sound', True), ('direct', True)]
    k = 0
    for weapon in weapons:
        for mode, sound in modes:
            run_to(g, 0x318E, 0x00E0)
            ss, sp = g.uc.reg_read(UC_X86_REG_SS), g.uc.reg_read(UC_X86_REG_SP)
            st = bytes(g.uc.mem_read(ss * 16 + sp, 20))
            ret_off, ret_seg = struct.unpack('<HH', st[:4])
            hitc, y0, y1, y2, x0, x1, x2, shooter = struct.unpack('<8H', st[4:20])
            g.ww(BASE + STRIDE * shooter + 0x17, weapon)
            g.uc.mem_write(g.ds * 16 + 0x81FF, bytes([1 if sound else 0]))
            if mode == 'direct':
                alive = [i for i in range(1, players + 1) if g.rd(BASE + STRIDE * i + 0x16, 1)[0]]
                victims = [i for i in alive if i != shooter] or alive
                hitc = 19 + victims[k % len(victims)]
                g.uc.mem_write(ss * 16 + sp + 4, struct.pack('<H', hitc))
                for i in alive:
                    g.uc.mem_write(g.ds * 16 + BASE + STRIDE * i + 0x45,
                                   struct.pack('<i', [0, 50, 150, 400][(k + i) % 4]))
            vp = g.rd(0xE3AC, 10).hex()
            pre = {'seed': struct.unpack('<I', g.rd(0x3774, 4))[0], 'players': players_raw(g, players)}
            v0, bg = g.vram(), bg_buffer(g)
            run_to(g, g.to_ghidra(ret_seg), ret_off)
            post = {'seed': struct.unpack('<I', g.rd(0x3774, 4))[0], 'players': players_raw(g, players)}
            v1 = g.vram()
            name = f'w{weapon:02d}_{mode}'
            (out / f'{name}.pre.z').write_bytes(zlib.compress(v0, 9))
            (out / f'{name}.bg.z').write_bytes(zlib.compress(bg, 9))
            (out / f'{name}.post.z').write_bytes(zlib.compress(v1, 9))
            x = real48_to_float(struct.pack('<3H', x0, x1, x2))
            y = real48_to_float(struct.pack('<3H', y0, y1, y2))
            nd = sum(a != b for a, b in zip(v0, v1))
            rec = {'name': name, 'hit_color': hitc, 'shooter': shooter, 'weapon': weapon,
                   'sound': sound, 'mode': mode, 'viewport': vp,
                   'x_raw': struct.pack('<3H', x0, x1, x2).hex(),
                   'y_raw': struct.pack('<3H', y0, y1, y2).hex(),
                   'x': x, 'y': y, 'pre': pre, 'post': post, 'ndiff': nd}
            idx.append(rec)
            print(name, f'x={x:.2f} y={y:.2f} hit={hitc} snd={sound} px={nd} vp={vp} seed {pre["seed"]:08x}->{post["seed"]:08x}',
                  flush=True)
            k += 1
    (out / 'index.json').write_text(json.dumps(idx, indent=1))
    print('wrote', out, 'n=', len(idx), flush=True)


if __name__ == '__main__':
    out = Path(sys.argv[1])
    weapons = [int(a) for a in sys.argv[2:]]
    capture(weapons, out)
