"""16-bit real-mode Unicorn harness for bomb25_flat.exe (Ghidra load base 0x1000).

Supports VGA A000 video RAM and INT 10h/21h/1Ah hooks for Graph/BGI emulation.
"""
from __future__ import annotations

import struct
from pathlib import Path
from typing import Callable, Dict, Iterable, List, Optional, Tuple

from unicorn import Uc, UcError, UC_ARCH_X86, UC_MODE_16, UC_HOOK_CODE, UC_HOOK_INTR
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
MEM_BASE = 0
MEM_SIZE = 0x200000  # 2 MiB
STACK_SEG = 0x9000
STACK_SP = 0xFFFE
VGA_SEG = 0xA000
VGA_SIZE = 0x10000

# DOS heap for INT 21h AH=48h allocations (paragraphs)
_HEAP_SEG = 0xB000
_HEAP_NEXT = _HEAP_SEG


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
    return (seg - LOAD_SEG) * 16 + off


class Emu16:
    def __init__(self, hook_interrupts: bool = True):
        global _HEAP_NEXT
        _HEAP_NEXT = _HEAP_SEG
        self.uc = Uc(UC_ARCH_X86, UC_MODE_16)
        self.uc.mem_map(MEM_BASE, MEM_SIZE)
        img = relocated_image()
        self.uc.mem_write(LOAD_SEG << 4, img)
        # VGA framebuffer
        self.uc.mem_write(VGA_SEG << 4, bytes(VGA_SIZE))
        # VGA256 OutText uses BIOS 8×8 font at F000:FA6E
        self._install_bios_font()
        self.int_log: List[str] = []
        self.video_mode = 3
        self.palette: Dict[int, Tuple[int, int, int]] = {}
        self.mouse_x = 0
        self.mouse_y = 0
        self.mouse_buttons = 0
        self._intr_hook = None
        self.reset_regs()
        if hook_interrupts:
            self.install_interrupt_hooks()

    def _install_bios_font(self):
        """Synthetic 8×8 font so BGI OutText can plot glyphs (full block for printable)."""
        font = bytearray(256 * 8)
        for ch in range(32, 127):
            base = ch * 8
            font[base : base + 8] = bytes(
                [0x7E, 0x81, 0xA5, 0x81, 0xA5, 0x99, 0x81, 0x7E]
            )  # recognizable glyph
        self.uc.mem_write(ghidra_to_linear(0xF000, 0xFA6E), bytes(font))

    def install_interrupt_hooks(self):
        if self._intr_hook is not None:
            return

        def on_intr(uc, intno, data):
            self._handle_interrupt(intno)

        self._intr_hook = self.uc.hook_add(UC_HOOK_INTR, on_intr)

    def _handle_interrupt(self, intno: int):
        ah = self.uc.reg_read(UC_X86_REG_AH)
        al = self.uc.reg_read(UC_X86_REG_AL)
        ax = self.uc.reg_read(UC_X86_REG_AX)
        bx = self.uc.reg_read(UC_X86_REG_BX)
        cx = self.uc.reg_read(UC_X86_REG_CX)
        dx = self.uc.reg_read(UC_X86_REG_DX)
        flags = self.uc.reg_read(UC_X86_REG_FLAGS)

        if intno == 0x10:
            self.int_log.append(f"INT10 AH={ah:02X} AL={al:02X} BX={bx:04X} CX={cx:04X} DX={dx:04X}")
            if ah == 0x00:  # set mode
                self.video_mode = al
                if al == 0x13:
                    self.uc.mem_write(VGA_SEG << 4, bytes(VGA_SIZE))
            elif ah == 0x0F:  # get mode
                self.uc.reg_write(UC_X86_REG_AL, self.video_mode)
                self.uc.reg_write(UC_X86_REG_AH, 80)  # cols
            elif ah == 0x10:  # DAC/palette
                if al == 0x10:  # set one DAC register
                    self.palette[bx & 0xFF] = (
                        self.uc.reg_read(UC_X86_REG_DH),
                        self.uc.reg_read(UC_X86_REG_CH),
                        self.uc.reg_read(UC_X86_REG_CL),
                    )
                elif al == 0x12:  # set block of DAC regs
                    pass
            # clear CF
            self.uc.reg_write(UC_X86_REG_FLAGS, flags & ~1)
            return

        if intno == 0x21:
            self.int_log.append(f"INT21 AH={ah:02X} BX={bx:04X} CX={cx:04X} DX={dx:04X}")
            global _HEAP_NEXT
            if ah == 0x48:  # allocate BX paragraphs
                n = bx
                seg = _HEAP_NEXT
                _HEAP_NEXT = (_HEAP_NEXT + n + 1) & 0xFFFF
                if ghidra_to_linear(_HEAP_NEXT, 0) >= MEM_SIZE:
                    self.uc.reg_write(UC_X86_REG_FLAGS, flags | 1)
                    self.uc.reg_write(UC_X86_REG_AX, 8)  # insufficient memory
                else:
                    self.uc.reg_write(UC_X86_REG_AX, seg)
                    self.uc.reg_write(UC_X86_REG_FLAGS, flags & ~1)
            elif ah == 0x49:  # free ES
                self.uc.reg_write(UC_X86_REG_FLAGS, flags & ~1)
            elif ah == 0x4A:  # resize
                self.uc.reg_write(UC_X86_REG_FLAGS, flags & ~1)
            elif ah == 0x30:  # get DOS version
                self.uc.reg_write(UC_X86_REG_AX, 0x0006)  # DOS 6.00
                self.uc.reg_write(UC_X86_REG_FLAGS, flags & ~1)
            elif ah == 0x25:  # set vector
                self.uc.reg_write(UC_X86_REG_FLAGS, flags & ~1)
            elif ah == 0x35:  # get vector
                self.uc.reg_write(UC_X86_REG_ES, 0)
                self.uc.reg_write(UC_X86_REG_BX, 0)
                self.uc.reg_write(UC_X86_REG_FLAGS, flags & ~1)
            elif ah == 0x2C:  # get time
                self.uc.reg_write(UC_X86_REG_CX, 0x1234)
                self.uc.reg_write(UC_X86_REG_DX, 0x5678)
                self.uc.reg_write(UC_X86_REG_FLAGS, flags & ~1)
            elif ah == 0x4C:  # exit
                self.uc.emu_stop()
            else:
                self.uc.reg_write(UC_X86_REG_FLAGS, flags & ~1)
            return

        if intno == 0x1A:
            self.int_log.append(f"INT1A AH={ah:02X}")
            if ah == 0x00:
                self.uc.reg_write(UC_X86_REG_CX, 0)
                self.uc.reg_write(UC_X86_REG_DX, 0x1234)
            self.uc.reg_write(UC_X86_REG_FLAGS, flags & ~1)
            return

        if intno == 0x33:  # mouse
            self.int_log.append(f"INT33 AX={ax:04X}")
            if ax == 0:
                self.uc.reg_write(UC_X86_REG_AX, 0xFFFF)
                self.uc.reg_write(UC_X86_REG_BX, 3)
            elif ax == 3:  # get position / button status
                self.uc.reg_write(UC_X86_REG_BX, getattr(self, "mouse_buttons", 0))
                self.uc.reg_write(UC_X86_REG_CX, getattr(self, "mouse_x", 0))
                self.uc.reg_write(UC_X86_REG_DX, getattr(self, "mouse_y", 0))
            self.uc.reg_write(UC_X86_REG_FLAGS, flags & ~1)
            return

        self.int_log.append(f"INT{intno:02X} AH={ah:02X}")
        self.uc.reg_write(UC_X86_REG_FLAGS, flags & ~1)

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

    def read_u16(self, seg: int, off: int) -> int:
        return struct.unpack("<H", self.read_bytes(seg, off, 2))[0]

    def write_u16(self, seg: int, off: int, val: int):
        self.write_bytes(seg, off, struct.pack("<H", val & 0xFFFF))

    def vram(self) -> bytearray:
        return bytearray(self.read_bytes(VGA_SEG, 0, VGA_SIZE))

    def pixel(self, x: int, y: int) -> int:
        return self.read_bytes(VGA_SEG, y * 320 + x, 1)[0]

    def set_pixel(self, x: int, y: int, c: int):
        self.write_bytes(VGA_SEG, y * 320 + x, bytes([c & 0xFF]))

    def push16(self, value: int):
        sp = (self.uc.reg_read(UC_X86_REG_SP) - 2) & 0xFFFF
        self.uc.reg_write(UC_X86_REG_SP, sp)
        ss = self.uc.reg_read(UC_X86_REG_SS)
        self.uc.mem_write(ghidra_to_linear(ss, sp), struct.pack("<H", value & 0xFFFF))

    def push_far_ptr(self, seg: int, off: int):
        """Push far pointer as used by TP (segment then offset? Actually push seg; push off → off at lower addr)."""
        self.push16(seg)
        self.push16(off)

    def set_regs(self, **kwargs):
        m = {
            "ax": UC_X86_REG_AX, "bx": UC_X86_REG_BX, "cx": UC_X86_REG_CX, "dx": UC_X86_REG_DX,
            "si": UC_X86_REG_SI, "di": UC_X86_REG_DI, "bp": UC_X86_REG_BP, "sp": UC_X86_REG_SP,
            "cs": UC_X86_REG_CS, "ds": UC_X86_REG_DS, "es": UC_X86_REG_ES, "ss": UC_X86_REG_SS,
            "flags": UC_X86_REG_FLAGS,
            "al": UC_X86_REG_AL, "ah": UC_X86_REG_AH, "bl": UC_X86_REG_BL, "bh": UC_X86_REG_BH,
            "cl": UC_X86_REG_CL, "ch": UC_X86_REG_CH, "dl": UC_X86_REG_DL, "dh": UC_X86_REG_DH,
        }
        for k, v in kwargs.items():
            kl = k.lower()
            self.uc.reg_write(m[kl], v & 0xFF if kl in ("al","ah","bl","bh","cl","ch","dl","dh") else v & 0xFFFF)

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
            "ds": self.uc.reg_read(UC_X86_REG_DS),
            "es": self.uc.reg_read(UC_X86_REG_ES),
            "flags": self.uc.reg_read(UC_X86_REG_FLAGS),
        }

    def snapshot_ds_graph(self) -> Dict[int, int]:
        """Snapshot common Graph DS words."""
        offs = [0xE63A, 0xE642, 0xE644, 0xE660, 0xE666, 0xE668, 0xE670,
                0xE684, 0xE686, 0xE6B4, 0xE6B6, 0xE5E4, 0xE5E6, 0xE5D8]
        return {o: self.read_u16(DS_SEG, o) for o in offs}

    def run(
        self,
        seg: int,
        off: int,
        *,
        max_insns: int = 2_000_000,
        stop_addrs: Optional[Iterable[Tuple[int, int]]] = None,
        hook_code: Optional[Callable] = None,
    ) -> Dict[str, int]:
        uc = self.uc
        stops = {(s << 4) + o for s, o in (stop_addrs or [])}
        sentinel = ghidra_to_linear(0xF000, 0x0000)
        stops.add(sentinel)
        uc.mem_write(sentinel, b"\xF4")

        def _hook(uc_, address, size, *args):
            if address in stops:
                uc_.emu_stop()
            if hook_code:
                hook_code(uc_, address, size)

        h = uc.hook_add(UC_HOOK_CODE, _hook)
        try:
            uc.reg_write(UC_X86_REG_CS, seg)
            uc.reg_write(UC_X86_REG_IP, off)
            try:
                uc.emu_start(ghidra_to_linear(seg, off), 0, count=max_insns)
            except UcError:
                regs = self.get_regs()
                if ghidra_to_linear(regs["cs"], regs["ip"]) != sentinel:
                    # HLT at sentinel is OK; other errors re-raise if not stopped cleanly
                    if regs["cs"] == 0xF000:
                        return regs
                    raise
            return self.get_regs()
        finally:
            uc.hook_del(h)


