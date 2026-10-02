"""16-bit real-mode Unicorn harness for bomb25_flat.exe (Ghidra load base 0x1000)."""
from __future__ import annotations

import struct
from pathlib import Path
from typing import Callable, Dict, Iterable, Optional, Tuple

from unicorn import Uc, UcError, UC_ARCH_X86, UC_MODE_16
from unicorn.x86_const import (
    UC_X86_REG_AH,
    UC_X86_REG_AL,
    UC_X86_REG_AX,
    UC_X86_REG_BH,
    UC_X86_REG_BL,
    UC_X86_REG_BP,
    UC_X86_REG_BX,
    UC_X86_REG_CH,
    UC_X86_REG_CL,
    UC_X86_REG_CS,
    UC_X86_REG_CX,
    UC_X86_REG_DH,
    UC_X86_REG_DL,
    UC_X86_REG_DI,
    UC_X86_REG_DS,
    UC_X86_REG_DX,
    UC_X86_REG_ES,
    UC_X86_REG_FLAGS,
    UC_X86_REG_IP,
    UC_X86_REG_SI,
    UC_X86_REG_SP,
    UC_X86_REG_SS,
)

ROOT = Path(__file__).resolve().parents[1]
FLAT = ROOT / "re" / "bomb25_flat.exe"
LOAD_SEG = 0x1000  # matches Ghidra
DS_SEG = 0x1E0D
# Physical memory: map paragraphs as linear = seg<<4
MEM_BASE = 0
MEM_SIZE = 0x200000  # 2 MiB covers image + stack + scratch
STACK_SEG = 0x9000
STACK_SP = 0xFFFE


def _load_relocated_image(path: Path = FLAT, load_seg: int = LOAD_SEG) -> bytes:
    raw = path.read_bytes()
    hdr = struct.unpack_from("<H", raw, 8)[0] * 16
    nreloc = struct.unpack_from("<H", raw, 6)[0]
    reloff = struct.unpack_from("<H", raw, 0x18)[0]
    img = bytearray(raw[hdr:])
    for i in range(nreloc):
        off, seg = struct.unpack_from("<HH", raw, reloff + 4 * i)
        pos = seg * 16 + off
        if pos + 1 < len(img):
            val = struct.unpack_from("<H", img, pos)[0]
            struct.pack_into("<H", img, pos, (val + load_seg) & 0xFFFF)
    return bytes(img)


_IMAGE: Optional[bytes] = None


def relocated_image() -> bytes:
    global _IMAGE
    if _IMAGE is None:
        _IMAGE = _load_relocated_image()
    return _IMAGE


def ghidra_to_linear(seg: int, off: int) -> int:
    return (seg << 4) + off


def file_image_offset(seg: int, off: int) -> int:
    """Offset into relocated image (which starts at paragraph LOAD_SEG in Ghidra)."""
    return (seg - LOAD_SEG) * 16 + off


