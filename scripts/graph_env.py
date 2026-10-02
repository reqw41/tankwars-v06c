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
    # Default aspect 1:1 (required by Circle → 11b7 LongDiv)
    emu.write_u16(DS_SEG, 0xE66C, 10000)
    emu.write_u16(DS_SEG, 0xE66E, 10000)

    # VGA256 leaves SI=14 (Arc/Ellipse) as near-ret stub at 0010.
    # Install a CODE hook so Circle/Arc actually rasterize for tests.
    _install_arc_hook(emu, ent_seg)

    emu._fcall = fcall  # type: ignore
    emu._driver = (ent_seg, ent_off)  # type: ignore
    return emu


def _install_arc_hook(emu: Emu16, ent_seg: int) -> None:
    """If driver SI=14 → stub ret@0010, draw ellipse at CP when that stub runs."""
    from unicorn import UC_HOOK_CODE
    from unicorn.x86_const import (
        UC_X86_REG_AX,
        UC_X86_REG_BX,
        UC_X86_REG_CX,
        UC_X86_REG_DX,
        UC_X86_REG_CS,
        UC_X86_REG_IP,
    )

    stub = emu.read_u16(ent_seg, 0x16 + 0x14)
    if stub != 0x10:
        return
    stub_lin = (ent_seg << 4) + 0x10

    def on_stub(uc, address, size, user_data):
        if address != stub_lin:
            return
        # Arc params: AX=stangle, BX=endangle, CX=xradius, DX=yradius; CP at driver:77/79
        cx = uc.reg_read(UC_X86_REG_CX) & 0xFFFF
        dx = uc.reg_read(UC_X86_REG_DX) & 0xFFFF
        ax = uc.reg_read(UC_X86_REG_AX) & 0xFFFF
        bx = uc.reg_read(UC_X86_REG_BX) & 0xFFFF
        # Only full-ish circles (0..360) — enough for GRAPH_Circle / 11ea
        if cx == 0 and dx == 0:
            return
        x0 = emu.read_u16(ent_seg, 0x77)
        y0 = emu.read_u16(ent_seg, 0x79)
        color = emu.read_bytes(ent_seg, 0x73, 1)[0]
        # Midpoint ellipse (full); angles ignored when spanning ≥360
        span = (bx - ax) & 0xFFFF
        if span < 350 and not (ax == 0 and bx >= 360):
            # partial arc: still draw full ellipse for visibility in tests
            pass
        rx, ry = max(cx, 1), max(dx, 1)
        # Bresenham-ish: sample 360 points
        import math as _m

        for deg in range(360):
            rad = _m.radians(deg)
            x = int(x0 + rx * _m.cos(rad) + 0.5)
            y = int(y0 + ry * _m.sin(rad) + 0.5)
            if 0 <= x < 320 and 0 <= y < 200:
                emu.set_pixel(x, y, color)

    emu.uc.hook_add(UC_HOOK_CODE, on_stub, begin=stub_lin, end=stub_lin + 1)


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
