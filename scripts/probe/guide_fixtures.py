"""Траектории Herb's (1) и Vick's (2): на входе выстрела подменяются тип наведения, цель и ветер."""
import json, struct, sys, zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from t03_common import boot_to_round, run_to, computer_keys  # noqa: E402
from unicorn import UC_HOOK_CODE
from unicorn.x86_const import UC_X86_REG_CS, UC_X86_REG_SS, UC_X86_REG_SP

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'scripts'))
from real48 import real48_to_float  # noqa: E402

BASE, STRIDE = 0x3EFC, 0x61
# тип 1 = Herb's (множество 0180), 2 = Vick's (множество 01a0)
PLAN = [('herb_a', 1), ('vick_a', 2), ('herb_b', 1), ('vick_b', 2)]


def capture(out: Path):
    out.mkdir(parents=True, exist_ok=True)
    g = boot_to_round((0x0D2F, 0x1A44), players=3, players_keys=computer_keys(3, 2))
    seg = g.ghidra_abs(0x2583)
    rec = seg * 16 + 0x0B91
    positions = []

    def on_code(uc, address, size, data):
        if address != rec:
            return
        x = real48_to_float(g.rd(0x4332, 6))
        y = real48_to_float(g.rd(0x4338, 6))
        positions.append([int(x) if x >= 0 else -int(-x), int(y) if y >= 0 else -int(-y)])

    g.uc.hook_add(UC_HOOK_CODE, on_code)
    idx = []
    for name, kind in PLAN:
        positions.clear()
        run_to(g, 0x2583, 0x01C0)
        ss, sp = g.uc.reg_read(UC_X86_REG_SS), g.uc.reg_read(UC_X86_REG_SP)
        # near call: [sp]=ret, дальше аргумент игрока (перед ним push cs в диспетчере — см. пробный дамп)
        stack = struct.unpack('<6H', bytes(g.uc.mem_read(ss * 16 + sp, 12)))
        # пролог ещё не выполнен: игрок — слово, которое диспетчер положил перед call
        player = stack[2]
        off = BASE + STRIDE * player
        alive = [i for i in range(1, 4) if i != player and g.rd(BASE + STRIDE * i + 0x16, 1)[0]]
        target = alive[0]
        g.ww(off + 0x19, kind)
        g.ww(off + 0x1B, target)
        g.ww(0x3EDE, 0)          # ветер
        g.uc.mem_write(g.ds * 16 + 0x81FF, b'\x00')
        g.uc.mem_write(g.ds * 16 + 0x8200, b'\x00')
        raw = g.rd(off, STRIDE)
        x, y = struct.unpack_from('<hh', raw, 0)
        power, ang, fac = struct.unpack_from('<hhh', raw, 0x0E)
        men = struct.unpack_from('<h', raw, 0x14)[0]
        tx, ty = struct.unpack_from('<hh', g.rd(BASE + STRIDE * target, 4))
        v0 = g.vram()
        run_to(g, 0x318E, 0x00E0)
        (out / f'{name}.vram.z').write_bytes(zlib.compress(v0, 9))
        recj = {'name': name, 'kind': kind, 'player': player, 'target': target,
                'x': x, 'y': y, 'power': power, 'angle': ang, 'facing': fac, 'men': men,
                'target_x': tx, 'target_y': ty,
                'wind': 0, 'positions': list(positions)}
        idx.append(recj)
        print(name, 'p', player, '->', target, 'ang', ang, 'pow', power, 'face', fac,
              'steps', len(positions), 'end', positions[-1] if positions else None, flush=True)
    (out / 'index.json').write_text(json.dumps(idx))
    print('bytes', (out / 'index.json').stat().st_size)


if __name__ == '__main__':
    capture(Path(sys.argv[1]))
