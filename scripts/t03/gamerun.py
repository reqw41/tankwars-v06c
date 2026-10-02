#!/usr/bin/env python3
"""Полный запуск Tank Wars 2.5 в unicorn: DOS/BIOS/VGA-заглушки, файлы из orig/, сценарий клавиш.

В отличие от emu16 (вызов отдельных процедур на образе Ghidra) здесь игра стартует с entry, как в DOS:
PSP, куча TP, InitGraph, меню. Оверлеи кладутся в верх памяти (OVL_ABS), стабы INT 3Fh заменены
на JMP FAR, поэтому оверлейный менеджер не работает.

Адреса: abs = rel + LOAD. Для перевода в адреса Ghidra (база 0x1000) — g2a()/a2g().
"""
from __future__ import annotations

import struct
import zlib
from pathlib import Path
from typing import Callable, Dict, List, Optional, Tuple

from unicorn import Uc, UC_ARCH_X86, UC_MODE_16, UC_HOOK_INTR, UC_HOOK_INSN, UC_HOOK_CODE, UC_HOOK_MEM_READ
from unicorn.x86_const import *  # noqa: F401,F403

ROOT = Path(__file__).resolve().parents[2]
ORIG = next(p for p in (ROOT / "orig").glob("TankWarsV2.5*") if p.is_dir())
EXE = ROOT / "re" / "bomb25.exe"
OVR = ROOT / "re" / "bomb25.ovr"

PSP = 0x0100
LOAD = 0x0110            # сегмент загрузки образа (rel 0)
OVL_ABS = 0x8000         # сюда кладём оверлеи
MEMTOP = 0x8000          # PSP:[2] — верх памяти для кучи TP
GHIDRA_BASE = 0x1000
DS_REL = 0x0E0D
VGA = 0xA000


def g2a(seg: int) -> int:
    """Сегмент Ghidra (резидентный) -> абсолютный в этом запуске (для оверлеев см. ovl_seg_map)."""
    return seg - GHIDRA_BASE + LOAD


