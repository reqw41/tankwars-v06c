"""Execution tests for Graph/GraphWrap via unicorn + VGA256 driver."""
from __future__ import annotations

import math
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from emu16 import DS_SEG, diff_bbox, pascal_string  # noqa: E402
from graph_env import (  # noqa: E402
    GRAPH,
    WRAP,
    call_driver,
    clear_vram,
    gcall,
    make_graph_emu,
)
from real48 import float_to_regs, regs_to_float  # noqa: E402


def push_real(x: float):
    ax, bx, dx = float_to_regs(x)
    return [dx, bx, ax]


def set_fill(emu, pattern=1, color=14):
    gcall(emu, 0x1131, [pattern, color])


# ---- drawing ----
def test_putpixel():
    emu = make_graph_emu()
    clear_vram(emu)
    gcall(emu, 0x1DC2, [5])
    gcall(emu, 0x1FE4, [10, 20, 5])
    assert emu.pixel(10, 20) == 5


def test_getpixel():
    emu = make_graph_emu()
    emu.set_pixel(15, 25, 9)
    r = gcall(emu, 0x1FCC, [15, 25])
    assert (r["ax"] & 0xFF) == 9


def test_setcolor_getcolor():
    emu = make_graph_emu()
    gcall(emu, 0x1DC2, [11])
    assert emu.read_u16(DS_SEG, 0xE660) == 11
    assert (gcall(emu, 0x1241)["ax"] & 0xFF) == 11


def test_line():
    emu = make_graph_emu()
    clear_vram(emu)
    gcall(emu, 0x1DC2, [4])
    gcall(emu, 0x1C86, [20, 10, 80, 50])
    assert emu.pixel(20, 10) == 4
    assert emu.pixel(80, 50) == 4
    bb = diff_bbox(bytes(64000), emu.vram())
    assert bb == (20, 10, 80, 50, 61)


def test_bar():
    emu = make_graph_emu()
    clear_vram(emu)
    set_fill(emu, 1, 14)
    gcall(emu, 0x1CCE, [10, 10, 50, 40])
    assert emu.pixel(20, 20) == 14
    bb = diff_bbox(bytes(64000), emu.vram())
    # inclusive 41×31 = 1271
    assert bb == (10, 10, 50, 40, 1271)


def test_rectangle_outline():
    emu = make_graph_emu()
    clear_vram(emu)
    gcall(emu, 0x1DC2, [3])
    gcall(emu, 0x10D2, [30, 20, 90, 60])
    assert emu.pixel(30, 20) == 3
    assert emu.pixel(60, 40) == 0


def test_circle():
    """1827:11ea Circle(x,y,r). VGA256 SI=14 is a stub; graph_env hooks it to rasterize."""
    emu = make_graph_emu()
    clear_vram(emu)
    gcall(emu, 0x1DC2, [14])
    # args push x,y,r → [bp+6]=r [bp+8]=y [bp+0a]=x
    gcall(emu, 0x11EA, [100, 80, 15])
    bb = diff_bbox(bytes(64000), emu.vram())
    assert bb is not None and bb[4] >= 50
    assert emu.pixel(115, 80) == 14  # right
    assert emu.pixel(85, 80) == 14  # left
    assert emu.pixel(100, 80) == 0  # center empty
    ent, _ = emu._driver
    assert emu.read_u16(ent, 0x77) == 100 and emu.read_u16(ent, 0x79) == 80


def test_settextstyle():
    """1827:1496 SetTextStyle(font,dir,charsize). font=0 → no INT21, stores E6AE/E6B0/E6B2."""
    emu = make_graph_emu()
    n = len(emu.int_log)
    # stdcall (charsize,dir,font)=(1,0,0) → push font,dir,size
    gcall(emu, 0x1496, [0, 0, 1])
    assert emu.read_u16(DS_SEG, 0xE6AE) == 0  # font
    assert emu.read_u16(DS_SEG, 0xE6B0) == 0  # direction
    assert emu.read_u16(DS_SEG, 0xE6B2) == 1  # charsize
    assert emu.read_u16(DS_SEG, 0xE63A) == 0
    assert not any(x.startswith("INT21") for x in emu.int_log[n:])
    gcall(emu, 0x1496, [0, 0, 4])
    assert emu.read_u16(DS_SEG, 0xE6B2) == 4


