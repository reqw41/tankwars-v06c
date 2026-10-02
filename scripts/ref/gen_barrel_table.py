#!/usr/bin/env python3
"""Таблица смещений ствола (1062:059f): dx = Trunc(Cos(DegToRad(a))*8), dy = Trunc(Sin(DegToRad(a))*8).

Считается исполнением оригинальных RTL-функций (175e:00da DegToRad, 1c5b:1263 Cos, 1276 Sin, 113d Mul, 1155 Trunc)
в unicorn, чтобы совпасть с Real48 до бита. Результат: scripts/ref/data/barrel.json, углы 0..360.
"""
import json, sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
from emu16 import Emu16, call_far  # noqa: E402


def trunc_trig(emu, angle, fn):
    r = call_far(emu, 0x1C5B, 0x1151, ax=angle & 0xFFFF, dx=0xFFFF if angle < 0 else 0)  # LongToReal
    r = call_far(emu, 0x175E, 0x00DA, stack_args=[r['dx'], r['bx'], r['ax']])          # DegToRad
    r = call_far(emu, 0x1C5B, fn, ax=r['ax'], bx=r['bx'], dx=r['dx'])                  # Cos/Sin
    r = call_far(emu, 0x1C5B, 0x113D, ax=r['ax'], bx=r['bx'], dx=r['dx'], cx=0x84, si=0, di=0)  # *8.0
    r = call_far(emu, 0x1C5B, 0x1155, ax=r['ax'], bx=r['bx'], dx=r['dx'])              # Trunc
    v = (r['dx'] << 16) | r['ax']
    return v - (1 << 32) if v >= 1 << 31 else v


if __name__ == '__main__':
    e = Emu16()
    tab = {a: [trunc_trig(e, a, 0x1263), trunc_trig(e, a, 0x1276)] for a in range(0, 361)}
    out = ROOT / 'scripts' / 'ref' / 'data' / 'barrel.json'
    out.write_text(json.dumps(tab))
    print({a: tab[a] for a in (0, 1, 30, 45, 60, 75, 89, 90, 91, 180)})