class Emu16:
    def __init__(self):
        self.uc = Uc(UC_ARCH_X86, UC_MODE_16)
        self.uc.mem_map(MEM_BASE, MEM_SIZE)
        img = relocated_image()
        # Place image at linear LOAD_SEG<<4
        base = LOAD_SEG << 4
        self.uc.mem_write(base, img)
        # Zero BSS-ish area after image for DS
        self.reset_regs()

    def reset_regs(self):
        uc = self.uc
        for reg, val in [
            (UC_X86_REG_AX, 0),
            (UC_X86_REG_BX, 0),
            (UC_X86_REG_CX, 0),
            (UC_X86_REG_DX, 0),
            (UC_X86_REG_SI, 0),
            (UC_X86_REG_DI, 0),
            (UC_X86_REG_BP, 0),
            (UC_X86_REG_FLAGS, 0x0202),
        ]:
            uc.reg_write(reg, val)
        uc.reg_write(UC_X86_REG_CS, LOAD_SEG)
        uc.reg_write(UC_X86_REG_DS, DS_SEG)
        uc.reg_write(UC_X86_REG_ES, DS_SEG)
        uc.reg_write(UC_X86_REG_SS, STACK_SEG)
        uc.reg_write(UC_X86_REG_SP, STACK_SP)

    def write_bytes(self, seg: int, off: int, data: bytes):
        self.uc.mem_write(ghidra_to_linear(seg, off), data)

    def read_bytes(self, seg: int, off: int, n: int) -> bytes:
        return bytes(self.uc.mem_read(ghidra_to_linear(seg, off), n))

    def push16(self, value: int):
        sp = (self.uc.reg_read(UC_X86_REG_SP) - 2) & 0xFFFF
        self.uc.reg_write(UC_X86_REG_SP, sp)
        ss = self.uc.reg_read(UC_X86_REG_SS)
        self.uc.mem_write(ghidra_to_linear(ss, sp), struct.pack("<H", value & 0xFFFF))

    def set_regs(self, **kwargs):
        m = {
            "ax": UC_X86_REG_AX,
            "bx": UC_X86_REG_BX,
            "cx": UC_X86_REG_CX,
            "dx": UC_X86_REG_DX,
            "si": UC_X86_REG_SI,
            "di": UC_X86_REG_DI,
            "bp": UC_X86_REG_BP,
            "sp": UC_X86_REG_SP,
            "cs": UC_X86_REG_CS,
            "ds": UC_X86_REG_DS,
            "es": UC_X86_REG_ES,
            "ss": UC_X86_REG_SS,
            "flags": UC_X86_REG_FLAGS,
            "al": UC_X86_REG_AL,
            "ah": UC_X86_REG_AH,
            "bl": UC_X86_REG_BL,
            "bh": UC_X86_REG_BH,
            "cl": UC_X86_REG_CL,
            "ch": UC_X86_REG_CH,
            "dl": UC_X86_REG_DL,
            "dh": UC_X86_REG_DH,
        }
        for k, v in kwargs.items():
            self.uc.reg_write(m[k.lower()], v & 0xFFFF if k.lower() not in ("al","ah","bl","bh","cl","ch","dl","dh") else v & 0xFF)

    def get_regs(self) -> Dict[str, int]:
        return {
            "ax": self.uc.reg_read(UC_X86_REG_AX),
            "bx": self.uc.reg_read(UC_X86_REG_BX),
            "cx": self.uc.reg_read(UC_X86_REG_CX),
            "dx": self.uc.reg_read(UC_X86_REG_DX),
            "si": self.uc.reg_read(UC_X86_REG_SI),
            "di": self.uc.reg_read(UC_X86_REG_DI),
            "bp": self.uc.reg_read(UC_X86_REG_BP),
            "sp": self.uc.reg_read(UC_X86_REG_SP),
            "cs": self.uc.reg_read(UC_X86_REG_CS),
            "ip": self.uc.reg_read(UC_X86_REG_IP),
            "flags": self.uc.reg_read(UC_X86_REG_FLAGS),
        }

    def run(
        self,
        seg: int,
        off: int,
        *,
        max_insns: int = 200000,
        stop_on_retf: bool = True,
        stop_addrs: Optional[Iterable[Tuple[int, int]]] = None,
        hook_code: Optional[Callable] = None,
    ) -> Dict[str, int]:
        """Execute starting at seg:off until RET/RETF or stop address.

        We plant a sentinel far-return target: push ret_off, ret_cs before call-style entry,
        OR for near routines expect RETN. Caller should push return frame as needed.
        """
        uc = self.uc
        stops = {(s << 4) + o for s, o in (stop_addrs or [])}
        sentinel = ghidra_to_linear(0xF000, 0x0000)
        stops.add(sentinel)
        # Ensure sentinel page exists (already in MEM_SIZE); write HLT
        uc.mem_write(sentinel, b"\xF4")

        def _hook(uc_, address, size, *args):
            if address in stops:
                uc_.emu_stop()
            if hook_code:
                hook_code(uc_, address, size)

        from unicorn import UC_HOOK_CODE

        h = uc.hook_add(UC_HOOK_CODE, _hook)
        try:
            start = ghidra_to_linear(seg, off)
            # Unicorn 16-bit: emu_start uses linear address; CS:IP must match
            uc.reg_write(UC_X86_REG_CS, seg)
            uc.reg_write(UC_X86_REG_IP, off)
            try:
                uc.emu_start(start, 0, count=max_insns)
            except UcError as e:
                # HLT at sentinel raises; treat as success if IP at sentinel
                regs = self.get_regs()
                if ghidra_to_linear(regs["cs"], regs["ip"]) != sentinel:
                    raise
            return self.get_regs()
        finally:
            uc.hook_del(h)