class Game:
    def __init__(self, keys: Optional[List[int]] = None, cfg: Optional[bytes] = None,
                 files_dir: Path = ORIG, ticks_per_block: int = 0,
                 dos_time: Tuple[int, int] = (0x0C1E, 0x0F32)):
        self.uc = Uc(UC_ARCH_X86, UC_MODE_16)
        self.uc.mem_map(0, 0x110000)
        self.files_dir = files_dir
        self.dos_time = dos_time
        self.cfg_override = cfg
        self.keys: List[int] = list(keys or [])   # слова INT16: (scan<<8)|ascii
        self.need_key = False
        self.idle_polls = 0
        self.stdout = bytearray()
        self.handles: Dict[int, Tuple[bytes, int, str]] = {}
        self.written: Dict[str, bytearray] = {}
        self.next_handle = 5
        self.palette = [(0, 0, 0)] * 256
        self.dac_w_index = 0
        self.dac_w_comp = 0
        self.dac_r_index = 0
        self.dac_r_comp = 0
        self.retrace = 0
        self.tick = 0
        self.int_log: List[str] = []
        self.unknown: Dict[str, int] = {}
        self.ovl_seg_map: Dict[int, int] = {}  # ghidra seg -> abs seg
        self.exit_code: Optional[int] = None
        self._load()
        self.uc.hook_add(UC_HOOK_INTR, self._on_intr)
        self.uc.hook_add(UC_HOOK_INSN, self._on_in, None, 1, 0, UC_X86_INS_IN)
        self.uc.hook_add(UC_HOOK_INSN, self._on_out, None, 1, 0, UC_X86_INS_OUT)
        # BIOS-тик 0040:006C сдвигается каждые READS_PER_TICK чтений (калибровка и Delay в Crt)
        self.tick_reads = 0
        self.uc.hook_add(UC_HOOK_MEM_READ, self._on_tick_read, None, 0x46C, 0x46F)

    # ---------- загрузка ----------
    def _load(self):
        exe = EXE.read_bytes()
        ovr = OVR.read_bytes()
        (last, pages, nrel, hdrpar, _mn, _mx, ss, sp, _cs, ip, cs, reloff, _ov) = struct.unpack('<13H', exe[2:28])
        size = (pages - 1) * 512 + (last or 512)
        img = bytearray(exe[hdrpar * 16:size])
        relocs = [struct.unpack('<HH', exe[reloff + 4 * i: reloff + 4 * i + 4]) for i in range(nrel)]
        ovl_rel = OVL_ABS - LOAD
        need = ovl_rel * 16 - len(img)
        assert need > 0
        img += bytes(need)
        # те же правила поиска стабов, что в flatten_ovr.py
        stubs = []
        for p in range(0, ovl_rel * 16 - need, 16):
            if img[p:p + 2] != b'\xcd\x3f':
                continue
            save, fo, csz, fsz, nent = struct.unpack('<HIHHH', img[p + 2:p + 14])
            if not (8 <= fo and fo + csz + fsz <= len(ovr) and csz > 0 and fsz % 2 == 0 and 0 < nent < 200):
                continue
            ents = img[p + 32:p + 32 + 5 * nent]
            if not all(ents[5 * i:5 * i + 2] == b'\xcd\x3f' for i in range(nent)):
                continue
            stubs.append((p // 16, fo, csz, fsz, nent))
        flat_next = 0x1185  # как в flatten_ovr: оверлеи шли подряд с конца образа
        for stubseg, fo, csz, fsz, nent in stubs:
            while len(img) % 16:
                img.append(0)
            newseg = len(img) // 16
            self.ovl_seg_map[flat_next + GHIDRA_BASE] = newseg + LOAD
            flat_next += (csz + 15) // 16
            img += ovr[fo:fo + csz]
            for (fx,) in struct.iter_unpack('<H', ovr[fo + csz:fo + csz + fsz]):
                relocs.append((fx, newseg))
            for i in range(nent):
                e = stubseg * 16 + 32 + 5 * i
                off = struct.unpack('<H', img[e + 2:e + 4])[0]
                img[e:e + 5] = b'\xea' + struct.pack('<HH', off, newseg)
                relocs.append((32 + 5 * i + 3, stubseg))
        for off, seg in relocs:
            pos = seg * 16 + off
            v = struct.unpack_from('<H', img, pos)[0]
            struct.pack_into('<H', img, pos, (v + LOAD) & 0xFFFF)
        self.image_len = len(img)
        self.uc.mem_write(LOAD * 16, bytes(img))
        # PSP
        psp = bytearray(256)
        psp[0:2] = b'\xcd\x20'
        struct.pack_into('<H', psp, 2, MEMTOP)
        struct.pack_into('<H', psp, 0x2C, 0x00F0)   # env
        psp[0x80] = 0
        psp[0x81] = 0x0D
        self.uc.mem_write(PSP * 16, bytes(psp))
        env = b'PATH=C:\\\x00\x00\x01\x00C:\\BOMB.EXE\x00'
        self.uc.mem_write(0x00F0 * 16, env)
        # IVT: всё на IRET-заглушку F000:FF00 (INT xx обрабатываем хуком, но far-call в вектор тоже возможен)
        self.uc.mem_write(0xFFF00, b'\xcf')
        ivt = b''.join(struct.pack('<HH', 0xFF00, 0xF000) for _ in range(256))
        self.uc.mem_write(0, ivt)
        # BIOS data: экран 80x25, тик
        self.uc.mem_write(0x449, bytes([3]))
        self.uc.mem_write(0x44A, struct.pack('<H', 80))
        self.uc.mem_write(0x484, bytes([24]))
        self.uc.mem_write(0x463, struct.pack('<H', 0x3D4))
        self.uc.mem_write(0x410, struct.pack('<H', 0x0020))
        # BIOS 8x8 font для OutText (как в emu16 — синтетика не годится для картинок, оставляем нули)
        r = self.uc
        r.reg_write(UC_X86_REG_DS, PSP)
        r.reg_write(UC_X86_REG_ES, PSP)
        r.reg_write(UC_X86_REG_SS, ss + LOAD)
        r.reg_write(UC_X86_REG_SP, sp)
        r.reg_write(UC_X86_REG_CS, cs + LOAD)
        r.reg_write(UC_X86_REG_IP, ip)
        self.start = ((cs + LOAD) << 4) + ip

    IDLE_POLLS_STOP = 300  # столько пустых KeyPressed подряд = игра ждёт клавишу
    READS_PER_TICK = 550   # => DelayCnt = 10 итераций на мс

    def _on_tick_read(self, uc, access, address, size, value, data):
        self.tick_reads += 1
        if self.tick_reads >= self.READS_PER_TICK:
            self.tick_reads = 0
            self.tick += 1
            uc.mem_write(0x46C, struct.pack('<I', self.tick))

    # ---------- порты ----------
    def _on_in(self, uc, port, size, data):
        if port == 0x3DA:
            self.retrace ^= 0x09
            return self.retrace
        if port == 0x3C9:
            c = self.palette[self.dac_r_index][self.dac_r_comp]
            self.dac_r_comp += 1
            if self.dac_r_comp == 3:
                self.dac_r_comp = 0
                self.dac_r_index = (self.dac_r_index + 1) & 0xFF
            return c
        if port == 0x60:
            return 0
        if port == 0x61:
            return 0
        if port == 0x201:  # джойстик нет
            return 0xFF
        self.unknown[f'IN {port:x}'] = self.unknown.get(f'IN {port:x}', 0) + 1
        return 0

    def _on_out(self, uc, port, size, value, data):
        if port == 0x3C8:
            self.dac_w_index = value & 0xFF
            self.dac_w_comp = 0
        elif port == 0x3C7:
            self.dac_r_index = value & 0xFF
            self.dac_r_comp = 0
        elif port == 0x3C9:
            p = list(self.palette[self.dac_w_index])
            p[self.dac_w_comp] = value & 0x3F
            self.palette[self.dac_w_index] = tuple(p)
            self.dac_w_comp += 1
            if self.dac_w_comp == 3:
                self.dac_w_comp = 0
                self.dac_w_index = (self.dac_w_index + 1) & 0xFF

    # ---------- прерывания ----------
    def _reg(self, r):
        return self.uc.reg_read(r)

    def _set(self, r, v):
        self.uc.reg_write(r, v & 0xFFFF)

    def _cf(self, on: bool):
        f = self._reg(UC_X86_REG_FLAGS)
        self._set(UC_X86_REG_FLAGS, (f | 1) if on else (f & ~1))

    def _zf(self, on: bool):
        f = self._reg(UC_X86_REG_FLAGS)
        self._set(UC_X86_REG_FLAGS, (f | 0x40) if on else (f & ~0x40))

    def _str_at(self, seg, off, maxlen=128) -> str:
        b = bytes(self.uc.mem_read(seg * 16 + off, maxlen))
        return b.split(b'\0')[0].decode('latin1')

    def _on_intr(self, uc, intno, data):
        ah = self._reg(UC_X86_REG_AH)
        al = self._reg(UC_X86_REG_AL)
        if intno == 0x21:
            self._dos(ah, al)
        elif intno == 0x10:
            if ah == 0x0F:
                self._set(UC_X86_REG_AX, (80 << 8) | (self.uc.mem_read(0x449, 1)[0]))
                self._set(UC_X86_REG_BX, 0)
            elif ah == 0x00:
                self.uc.mem_write(0x449, bytes([al & 0x7F]))
                if (al & 0x7F) == 0x13 and not (al & 0x80):
                    self.uc.mem_write(VGA * 16, bytes(65536))
            elif ah == 0x10 and al == 0x10:
                bx = self._reg(UC_X86_REG_BX)
                self.palette[bx & 0xFF] = (self._reg(UC_X86_REG_DH), self._reg(UC_X86_REG_CH), self._reg(UC_X86_REG_CL))
            elif ah == 0x10 and al == 0x12:
                bx, cx = self._reg(UC_X86_REG_BX), self._reg(UC_X86_REG_CX)
                es, dx = self._reg(UC_X86_REG_ES), self._reg(UC_X86_REG_DX)
                raw = bytes(self.uc.mem_read(es * 16 + dx, 3 * cx))
                for i in range(cx):
                    self.palette[(bx + i) & 0xFF] = tuple(raw[3 * i:3 * i + 3])
            elif ah == 0x11 and al == 0x30:  # font info
                self._set(UC_X86_REG_ES, 0xF000)
                self._set(UC_X86_REG_BP, 0xFA6E)
            elif ah == 0x1A:
                self._set(UC_X86_REG_AX, 0x001A)
                self._set(UC_X86_REG_BX, 0x0008)
            elif ah == 0x12:
                self._set(UC_X86_REG_BX, 0x0003)
            self.int_log.append(f'INT10 {ah:02x}{al:02x}')
        elif intno == 0x16:
            if ah in (0x00, 0x10):
                if not self.keys:
                    self.need_key = True
                    # вернуть управление на эту же инструкцию INT 16 при следующем run()
                    ip = self._reg(UC_X86_REG_IP)
                    self._set(UC_X86_REG_IP, ip - 2)
                    self.uc.emu_stop()
                    return
                self._set(UC_X86_REG_AX, self.keys.pop(0))
            elif ah in (0x01, 0x11):
                if self.keys:
                    self.idle_polls = 0
                    self._set(UC_X86_REG_AX, self.keys[0])
                    self._zf(False)
                else:
                    self._zf(True)
                    self.idle_polls += 1
                    if self.idle_polls >= self.IDLE_POLLS_STOP:
                        self.idle_polls = 0
                        self.need_key = True
                        self.uc.emu_stop()
            elif ah in (0x02, 0x12):
                self._set(UC_X86_REG_AX, 0)
        elif intno == 0x1A:
            if ah == 0:
                self.tick += 1
                self._set(UC_X86_REG_CX, self.tick >> 16)
                self._set(UC_X86_REG_DX, self.tick)
                self._set(UC_X86_REG_AX, 0)
        elif intno == 0x33:
            if self._reg(UC_X86_REG_AX) == 0:
                self._set(UC_X86_REG_AX, 0)  # мыши нет
        elif intno == 0x11:
            self._set(UC_X86_REG_AX, 0x0026)
        elif intno == 0x12:
            self._set(UC_X86_REG_AX, 640)
        elif intno in (0x15, 0x67, 0x2F, 0x1B, 0x23, 0x24, 0x28, 0x08, 0x1C):
            pass
        else:
            k = f'INT{intno:02x}/{ah:02x}'
            self.unknown[k] = self.unknown.get(k, 0) + 1

    def _find_file(self, name: str) -> Optional[Path]:
        base = name.replace('\\', '/').split('/')[-1].split(':')[-1].upper()
        for p in self.files_dir.iterdir():
            if p.name.upper() == base:
                return p
        return None

    def _dos(self, ah, al):
        R = self._reg
        if ah == 0x30:
            self._set(UC_X86_REG_AX, 0x1E03)  # DOS 3.30
            self._set(UC_X86_REG_BX, 0)
        elif ah == 0x25:
            pass
        elif ah == 0x35:
            self._set(UC_X86_REG_ES, 0xF000)
            self._set(UC_X86_REG_BX, 0xFF00)
        elif ah == 0x4A:
            self._cf(False)
        elif ah == 0x48:
            self._set(UC_X86_REG_AX, 8)
            self._set(UC_X86_REG_BX, 0)
            self._cf(True)
        elif ah == 0x49:
            self._cf(False)
        elif ah in (0x2C, 0x2A):
            if ah == 0x2C:
                self._set(UC_X86_REG_CX, self.dos_time[0])
                self._set(UC_X86_REG_DX, self.dos_time[1])
            else:
                self._set(UC_X86_REG_CX, 1991)
                self._set(UC_X86_REG_DX, 0x0511)
        elif ah == 0x19:
            self._set(UC_X86_REG_AX, 2)
        elif ah == 0x47:
            self.uc.mem_write(R(UC_X86_REG_DS) * 16 + R(UC_X86_REG_SI), b'\0')
            self._cf(False)
        elif ah == 0x0E or ah == 0x3B:
            self._cf(False)
        elif ah == 0x1A:
            self.dta = (R(UC_X86_REG_DS), R(UC_X86_REG_DX))
        elif ah == 0x2F:
            self._set(UC_X86_REG_ES, PSP)
            self._set(UC_X86_REG_BX, 0x80)
        elif ah == 0x62:
            self._set(UC_X86_REG_BX, PSP)
        elif ah == 0x44:
            h = R(UC_X86_REG_BX)
            if al == 0:
                self._set(UC_X86_REG_DX, 0x80D3 if h <= 4 else 0x0002)
                self._cf(False)
            else:
                self._cf(False)
        elif ah in (0x3D, 0x3C, 0x5B):
            name = self._str_at(R(UC_X86_REG_DS), R(UC_X86_REG_DX))
            self.int_log.append(f'OPEN {name} ah={ah:02x} al={al}')
            if ah == 0x3D:
                p = self._find_file(name)
                data = None
                if name.upper().endswith('BOMB.CFG') and self.cfg_override is not None:
                    data = self.cfg_override
                elif p is not None:
                    data = p.read_bytes()
                if data is None:
                    self._set(UC_X86_REG_AX, 2)
                    self._cf(True)
                    return
            else:
                data = b''
                self.written[name.upper()] = bytearray()
            h = self.next_handle
            self.next_handle += 1
            self.handles[h] = [data, 0, name.upper()]
            self._set(UC_X86_REG_AX, h)
            self._cf(False)
        elif ah == 0x3E:
            self.handles.pop(R(UC_X86_REG_BX), None)
            self._cf(False)
        elif ah == 0x3F:
            h, n = R(UC_X86_REG_BX), R(UC_X86_REG_CX)
            if h == 0:
                self._set(UC_X86_REG_AX, 0)
                self._cf(False)
                return
            f = self.handles.get(h)
            if f is None:
                self._set(UC_X86_REG_AX, 6)
                self._cf(True)
                return
            chunk = f[0][f[1]:f[1] + n]
            f[1] += len(chunk)
            self.uc.mem_write(R(UC_X86_REG_DS) * 16 + R(UC_X86_REG_DX), chunk)
            self._set(UC_X86_REG_AX, len(chunk))
            self._cf(False)
        elif ah == 0x40:
            h, n = R(UC_X86_REG_BX), R(UC_X86_REG_CX)
            data = bytes(self.uc.mem_read(R(UC_X86_REG_DS) * 16 + R(UC_X86_REG_DX), n))
            if h in (1, 2):
                self.stdout += data
            elif h in self.handles:
                self.written.setdefault(self.handles[h][2], bytearray()).extend(data)
            self._set(UC_X86_REG_AX, n)
            self._cf(False)
        elif ah == 0x42:
            h = R(UC_X86_REG_BX)
            f = self.handles.get(h)
            off = (R(UC_X86_REG_CX) << 16) | R(UC_X86_REG_DX)
            if f is None:
                self._cf(True)
                return
            if al == 0:
                f[1] = off
            elif al == 1:
                f[1] += off
            else:
                f[1] = len(f[0]) + off
            self._set(UC_X86_REG_AX, f[1] & 0xFFFF)
            self._set(UC_X86_REG_DX, f[1] >> 16)
            self._cf(False)
        elif ah == 0x4E:
            name = self._str_at(R(UC_X86_REG_DS), R(UC_X86_REG_DX))
            p = None if '*' in name or '?' in name else self._find_file(name)
            self.int_log.append(f'FIND {name} -> {p}')
            if p is None:
                self._set(UC_X86_REG_AX, 18)
                self._cf(True)
                return
            seg, off = getattr(self, 'dta', (PSP, 0x80))
            ent = bytearray(43)
            ent[0x15] = 0x20
            struct.pack_into('<I', ent, 0x1A, p.stat().st_size)
            nm = p.name.upper().encode()[:12]
            ent[0x1E:0x1E + len(nm)] = nm
            self.uc.mem_write(seg * 16 + off, bytes(ent))
            self._set(UC_X86_REG_AX, 0)
            self._cf(False)
        elif ah == 0x4F:
            self._set(UC_X86_REG_AX, 18)
            self._cf(True)
        elif ah == 0x4C:
            self.exit_code = al
            self.uc.emu_stop()
        elif ah in (0x09, 0x02, 0x06):
            pass
        else:
            k = f'DOS {ah:02x}'
            self.unknown[k] = self.unknown.get(k, 0) + 1
            self._cf(False)

    # ---------- исполнение ----------
    def run(self, max_insns: int = 50_000_000, until: Optional[Tuple[int, int]] = None) -> str:
        """Исполнять до запроса клавиши / выхода / лимита / until=(abs_seg, off). Возвращает причину."""
        self.need_key = False
        cs, ip = self._reg(UC_X86_REG_CS), self._reg(UC_X86_REG_IP)
        start = cs * 16 + ip
        # until в emu_start ненадёжен (уже транслированные блоки не проверяют адрес) — останов хуком
        stop = until[0] * 16 + until[1] if until else 0xFFFFF
        hook = None
        self._hit_until = False
        if until and start == stop:   # уже стоим на цели — сделать шаг, чтобы ловить следующее попадание
            self.uc.emu_start(start, 0xFFFFF, count=1)
            cs, ip = self._reg(UC_X86_REG_CS), self._reg(UC_X86_REG_IP)
            start = cs * 16 + ip
        if until and start != stop:
            def _stop(uc, address, size, data):
                self._hit_until = True
                uc.emu_stop()
            hook = self.uc.hook_add(UC_HOOK_CODE, _stop, None, stop, stop)
        try:
            self.uc.emu_start(start, 0xFFFFF, count=max_insns)
        except Exception as e:  # noqa: BLE001
            cs, ip = self._reg(UC_X86_REG_CS), self._reg(UC_X86_REG_IP)
            return f'error {e} at {cs:04x}:{ip:04x}'
        finally:
            if hook is not None:
                self.uc.hook_del(hook)
        if self.exit_code is not None:
            return 'exit'
        if self.need_key:
            return 'key'
        cs, ip = self._reg(UC_X86_REG_CS), self._reg(UC_X86_REG_IP)
        if until and self._hit_until and (cs * 16 + ip) == stop:
            return 'until'
        return 'limit'

    def where(self) -> str:
        cs, ip = self._reg(UC_X86_REG_CS), self._reg(UC_X86_REG_IP)
        return f'{cs:04x}:{ip:04x} (ghidra {self.to_ghidra(cs):04x}:{ip:04x})'

    def to_ghidra(self, abs_seg: int) -> int:
        for g, a in self.ovl_seg_map.items():
            if a == abs_seg:
                return g
        return abs_seg - LOAD + GHIDRA_BASE

    def ghidra_abs(self, gseg: int) -> int:
        return self.ovl_seg_map.get(gseg, gseg - GHIDRA_BASE + LOAD)

    # ---------- память ----------
    @property
    def ds(self) -> int:
        return DS_REL + LOAD

    def rd(self, off: int, n: int) -> bytes:
        return bytes(self.uc.mem_read(self.ds * 16 + off, n))

    def rw(self, off: int) -> int:
        return struct.unpack('<H', self.rd(off, 2))[0]

    def ww(self, off: int, v: int):
        self.uc.mem_write(self.ds * 16 + off, struct.pack('<H', v & 0xFFFF))

    def vram(self) -> bytes:
        return bytes(self.uc.mem_read(VGA * 16, 64000))

    def save_png(self, path: Path, scale: int = 2):
        px = self.vram()
        pal = [tuple(min(255, c * 255 // 63) for c in p) for p in self.palette]
        w, h = 320 * scale, 200 * scale
        raw = bytearray()
        for y in range(h):
            raw.append(0)
            row = px[(y // scale) * 320:(y // scale) * 320 + 320]
            for x in range(w):
                raw += bytes(pal[row[x // scale]])
        def chunk(t, d):
            c = struct.pack('>I', len(d)) + t + d
            return c + struct.pack('>I', zlib.crc32(t + d) & 0xFFFFFFFF)
        png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
        png += chunk(b'IDAT', zlib.compress(bytes(raw), 6)) + chunk(b'IEND', b'')
        Path(path).parent.mkdir(parents=True, exist_ok=True)
        Path(path).write_bytes(png)


def key(ch: str) -> int:
    """ASCII-клавиша -> слово INT16."""
    special = {'\r': 0x1C0D, ' ': 0x3920, '\x1b': 0x011B}
    if ch in special:
        return special[ch]
    return ord(ch)


KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT = 0x4800, 0x5000, 0x4B00, 0x4D00
KEY_PGUP, KEY_PGDN = 0x4900, 0x5100


if __name__ == '__main__':
    g = Game()
    for i in range(6):
        r = g.run(30_000_000)
        print(i, r, g.where(), 'unknown', g.unknown)
        print('stdout:', bytes(g.stdout[-300:]))
        if r != 'limit':
            break


def text_screen(g: 'Game') -> str:
    raw = bytes(g.uc.mem_read(0xB8000, 4000))
    lines = [''.join(chr(raw[(r * 80 + c) * 2]) for c in range(80)).rstrip() for r in range(25)]
    return '\n'.join(l for l in lines if l.strip())