def test_setusercharsize():
    """1827:16e3 SetUserCharSize — clears E6B2; changes TextWidth via driver [7b]."""
    emu = make_graph_emu()
    emu.write_bytes(DS_SEG, 0x4000, pascal_string("Hello"))
    w0 = gcall(emu, 0x1F9B, [DS_SEG, 0x4000])["ax"]
    assert w0 == 40
    gcall(emu, 0x16E3, [8, 8, 8, 8])
    assert emu.read_u16(DS_SEG, 0xE6B2) == 0
    assert gcall(emu, 0x1F9B, [DS_SEG, 0x4000])["ax"] == 40
    # width 16: push so BX (DivX slot in 1f7e) = 16 → args [8,16,8,16]
    gcall(emu, 0x16E3, [8, 16, 8, 16])
    assert gcall(emu, 0x1F9B, [DS_SEG, 0x4000])["ax"] == 80


def test_inttostr():
    """175e:0293 IntToStr(LongInt → Pascal string). Hidden result far ptr; retf 4 cleans LongInt."""
    emu = make_graph_emu()
    buf = 0x4400
    emu.write_bytes(DS_SEG, buf, bytes(32))
    # push result_seg, result_off, long_hi, long_lo
    gcall(emu, 0x0293, [DS_SEG, buf, 0, 12345], seg=WRAP)
    s = emu.read_bytes(DS_SEG, buf, 16)
    assert s[0] == 5 and s[1:6] == b"12345"
    emu.write_bytes(DS_SEG, buf, bytes(32))
    gcall(emu, 0x0293, [DS_SEG, buf, 0xFFFF, (-7) & 0xFFFF], seg=WRAP)
    s = emu.read_bytes(DS_SEG, buf, 16)
    assert s[0] == 2 and s[1:3] == b"-7"


def test_outtextxy():
    emu = make_graph_emu()
    clear_vram(emu)
    gcall(emu, 0x1DC2, [15])
    emu.write_bytes(DS_SEG, 0x4000, pascal_string("Hi"))
    gcall(emu, 0x1F12, [100, 50, DS_SEG, 0x4000])
    bb = diff_bbox(bytes(64000), emu.vram())
    assert bb is not None and bb[4] > 0


def test_outtext_at_cp():
    emu = make_graph_emu()
    clear_vram(emu)
    gcall(emu, 0x1DC2, [15])
    call_driver(emu, 0x08, ax=50, bx=40)
    emu.write_bytes(DS_SEG, 0x4000, pascal_string("OT"))
    gcall(emu, 0x13F2, [DS_SEG, 0x4000])
    bb = diff_bbox(bytes(64000), emu.vram())
    assert bb is not None and bb[4] > 0


def test_textwidth():
    emu = make_graph_emu()
    emu.write_bytes(DS_SEG, 0x4000, pascal_string("Hello"))
    r = gcall(emu, 0x1F9B, [DS_SEG, 0x4000])
    assert r["ax"] == 40


def test_moveto_getx():
    emu = make_graph_emu()
    gcall(emu, 0x1042, [123, 45])
    assert emu.read_u16(DS_SEG, 0xE666) == 123
    assert emu.read_u16(DS_SEG, 0xE668) == 45
    assert gcall(emu, 0x105F)["ax"] == 123


def test_getmax():
    emu = make_graph_emu()
    assert gcall(emu, 0x1072)["ax"] == 319
    assert gcall(emu, 0x1085)["ax"] == 199


def test_setviewport():
    emu = make_graph_emu()
    gcall(emu, 0x0F93, [10, 20, 250, 150, 1])
    assert [emu.read_u16(DS_SEG, a) for a in (0xE674, 0xE676, 0xE678, 0xE67A)] == [
        10,
        20,
        250,
        150,
    ]


def test_setfillstyle_getfillsettings():
    emu = make_graph_emu()
    gcall(emu, 0x1131, [3, 7])
    assert emu.read_u16(DS_SEG, 0xE684) == 3
    assert emu.read_u16(DS_SEG, 0xE686) == 7
    buf = 0x4100
    gcall(emu, 0x1119, [DS_SEG, buf])
    assert emu.read_u16(DS_SEG, buf) == 3
    assert emu.read_u16(DS_SEG, buf + 2) == 7


def test_settextjustify():
    emu = make_graph_emu()
    gcall(emu, 0x1454, [2, 1])
    assert emu.read_u16(DS_SEG, 0xE6B4) == 2
    assert emu.read_u16(DS_SEG, 0xE6B6) == 1