def call_near(emu: Emu16, seg: int, off: int, **regs) -> Dict[str, int]:
    emu.reset_regs()
    emu.set_regs(cs=seg, ds=DS_SEG, es=DS_SEG, ss=STACK_SEG, sp=STACK_SP, **regs)
    return _run_with_ret_detect(emu, seg, off, far=False)


def call_far(emu: Emu16, seg: int, off: int, **regs) -> Dict[str, int]:
    """Call far with optional stack_args (list of words, pushed first→last = left→right TP order).

    Extra kw: stack_args: List[int]
    """
    stack_args = regs.pop("stack_args", None)
    base = dict(
        cs=seg, ds=DS_SEG, es=DS_SEG, ss=STACK_SEG, sp=STACK_SP,
        ax=0, bx=0, cx=0, dx=0, si=0, di=0, bp=0, flags=0x0202,
    )
    base.update(regs)
    emu.set_regs(**base)
    if stack_args:
        for w in stack_args:
            emu.push16(w)
    emu.push16(0xF000)
    emu.push16(0x0000)
    return emu.run(seg, off, stop_addrs=[(0xF000, 0x0000)])


def call_far_fresh(emu: Emu16, seg: int, off: int, **regs) -> Dict[str, int]:
    """Like original call_far: reset GP regs then call (keeps memory)."""
    return call_far(emu, seg, off, **regs)


