#!/usr/bin/env python3
"""T01b addendum1: Circle / SetTextStyle / SetUserCharSize / IntToStr effect probes."""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

from emu16 import DS_SEG, diff_bbox, pascal_string  # noqa: E402
from graph_env import WRAP, clear_vram, gcall, make_graph_emu  # noqa: E402


def main():
    emu = make_graph_emu()
    clear_vram(emu)
    gcall(emu, 0x1DC2, [14])
    gcall(emu, 0x11EA, [100, 80, 15])
    bb = diff_bbox(bytes(64000), emu.vram())
    print(f"Circle(100,80,15) bbox={bb} right={emu.pixel(115,80)} SI14stub={emu.read_u16(emu._driver[0],0x16+0x14):04x}")

    emu = make_graph_emu()
    n = len(emu.int_log)
    gcall(emu, 0x1496, [0, 0, 1])
    print(
        f"SetTextStyle(font0,dir0,size1) E6AE={emu.read_u16(DS_SEG,0xE6AE)} "
        f"E6B0={emu.read_u16(DS_SEG,0xE6B0)} E6B2={emu.read_u16(DS_SEG,0xE6B2)} "
        f"INT21={sum(1 for x in emu.int_log[n:] if x.startswith('INT21'))}"
    )

    emu = make_graph_emu()
    emu.write_bytes(DS_SEG, 0x4000, pascal_string("Hello"))
    w0 = gcall(emu, 0x1F9B, [DS_SEG, 0x4000])["ax"]
    gcall(emu, 0x16E3, [8, 16, 8, 16])
    w1 = gcall(emu, 0x1F9B, [DS_SEG, 0x4000])["ax"]
    print(f"SetUserCharSize→TextWidth {w0}→{w1} E6B2={emu.read_u16(DS_SEG,0xE6B2)}")

    emu = make_graph_emu()
    buf = 0x4400
    emu.write_bytes(DS_SEG, buf, bytes(32))
    gcall(emu, 0x0293, [DS_SEG, buf, 0, 12345], seg=WRAP)
    s = emu.read_bytes(DS_SEG, buf, 16)
    print(f"IntToStr(12345)={s[1:1+s[0]]!r}")
    emu.write_bytes(DS_SEG, buf, bytes(32))
    gcall(emu, 0x0293, [DS_SEG, buf, 0xFFFF, (-7) & 0xFFFF], seg=WRAP)
    s = emu.read_bytes(DS_SEG, buf, 16)
    print(f"IntToStr(-7)={s[1:1+s[0]]!r}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