def call_near(emu: Emu16, seg: int, off: int, **regs) -> Dict[str, int]:
    """Call a near routine: push near return to sentinel IP within same CS... 
    Actually near RET pops IP only. We set CS=seg and push sentinel offset in a fake CS.
    Simpler: push 0x0000 as return IP and put HLT at seg:0000? That may be code.
    Use a scratch near-return stub in STACK_SEG.
    """
    emu.reset_regs()
    emu.set_regs(cs=seg, ds=DS_SEG, es=DS_SEG, ss=STACK_SEG, sp=STACK_SP, **regs)
    # Write near stub at STACK_SEG:0100 = HLT
    stub_off = 0x0100
    emu.write_bytes(STACK_SEG, stub_off, b"\xF4")
    emu.push16(stub_off)
    # When function RETs, IP=stub_off but CS still = seg — PROBLEM for near ret.
    # Near RET only pops IP; CS unchanged. So stub must be in same segment as callee.
    # Plant HLT at a high offset in the callee's segment if free, else use hook on RET.
    return _run_with_ret_detect(emu, seg, off, far=False)


def call_far(emu: Emu16, seg: int, off: int, **regs) -> Dict[str, int]:
    emu.reset_regs()
    emu.set_regs(cs=seg, ds=DS_SEG, es=DS_SEG, ss=STACK_SEG, sp=STACK_SP, **regs)
    # far return frame: IP, CS → sentinel
    emu.push16(0xF000)  # CS
    emu.push16(0x0000)  # IP
    return emu.run(seg, off, stop_addrs=[(0xF000, 0x0000)])


def _run_with_ret_detect(emu: Emu16, seg: int, off: int, far: bool) -> Dict[str, int]:
    """Hook RET/RETF opcodes to stop."""
    from unicorn import UC_HOOK_CODE

    uc = emu.uc
    start_sp = uc.reg_read(UC_X86_REG_SP)

    def hook(uc_, address, size, *args):
        op = bytes(uc_.mem_read(address, 1))[0]
        if op not in (0xC3, 0xCB, 0xC2, 0xCA):
            return
        sp = uc_.reg_read(UC_X86_REG_SP)
        if sp < start_sp - 8:
            return
        ss = uc_.reg_read(UC_X86_REG_SS)
        if op in (0xC3, 0xC2):
            ip = struct.unpack("<H", bytes(uc_.mem_read(ghidra_to_linear(ss, sp), 2)))[0]
            uc_.reg_write(UC_X86_REG_SP, (sp + 2) & 0xFFFF)
            if op == 0xC2:
                imm = struct.unpack("<H", bytes(uc_.mem_read(address + 1, 2)))[0]
                uc_.reg_write(UC_X86_REG_SP, (uc_.reg_read(UC_X86_REG_SP) + imm) & 0xFFFF)
            uc_.reg_write(UC_X86_REG_IP, ip)
        else:
            ip = struct.unpack("<H", bytes(uc_.mem_read(ghidra_to_linear(ss, sp), 2)))[0]
            cs = struct.unpack(
                "<H", bytes(uc_.mem_read(ghidra_to_linear(ss, (sp + 2) & 0xFFFF), 2))
            )[0]
            uc_.reg_write(UC_X86_REG_SP, (sp + 4) & 0xFFFF)
            if op == 0xCA:
                imm = struct.unpack("<H", bytes(uc_.mem_read(address + 1, 2)))[0]
                uc_.reg_write(UC_X86_REG_SP, (uc_.reg_read(UC_X86_REG_SP) + imm) & 0xFFFF)
            uc_.reg_write(UC_X86_REG_CS, cs)
            uc_.reg_write(UC_X86_REG_IP, ip)
        uc_.emu_stop()

    if not far:
        emu.push16(0xDEAD)
    else:
        emu.push16(0xF000)
        emu.push16(0x0000)

    h = uc.hook_add(UC_HOOK_CODE, hook)
    try:
        uc.reg_write(UC_X86_REG_CS, seg)
        uc.reg_write(UC_X86_REG_IP, off)
        try:
            uc.emu_start(ghidra_to_linear(seg, off), 0, count=500000)
        except UcError:
            pass
        return emu.get_regs()
    finally:
        uc.hook_del(h)


def call_real_binop_regs(emu: Emu16, seg: int, off: int, a: float, b: float, far: bool = False):
    """TP Real binop: left in DX:BX:AX, right in DI:SI:CX."""
    from real48 import float_to_regs

    ax, bx, dx = float_to_regs(a)
    cx, si, di = float_to_regs(b)
    if far:
        return call_far(emu, seg, off, ax=ax, bx=bx, dx=dx, cx=cx, si=si, di=di)
    return call_near(emu, seg, off, ax=ax, bx=bx, dx=dx, cx=cx, si=si, di=di)


def result_real(regs: Dict[str, int]) -> float:
    from real48 import regs_to_float

    return regs_to_float(regs["ax"], regs["bx"], regs["dx"])
