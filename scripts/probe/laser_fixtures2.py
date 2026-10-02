"""Эталоны лазера с попаданием в землю и в танки (дополняет laser_fixtures.py, где луч уходил в небо).

На входе хода (2583:2976) подменяются оружие 5, энергия, мощность, звук, отражающие стены, угол/направление.
Угол выбирается перебором: прямая луча по текущему экрану должна первой встретить нужную цель.
usage: laser_fixtures2.py OUT_DIR
"""
import json, math, struct, sys, zlib
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from t03_common import boot_to_round, run_to, computer_keys, ROOT  # noqa: E402
from tanks_probe import bg_buffer  # noqa: E402
from unicorn.x86_const import UC_X86_REG_SS, UC_X86_REG_BP  # noqa: E402

BASE, STRIDE = 0x3EFC, 0x61
# (имя, цель 'ground'|'tank', power, sound, rebound, щит жертвы)
PLAN = [
    ('g_p60', 'ground', 60, False, 0, 0),
    ('g_p150_snd', 'ground', 150, True, 0, 0),
    ('g_p300_reb', 'ground', 300, False, 1, 0),
    ('t_noshield', 'tank', 120, False, 0, 0),
    ('t_noshield_snd', 'tank', 100, True, 0, 0),
    ('t_shield', 'tank', 150, False, 0, 40),
    ('t_shield_over', 'tank', 200, True, 0, 9),
    ('g_p500_reb_snd', 'ground', 500, True, 1, 0),
]


def first_hit(vram, x, y, ang, facing):
    a = math.radians(ang)
    e = a if facing > 0 else math.pi - a
    X, Y = x + 7 * math.cos(a) * facing, y - 7 * math.sin(a)
    dx, dy = math.cos(e), -math.sin(e)
    for _ in range(400):
        X += dx; Y += dy
        ix, iy = int(X), int(Y)
        if not (11 < X < 309 and 31 < Y < 189):
            return None
        c = vram[iy * 320 + ix]
        if c == 2 or 20 <= c <= 29:
            return c
    return None


def capture(out: Path, dos_time=(0x2468, 0x0ACE), players=3):
    out.mkdir(parents=True, exist_ok=True)
    g = boot_to_round(dos_time, players=players, players_keys=computer_keys(players, 2))
    idx = []
    for name, want, power, sound, rebound, shield in PLAN:
        for _attempt in range(12):
            run_to(g, 0x2583, 0x2976)
            ss, bp = g.uc.reg_read(UC_X86_REG_SS), g.uc.reg_read(UC_X86_REG_BP)
            player = struct.unpack('<H', bytes(g.uc.mem_read(ss * 16 + bp - 2, 2)))[0]
            off = BASE + STRIDE * player
            sx, sy = struct.unpack('<hh', g.rd(off, 4))
            v = g.vram()
            choice = None
            for facing in (1, -1):
                for ang in range(0, 91):
                    c = first_hit(v, sx, sy, ang, facing)
                    if c is None:
                        continue
                    if want == 'ground' and c == 2:
                        choice = (ang, facing, c); break
                    if want == 'tank' and 20 <= c <= 29 and c != 19 + player:
                        vic = c - 19
                        if struct.unpack('<h', g.rd(BASE + STRIDE * vic + 0x14, 2))[0] > 0:
                            choice = (ang, facing, c); break
                if choice:
                    break
            if choice:
                break
            g.run(1)
        if not choice:
            print(name, 'нет подходящего угла', flush=True)
            continue
        ang, facing, c = choice
        g.uc.mem_write(g.ds * 16 + off + 0x17, bytes([5]))
        g.ww(off + 0x0E, power); g.ww(off + 0x2B, 2000)
        g.ww(off + 0x10, ang); g.ww(off + 0x12, facing & 0xFFFF)
        g.uc.mem_write(g.ds * 16 + 0x81FF, bytes([1 if sound else 0]))
        g.uc.mem_write(g.ds * 16 + 0x8200, bytes([rebound]))
        if want == 'tank':
            g.uc.mem_write(g.ds * 16 + BASE + STRIDE * (c - 19) + 0x45, struct.pack('<i', shield))
        run_to(g, 0x2583, 0x140F)
        pre = {'seed': struct.unpack('<I', g.rd(0x3774, 4))[0],
               'players': [g.rd(BASE + STRIDE * i, STRIDE).hex() for i in range(1, players + 1)]}
        v0, bg = g.vram(), bg_buffer(g)
        run_to(g, 0x2583, 0x29AE)
        post = {'seed': struct.unpack('<I', g.rd(0x3774, 4))[0],
                'players': [g.rd(BASE + STRIDE * i, STRIDE).hex() for i in range(1, players + 1)]}
        v1 = g.vram()
        for nm, data in (('pre', v0), ('bg', bg), ('post', v1)):
            (out / f'{name}.{nm}.z').write_bytes(zlib.compress(data, 9))
        nd = sum(a != b for a, b in zip(v0, v1))
        idx.append({'name': name, 'player': player, 'power': power, 'sound': sound, 'rebound': bool(rebound),
                    'target': want, 'target_color': c, 'angle': ang, 'facing': facing, 'shield': shield,
                    'pre': pre, 'post': post, 'ndiff': nd})
        print(name, 'player', player, 'ang', ang, 'f', facing, 'target', c, 'px', nd, flush=True)
    (out / 'index.json').write_text(json.dumps(idx, indent=1))


if __name__ == '__main__':
    capture(Path(sys.argv[1]))
