"""Эталоны осыпания (2b39:03da -> 1062:027e) и падения танков (2b39:0020) из настоящей игры.

Чтобы под танками были воронки, на входе взрыва 318e:00e0 оружие подменяется на крупное (3/4).
На входе 2b39:03da подменяется Crumble% (DS:3EE6), на входе 2b39:0020 — Inertia Dampener части танков.
usage: crumble_fixtures.py N_EVENTS OUT_DIR
"""
import json, struct, sys, zlib
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from t03_common import boot_to_round, computer_keys, ROOT  # noqa: E402
from tanks_probe import bg_buffer  # noqa: E402
from unicorn import UC_HOOK_CODE  # noqa: E402
from unicorn.x86_const import UC_X86_REG_SS, UC_X86_REG_SP  # noqa: E402

BASE, STRIDE = 0x3EFC, 0x61


def capture(n_events, out: Path, players=4, dos_time=(0x0E44, 0x2B1D)):
    out.mkdir(parents=True, exist_ok=True)
    g = boot_to_round(dos_time, players=players, players_keys=computer_keys(players, 2))
    targets = {g.ghidra_abs(0x318E) * 16 + 0x00E0: 'expl', g.ghidra_abs(0x2B39) * 16 + 0x03DA: 'crumble',
               g.ghidra_abs(0x2B39) * 16 + 0x0020: 'fall'}
    state = {'hit': None, 'skip': None}

    def hk(uc, addr, size, d):
        if state['skip'] == addr:          # продолжаем с этого же адреса — первое срабатывание пропустить
            state['skip'] = None
            return
        state['hit'] = targets[addr]
        state['at'] = addr
        uc.emu_stop()
    for a in targets:
        g.uc.hook_add(UC_HOOK_CODE, hk, None, a, a)
    idx, k, nexpl = [], 0, 0
    while k < n_events:
        state['hit'] = None
        r = g.run(200_000_000)
        if r == 'exit' or r.startswith('error'):
            break
        ev = state['hit']
        if ev is None:
            continue
        ss, sp = g.uc.reg_read(UC_X86_REG_SS), g.uc.reg_read(UC_X86_REG_SP)
        ret_off, ret_seg = struct.unpack('<HH', bytes(g.uc.mem_read(ss * 16 + sp, 4)))
        if ev == 'expl':
            shooter = struct.unpack('<H', bytes(g.uc.mem_read(ss * 16 + sp + 18, 2)))[0]
            g.ww(BASE + STRIDE * shooter + 0x17, [3, 4][nexpl % 2])
            nexpl += 1
            state['skip'] = state['at']
            continue
        if ev == 'crumble':
            g.ww(0x3EE6, [100, 50, 10, 100][k % 4])
        if ev == 'fall':
            for i in range(1, players + 1):
                g.uc.mem_write(g.ds * 16 + BASE + STRIDE * i + 0x49, struct.pack('<i', [0, 0, 5, 0][(k + i) % 4]))
        pre = {'seed': struct.unpack('<I', g.rd(0x3774, 4))[0],
               'players': [g.rd(BASE + STRIDE * i, STRIDE).hex() for i in range(1, players + 1)],
               'percent': g.rw(0x3EE6), 'rebound': g.rd(0x8200, 1)[0]}
        v0, bg = g.vram(), bg_buffer(g)
        from t03_common import run_to
        state['skip'] = state['at']
        run_to(g, g.to_ghidra(ret_seg), ret_off)
        state['skip'] = None
        post = {'seed': struct.unpack('<I', g.rd(0x3774, 4))[0],
                'players': [g.rd(BASE + STRIDE * i, STRIDE).hex() for i in range(1, players + 1)]}
        name = f'{ev}{k:02d}'
        changed = sum(1 for a, b in zip(v0, g.vram()) if a != b)
        (out / f'{name}.pre.z').write_bytes(zlib.compress(v0, 9))
        (out / f'{name}.bg.z').write_bytes(zlib.compress(bg, 9))
        (out / f'{name}.post.z').write_bytes(zlib.compress(g.vram(), 9))
        idx.append({'name': name, 'event': ev, 'pre': pre, 'post': post, 'vram_changed': changed})
        print(name, 'changed px', changed, 'percent', pre['percent'], flush=True)
        k += 1
    (out / 'index.json').write_text(json.dumps(idx, indent=1))


if __name__ == '__main__':
    capture(int(sys.argv[1]), Path(sys.argv[2]))
