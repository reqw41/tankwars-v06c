"""Эталоны взрыва 318e:00e0 из настоящей игры (ИИ Lobber против Lobber).

На входе взрыва можно подменить оружие стрелявшего (+0x17) и флаг звука DS:81FF — это вход функции,
дальше исполняется оригинал. Сохраняются: вход (VRAM, фон, записи игроков, сид, аргументы) и выход.
usage: explosion_fixtures.py N_SHOTS OUT_DIR
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
WEAPON_PLAN = [1, 2, 3, 4, 11, 1, 3, 2, 4, 11, 1, 2, 3, 4, 11, 1]


def players_raw(g, n):
    return [g.rd(BASE + STRIDE * i, STRIDE).hex() for i in range(1, n + 1)]


def capture(n_shots, out: Path, players=3, dos_time=(0x0C1E, 0x0F32), direct=False):
    out.mkdir(parents=True, exist_ok=True)
    g = boot_to_round(dos_time, players=players, players_keys=computer_keys(players, 2))
    idx = []
    for k in range(n_shots):
        run_to(g, 0x318E, 0x00E0)
        ss, sp = g.uc.reg_read(UC_X86_REG_SS), g.uc.reg_read(UC_X86_REG_SP)
        st = bytes(g.uc.mem_read(ss * 16 + sp, 20))
        ret_off, ret_seg = struct.unpack('<HH', st[:4])
        hitc, y0, y1, y2, x0, x1, x2, shooter = struct.unpack('<8H', st[4:20])
        weapon = WEAPON_PLAN[k % len(WEAPON_PLAN)]
        sound = k % 3 == 0
        g.ww(BASE + STRIDE * shooter + 0x17, weapon)
        g.uc.mem_write(g.ds * 16 + 0x81FF, bytes([1 if sound else 0]))
        if direct:
            # прямое попадание в другой живой танк + щиты (вход функции, дальше исполняется оригинал)
            alive = [i for i in range(1, players + 1) if g.rd(BASE + STRIDE * i + 0x16, 1)[0]]
            victims = [i for i in alive if i != shooter] or alive
            victim = victims[k % len(victims)]
            hitc = 19 + victim
            g.uc.mem_write(ss * 16 + sp + 4, struct.pack('<H', hitc))
            for i in alive:
                g.uc.mem_write(g.ds * 16 + BASE + STRIDE * i + 0x45, struct.pack('<i', [0, 50, 150, 400][(k + i) % 4]))
        pre = {'seed': struct.unpack('<I', g.rd(0x3774, 4))[0], 'players': players_raw(g, players)}
        v0, bg = g.vram(), bg_buffer(g)
        run_to(g, g.to_ghidra(ret_seg), ret_off)
        post = {'seed': struct.unpack('<I', g.rd(0x3774, 4))[0], 'players': players_raw(g, players)}
        name = f'e{k:02d}'
        (out / f'{name}.pre.z').write_bytes(zlib.compress(v0, 9))
        (out / f'{name}.bg.z').write_bytes(zlib.compress(bg, 9))
        (out / f'{name}.post.z').write_bytes(zlib.compress(g.vram(), 9))
        rec = {'name': name, 'hit_color': hitc, 'shooter': shooter, 'weapon': weapon, 'sound': sound,
               'x_raw': struct.pack('<3H', x0, x1, x2).hex(), 'y_raw': struct.pack('<3H', y0, y1, y2).hex(),
               'x': real48_to_float(struct.pack('<3H', x0, x1, x2)), 'y': real48_to_float(struct.pack('<3H', y0, y1, y2)),
               'pre': pre, 'post': post}
        idx.append(rec)
        print(name, f"x={rec['x']:.2f} y={rec['y']:.2f} hit={hitc} w={weapon} snd={sound}")
    (out / 'index.json').write_text(json.dumps(idx, indent=1))


if __name__ == '__main__':
    capture(int(sys.argv[1]), Path(sys.argv[2]), players=int(sys.argv[3]) if len(sys.argv) > 3 else 3,
            dos_time=(0x0D2F, 0x1A44), direct=len(sys.argv) > 4 and sys.argv[4] == 'direct')
