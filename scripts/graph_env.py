#!/usr/bin/env python3
"""Graph environment: relocate VGA256, wire E642, init mode 13h, helpers to call Graph APIs."""
from __future__ import annotations

import sys
from pathlib import Path
from typing import List, Optional

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from emu16 import (  # noqa: E402
    DS_SEG,
    Emu16,
    STACK_SEG,
    STACK_SP,
    VGA_SEG,
    _run_with_ret_detect,
    diff_bbox,
    pascal_string,
)

GRAPH = 0x1827
WRAP = 0x175E


def make_graph_emu() -> Emu16:
    """Return an Emu16 with VGA256 driver relocated and Graph ready for drawing."""
    emu = Emu16(hook_interrupts=True)

    def fcall(off: int, stack_args=None, seg=GRAPH, max_insns=2_000_000):
        emu.set_regs(
            cs=seg, ds=DS_SEG, es=DS_SEG, ss=STACK_SEG, sp=STACK_SP,
            ax=0, bx=0, cx=0, dx=0, si=0, di=0, bp=0, flags=0x0202,
        )
        if stack_args:
            for w in stack_args:
                emu.push16(w)
        emu.push16(0xF000)
        emu.push16(0)
        return emu.run(seg, off, stop_addrs=[(0xF000, 0)], max_insns=max_insns)

    # Graph unit init (GetMem hooks etc.)
    fcall(0x193E)

    # Relocate packed VGA256 at 1062:14F8 via Graph's fixup routine 0569
    emu.set_regs(cs=GRAPH, ds=DS_SEG, es=DS_SEG, ss=STACK_SEG, sp=STACK_SP, flags=0x0202)
    emu.push16(0x1062)
    emu.push16(0x14F8)
    emu.push16(0x1062)
    emu.push16(0x14F8 + 0x80)
    emu.push16(0x1062)
    emu.push16(0x14F8 + 0x80 + 4)
    regs = _run_with_ret_detect(emu, GRAPH, 0x0569, far=False)
    ent_seg, ent_off = regs["dx"], regs["ax"]
    assert emu.read_bytes(ent_seg, ent_off, 2) == b"\x1e\x0e", (
        f"unexpected driver stub at {ent_seg:04x}:{ent_off:04x}"
    )

    emu.write_u16(DS_SEG, 0xE642, ent_off)
    emu.write_u16(DS_SEG, 0xE644, ent_seg)

    # BGI clear/init (SI=2) sets mode 13h via INT10
    emu.set_regs(
        cs=ent_seg, ds=DS_SEG, es=DS_SEG, ss=STACK_SEG, sp=STACK_SP,
        ax=0, bx=0, cx=0, dx=0, si=2, di=0, bp=0, flags=0x0202,
    )
    emu.push16(0xF000)
    emu.push16(0)
    emu.run(ent_seg, ent_off, stop_addrs=[(0xF000, 0)])

    # Graph globals
    emu.write_u16(DS_SEG, 0xE670, 1)  # GraphActive
    emu.write_u16(DS_SEG, 0xE5E4, 319)
    emu.write_u16(DS_SEG, 0xE5E6, 199)
    emu.write_u16(DS_SEG, 0xE666, 0)  # CP X
    emu.write_u16(DS_SEG, 0xE668, 0)  # CP Y
    emu.write_u16(DS_SEG, 0xE660, 15)  # current color
    emu.write_u16(DS_SEG, 0xE63A, 0)  # GraphResult

    emu._fcall = fcall  # type: ignore
    emu._driver = (ent_seg, ent_off)  # type: ignore
    return emu


def gcall(emu: Emu16, off: int, args: Optional[List[int]] = None, seg: int = GRAPH):
    return emu._fcall(off, stack_args=args or [], seg=seg)  # type: ignore


def clear_vram(emu: Emu16):
    emu.write_bytes(VGA_SEG, 0, bytes(64000))


def call_driver(emu: Emu16, si: int, ax=0, bx=0, cx=0, dx=0):
    ent_seg, ent_off = emu._driver  # type: ignore
    emu.set_regs(
        cs=ent_seg, ds=DS_SEG, es=DS_SEG, ss=STACK_SEG, sp=STACK_SP,
        ax=ax, bx=bx, cx=cx, dx=dx, si=si, di=0, bp=0, flags=0x0202,
    )
    emu.push16(0xF000)
    emu.push16(0)
    return emu.run(ent_seg, ent_off, stop_addrs=[(0xF000, 0)])
