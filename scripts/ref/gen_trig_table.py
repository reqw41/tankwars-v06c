#!/usr/bin/env python3
"""Cos/Sin(DegToRad(a)) для целых a = 0..360, как их считает RTL TP6 (Real48, исполнением в unicorn).

Результат: scripts/ref/data/trig.json — {a: [cos_real48_hex, sin_real48_hex]}. TP6 даёт, например,
Cos(0) = 0.99999999999454 (не 1.0) — поэтому math.cos не годится для побитной модели.
"""
import json, struct, sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
from emu16 import Emu16, call_far  # noqa: E402


def trig(emu, a, fn):
    r = call_far(emu, 0x1C5B, 0x1151, ax=a & 0xFFFF, dx=0xFFFF if a < 0 else 0)
    r = call_far(emu, 0x175E, 0x00DA, stack_args=[r['dx'], r['bx'], r['ax']])
    r = call_far(emu, 0x1C5B, fn, ax=r['ax'], bx=r['bx'], dx=r['dx'])
    return struct.pack('<3H', r['ax'], r['bx'], r['dx']).hex()


if __name__ == '__main__':
    e = Emu16()
    tab = {a: [trig(e, a, 0x1263), trig(e, a, 0x1276)] for a in range(0, 361)}
    (ROOT / 'scripts/ref/data/trig.json').write_text(json.dumps(tab))
    print(tab[0], tab[90])
