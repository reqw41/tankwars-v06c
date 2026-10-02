"""Circle (1827:11ea) в настоящей игре: после настоящего InitGraph, внутри взрыва CRI (оружие 6).

Вывод: список (x, y, r) и множества изменённых пикселей между входом в 11ea и его RETF (1827:1209).
"""
import json, struct, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from t03_common import boot_to_round, run_to, computer_keys, ROOT  # noqa: E402
from unicorn import UC_HOOK_CODE  # noqa: E402
from unicorn.x86_const import UC_X86_REG_SS, UC_X86_REG_SP  # noqa: E402


def probe(max_calls=6):
    g = boot_to_round((0x0C1E, 0x0F32), players=2, players_keys=computer_keys(2, 2))
    run_to(g, 0x318E, 0x00E0)
    ss, sp = g.uc.reg_read(UC_X86_REG_SS), g.uc.reg_read(UC_X86_REG_SP)
    shooter = struct.unpack('<H', bytes(g.uc.mem_read(ss * 16 + sp + 18, 2)))[0]
    g.ww(0x3EFC + 0x61 * shooter + 0x17, 6)
    calls, st = [], {}
    ent = g.ghidra_abs(0x1827) * 16 + 0x11EA
    ret = g.ghidra_abs(0x1827) * 16 + 0x1209

    def h_in(uc, a, s, d):
        sp_, ss_ = uc.reg_read(UC_X86_REG_SP), uc.reg_read(UC_X86_REG_SS)
        st['args'] = struct.unpack('<3H', bytes(uc.mem_read(ss_ * 16 + sp_ + 4, 6)))[::-1]
        st['v'] = g.vram()

    def h_out(uc, a, s, d):
        v = g.vram()
        calls.append({'args': list(st['args']), 'pixels': [[k % 320, k // 320] for k in range(64000) if v[k] != st['v'][k]]})
    g.uc.hook_add(UC_HOOK_CODE, h_in, None, ent, ent)
    g.uc.hook_add(UC_HOOK_CODE, h_out, None, ret, ret)
    for _ in range(20):
        if g.run(100_000_000) != 'limit' or len(calls) >= max_calls:
            break
    return calls


if __name__ == '__main__':
    calls = probe()
    out = ROOT / 'tests' / 'fixtures' / 't03' / 'circle_real.json'
    out.write_text(json.dumps(calls))
    print([(c['args'], len(c['pixels'])) for c in calls])
