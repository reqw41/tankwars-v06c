"""Эталоны лазера 2583:140f. На входе хода подменяются оружие, энергия, мощность и звук."""
import json, struct, sys, zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from t03_common import boot_to_round, run_to, computer_keys, ROOT  # noqa: E402
from tanks_probe import bg_buffer  # noqa: E402
from unicorn.x86_const import UC_X86_REG_SS, UC_X86_REG_BP  # noqa: E402

BASE, STRIDE = 0x3EFC, 0x61
# (name, power, energy, sound)
PLAN = [
    ('ground', 80, 1000, False),
    ('sound', 120, 1000, True),
    ('clamp', 400, 150, True),
    ('direct', 200, 1000, False),
]


def players_raw(g, n=3):
    return [g.rd(BASE + STRIDE * i, STRIDE).hex() for i in range(1, n + 1)]


def capture(out: Path):
    out.mkdir(parents=True, exist_ok=True)
    g = boot_to_round((0x0D2F, 0x1A44), players=3, players_keys=computer_keys(3, 2))
    idx = []
    for name, power, energy, sound in PLAN:
        run_to(g, 0x2583, 0x2976)
        ss, bp = g.uc.reg_read(UC_X86_REG_SS), g.uc.reg_read(UC_X86_REG_BP)
        player = struct.unpack('<H', bytes(g.uc.mem_read(ss * 16 + bp - 2, 2)))[0]
        off = BASE + STRIDE * player
        g.uc.mem_write(g.ds * 16 + off + 0x17, bytes([5]))
        g.ww(off + 0x0E, power)
        g.ww(off + 0x2B, energy)
        g.uc.mem_write(g.ds * 16 + 0x81FF, bytes([1 if sound else 0]))
        if name == 'direct':
            # навести на другого живого: угол 0..90 и facing к его x
            sx, sy = struct.unpack('<hh', g.rd(off, 4))
            alive = [i for i in range(1, 4) if i != player and g.rd(BASE + STRIDE * i + 0x16, 1)[0]]
            vic = alive[0]
            vx, vy = struct.unpack('<hh', g.rd(BASE + STRIDE * vic, 4))
            facing = 1 if vx >= sx else -1
            g.ww(off + 0x12, facing & 0xFFFF)
            dx, dy = abs(vx - sx), max(0, sy - vy)
            ang = 45 if dx == 0 else max(0, min(90, int(round(__import__('math').degrees(__import__('math').atan2(dy, dx))))))
            g.ww(off + 0x10, ang)
        run_to(g, 0x2583, 0x140F)
        pre = {'seed': struct.unpack('<I', g.rd(0x3774, 4))[0], 'players': players_raw(g)}
        v0, bg = g.vram(), bg_buffer(g)
        run_to(g, 0x2583, 0x29AE)
        post = {'seed': struct.unpack('<I', g.rd(0x3774, 4))[0], 'players': players_raw(g)}
        v1 = g.vram()
        (out / f'{name}.pre.z').write_bytes(zlib.compress(v0, 9))
        (out / f'{name}.bg.z').write_bytes(zlib.compress(bg, 9))
        (out / f'{name}.post.z').write_bytes(zlib.compress(v1, 9))
        nd = sum(a != b for a, b in zip(v0, v1))
        rec = {'name': name, 'player': player, 'power': power, 'energy': energy, 'sound': sound,
               'pre': pre, 'post': post, 'ndiff': nd}
        idx.append(rec)
        print(name, 'player', player, 'px', nd, f'seed {pre["seed"]:08x}->{post["seed"]:08x}', flush=True)
    (out / 'index.json').write_text(json.dumps(idx, indent=1))


if __name__ == '__main__':
    capture(Path(sys.argv[1]))
