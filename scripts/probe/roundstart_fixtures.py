"""Эталоны начала раунда: вход 2eef:0909 (сид, настройки) -> вход в цикл ходов 2583:2783 (экран, фон, игроки, ветер)."""
import json, struct, sys, zlib
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from t03_common import boot_to_round, run_to, computer_keys, ROOT  # noqa: E402
from tanks_probe import bg_buffer  # noqa: E402
from unicorn.x86_const import UC_X86_REG_SS, UC_X86_REG_BP  # noqa: E402

BASE, STRIDE = 0x3EFC, 0x61
CFG = {'walls_cfg': (0x820C, 'h'), 'bg_cfg': (0x8860, 'h'), 'wind_mode': (0x81F6, 'h'), 'players': (0x3EDC, 'h'),
       'ball_inv': (0x8201, 'B')}


def capture(out: Path, n_rounds, players=4, dos_time=(0x0BAD, 0x0C0D), ai=2, bg_plan=None):
    out.mkdir(parents=True, exist_ok=True)
    g = boot_to_round(dos_time, players=players, players_keys=computer_keys(players, ai))
    idx = []
    for k in range(n_rounds):
        try:
            run_to(g, 0x2EEF, 0x0909)
        except RuntimeError as e:
            print('конец сета:', e)
            break
        if bg_plan is not None:
            g.ww(0x8860, bg_plan[k % len(bg_plan)])      # вход: вариант фона
            g.ww(0x820C, [0, 1, 2][k % 3])                # вход: настройка стен
            g.ww(0x81F6, k % 6)                           # вход: режим ветра
        pre = {'seed': struct.unpack('<I', g.rd(0x3774, 4))[0],
               'cfg': {n: struct.unpack('<' + f, g.rd(a, struct.calcsize(f)))[0] for n, (a, f) in CFG.items()},
               'players': [g.rd(BASE + STRIDE * i, STRIDE).hex() for i in range(1, players + 1)]}
        run_to(g, 0x2583, 0x2783)
        ss, bp = g.uc.reg_read(UC_X86_REG_SS), g.uc.reg_read(UC_X86_REG_BP)
        first_raw = struct.unpack('<H', bytes(g.uc.mem_read(ss * 16 + bp - 2, 2)))[0]
        post = {'seed': struct.unpack('<I', g.rd(0x3774, 4))[0], 'wind': struct.unpack('<h', g.rd(0x3EDE, 2))[0],
                'rebound': g.rd(0x8200, 1)[0], 'first_raw': first_raw,
                'players': [g.rd(BASE + STRIDE * i, STRIDE).hex() for i in range(1, players + 1)]}
        name = f'r{k:02d}'
        (out / f'{name}.post.z').write_bytes(zlib.compress(g.vram(), 9))
        (out / f'{name}.bg.z').write_bytes(zlib.compress(bg_buffer(g), 9))
        idx.append({'name': name, 'pre': pre, 'post': post})
        print(name, pre['cfg'], 'ветер', post['wind'], 'стены', post['rebound'], 'первый(raw)', first_raw, flush=True)
        # дать раунду закончиться: убить всех, кроме одного, через здоровье на входе проверки смертей
        for i in range(2, players + 1):
            g.ww(BASE + STRIDE * i + 0x14, (-1) & 0xFFFF)
    (out / 'index.json').write_text(json.dumps(idx, indent=1))


if __name__ == '__main__':
    capture(Path(sys.argv[1]), int(sys.argv[2]), bg_plan=[0, 1, 2, 3, 4, 5, 6])
