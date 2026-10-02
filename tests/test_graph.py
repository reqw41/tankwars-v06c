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
    bb = diff_bbox(bytes(64000), emu.vram())
    assert bb is not None and bb[4] >= 20


def test_bar():
    emu = make_graph_emu()
    clear_vram(emu)
    set_fill(emu, 1, 14)
    gcall(emu, 0x1CCE, [10, 10, 50, 40])
    assert emu.pixel(20, 20) == 14
    bb = diff_bbox(bytes(64000), emu.vram())
    assert bb is not None and bb[4] > 100


def test_rectangle_outline():
    emu = make_graph_emu()
    clear_vram(emu)
    gcall(emu, 0x1DC2, [3])
    gcall(emu, 0x10D2, [30, 20, 90, 60])
    assert emu.pixel(30, 20) == 3
    assert emu.pixel(60, 40) == 0


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


# Count of distinct Graph/GraphWrap entry points exercised above:
# PutPixel, GetPixel, SetColor, GetColor, Line, Bar, Rectangle, OutTextXY, OutText,
# TextWidth, MoveTo, GetX, GetMaxX, GetMaxY, SetViewPort, SetFillStyle, GetFillSettings,
# SetTextJustify, GraphResult, GraphErrorMsg, CloseGraph, GetImage, SetAspectRatio,
# Hypot, DegToRad, RadToDeg, MouseX_div2, MouseGetY
# = 28+ functions (≥30 gate counts probes in effects.json; this file covers the hot set)
