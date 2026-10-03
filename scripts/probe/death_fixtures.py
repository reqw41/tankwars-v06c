"""Эталоны анимаций гибели танка (оверлей 285c, выбор Random(7) в 2583:2bb9).

Входы, которые подменяются: здоровье одного живого танка в начале проверки смертей (2583:2b04) и номер
варианта в DS:3EAE сразу после Random(7) (2583:2bc5). Сама анимация — оригинал.
usage: death_fixtures.py OUT_DIR N_PER_VARIANT
"""
import json, struct, sys, zlib
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from t03_common import boot_to_round, run_to, computer_keys, ROOT  # noqa: E402
from tanks_probe import bg_buffer  # noqa: E402
from unicorn.x86_const import UC_X86_REG_SS, UC_X86_REG_SP  # noqa: E402

BASE, STRIDE = 0x3EFC, 0x61
ENTRY = {0: 0x0020, 1: 0x0F61, 2: 0x1DA5, 3: 0x0F61, 4: 0x28D9, 5: 0x2B76, 6: 0x2C29}


def recs(g, n):
    return [g.rd(BASE + STRIDE * i, STRIDE).hex() for i in range(1, n + 1)]


def capture(out: Path, per=3, players=6, dos_time=(0x3141, 0x5926)):
    out.mkdir(parents=True, exist_ok=True)
    plan = [v for v in range(7) for _ in range(per)]
    idx, k, rounds = [], 0, 0
    g = boot_to_round(dos_time, players=players, players_keys=computer_keys(players, 2))
    while k < len(plan):
        try:
            run_to(g, 0x2583, 0x2B04, budget=3_000_000_000)
        except RuntimeError as e:
            print('стоп:', e); break
        alive = [i for i in range(1, players + 1) if g.rd(BASE + STRIDE * i + 0x16, 1)[0]
                 and struct.unpack('<h', g.rd(BASE + STRIDE * i + 0x14, 2))[0] > 0]
        if len(alive) < 2:
            continue
        shooter = g.rd(0x885E, 1)[0]
        victims = [i for i in alive if i != shooter] or alive
        vic = victims[k % len(victims)]
        g.ww(BASE + STRIDE * vic + 0x14, (-10) & 0xFFFF)
        run_to(g, 0x2583, 0x2BC5)
        variant = plan[k]
        g.ww(0x3EAE, variant)
        run_to(g, 0x285C, ENTRY[variant])
        ss, sp = g.uc.reg_read(UC_X86_REG_SS), g.uc.reg_read(UC_X86_REG_SP)
        ret_off, ret_seg = struct.unpack('<HH', bytes(g.uc.mem_read(ss * 16 + sp, 4)))
        args = list(struct.unpack('<4H', bytes(g.uc.mem_read(ss * 16 + sp + 4, 8))))
        pre = {'seed': struct.unpack('<I', g.rd(0x3774, 4))[0], 'players': recs(g, players)}
        v0, bg = g.vram(), bg_buffer(g)
        g.uc.mem_write(g.ds * 16 + 0x81FF, bytes([1 if k % 2 == 0 else 0]))   # звук через раз (вход)
        g.uc.mem_write(g.ds * 16 + 0x8203, bytes([0 if k % 4 == 3 else 1]))   # Explotions Kill (вход)
        sound = g.rd(0x81FF, 1)[0]
        wind = struct.unpack('<h', g.rd(0x3EDE, 2))[0]
        xkill = g.rd(0x8203, 1)[0]
        run_to(g, g.to_ghidra(ret_seg), ret_off)
        post = {'seed': struct.unpack('<I', g.rd(0x3774, 4))[0], 'players': recs(g, players)}
        v1 = g.vram()
        name = f'd{variant}_{k:02d}'
        for nm, data in (('pre', v0), ('bg', bg), ('post', v1)):
            (out / f'{name}.{nm}.z').write_bytes(zlib.compress(data, 9))
        nd = sum(a != b for a, b in zip(v0, v1))
        idx.append({'name': name, 'variant': variant, 'victim': vic, 'shooter': shooter, 'args': args,
                    'sound': sound, 'wind': wind, 'xkill': xkill, 'rebound': g.rd(0x8200, 1)[0], 'pre': pre, 'post': post, 'ndiff': nd})
        print(name, 'жертва', vic, 'стрелок', shooter, 'аргументы', args[:2], 'px', nd, 'звук', sound, 'ветер', wind, 'xkill', xkill, flush=True)
        k += 1
    (out / 'index.json').write_text(json.dumps(idx, indent=1))


if __name__ == '__main__':
    capture(Path(sys.argv[1]), per=int(sys.argv[2]) if len(sys.argv) > 2 else 3)