def test_graphresult():
    emu = make_graph_emu()
    emu.write_u16(DS_SEG, 0xE63A, 0x1234)
    r = gcall(emu, 0x04F3)
    assert r["ax"] == 0x1234
    assert emu.read_u16(DS_SEG, 0xE63A) == 0


def test_grapherrormsg():
    emu = make_graph_emu()
    buf = 0x4300
    emu.write_bytes(DS_SEG, buf, bytes(64))
    gcall(emu, 0x027E, [DS_SEG, buf, 0])
    s = emu.read_bytes(DS_SEG, buf, 20)
    assert s[0] > 0
    assert b"error" in s[1 : 1 + s[0]].lower() or s[1:1 + s[0]] == b"No error"


def test_closegraph():
    emu = make_graph_emu()
    gcall(emu, 0x0EB5)
    assert emu.read_u16(DS_SEG, 0xE670) == 0


def test_getimage():
    emu = make_graph_emu()
    clear_vram(emu)
    set_fill(emu, 1, 5)
    gcall(emu, 0x1CCE, [10, 10, 20, 20])
    buf = 0x4200
    gcall(emu, 0x1FFB, [10, 10, 20, 20, DS_SEG, buf])
    w, h = emu.read_u16(DS_SEG, buf), emu.read_u16(DS_SEG, buf + 2)
    assert w in (10, 11) and h in (10, 11)


def test_setaspectratio():
    emu = make_graph_emu()
    gcall(emu, 0x192B, [0x200, 0x100])
    assert emu.read_u16(DS_SEG, 0xE66C) == 0x200
    assert emu.read_u16(DS_SEG, 0xE66E) == 0x100


def test_cleardevice_moveto0():
    emu = make_graph_emu()
    gcall(emu, 0x1042, [50, 50])
    gcall(emu, 0x0F80)
    assert emu.read_u16(DS_SEG, 0xE666) == 0
    assert emu.read_u16(DS_SEG, 0xE668) == 0


def test_setlinestyle():
    emu = make_graph_emu()
    gcall(emu, 0x1E4A, [0, 0, 1, 0])
    # returns without crash; SI=1Ah


def test_initgraph_driver_ptr():
    emu = make_graph_emu()
    assert emu.read_u16(DS_SEG, 0xE644) != 0  # driver segment wired


# ---- GraphWrap ----
def test_hypot():
    emu = make_graph_emu()
    r = gcall(emu, 0x0088, push_real(3.0) + push_real(4.0), seg=WRAP)
    assert abs(regs_to_float(r["ax"], r["bx"], r["dx"]) - 5.0) < 1e-4


def test_degtorad():
    emu = make_graph_emu()
    r = gcall(emu, 0x00DA, push_real(180.0), seg=WRAP)
    assert abs(regs_to_float(r["ax"], r["bx"], r["dx"]) - math.pi) < 1e-4


def test_radtodeg():
    emu = make_graph_emu()
    r = gcall(emu, 0x0124, push_real(math.pi), seg=WRAP)
    assert abs(regs_to_float(r["ax"], r["bx"], r["dx"]) - 180.0) < 1e-3


def test_mouse_x_div2():
    emu = make_graph_emu()
    emu.mouse_x = 160
    assert gcall(emu, 0x0190, seg=WRAP)["ax"] == 80


def test_mouse_get_y():
    emu = make_graph_emu()
    emu.mouse_y = 123
    assert gcall(emu, 0x01CC, seg=WRAP)["ax"] == 123


# Distinct Graph/GraphWrap entry points in this file (≥30):
# 1fe4 PutPixel, 1fcc GetPixel, 1dc2 SetColor, 1241 GetColor, 1c86 Line, 1cce Bar,
# 10d2 Rectangle, 11ea Circle, 1f12 OutTextXY, 13f2 OutText, 1f9b TextWidth,
# 1042 MoveTo, 105f GetX, 1072 GetMaxX, 1085 GetMaxY, 0f93 SetViewPort,
# 1131 SetFillStyle, 1119 GetFillSettings, 1454 SetTextJustify, 1496 SetTextStyle,
# 16e3 SetUserCharSize, 04f3 GraphResult, 027e GraphErrorMsg, 0eb5 CloseGraph,
# 1ffb GetImage, 192b SetAspectRatio, 0f80 ClearDevice_MoveTo0, 1e4a SetLineStyle,
# 0bae/E642 InitGraph driver, 175e:0088 Hypot, 00da DegToRad, 0124 RadToDeg,
# 0190 MouseX_div2, 01cc MouseGetY, 0293 IntToStr
# = 35 entry points