def _run_with_ret_detect(emu: Emu16, seg: int, off: int, far: bool) -> Dict[str, int]:
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
            uc.emu_start(ghidra_to_linear(seg, off), 0, count=2_000_000)
        except UcError:
            pass
        return emu.get_regs()
    finally:
        uc.hook_del(h)


def call_real_binop_regs(emu: Emu16, seg: int, off: int, a: float, b: float, far: bool = False):
    from real48 import float_to_regs

    ax, bx, dx = float_to_regs(a)
    cx, si, di = float_to_regs(b)
    if far:
        return call_far(emu, seg, off, ax=ax, bx=bx, dx=dx, cx=cx, si=si, di=di)
    return call_near(emu, seg, off, ax=ax, bx=bx, dx=dx, cx=cx, si=si, di=di)


def result_real(regs: Dict[str, int]) -> float:
    from real48 import regs_to_float

    return regs_to_float(regs["ax"], regs["bx"], regs["dx"])


def pascal_string(s: str) -> bytes:
    b = s.encode("latin-1")
    if len(b) > 255:
        b = b[:255]
    return bytes([len(b)]) + b


def vram_diff(before: bytes, after: bytes):
    """Yield (offset, old, new) for changed bytes."""
    for i, (a, b) in enumerate(zip(before, after)):
        if a != b:
            yield i, a, b


def diff_bbox(before: bytes, after: bytes):
    """Bounding box of changed pixels in 320x200, or None."""
    xs, ys = [], []
    for off, _a, _b in vram_diff(before, after):
        if off >= 320 * 200:
            continue
        xs.append(off % 320)
        ys.append(off // 320)
    if not xs:
        return None
    return min(xs), min(ys), max(xs), max(ys), len(xs)
