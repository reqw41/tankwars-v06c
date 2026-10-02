#!/usr/bin/env python3
"""Coverage: share of game→library far-call sites whose targets are named in rtl_names.csv.

Game segment bounds come from re/ovl_map.txt (overlay code sizes) plus full
resident ranges 1000→1035 and 1062→1632 (not truncated to last FUN_ end).
"""
from __future__ import annotations

import argparse
import collections
import csv
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FLAT = ROOT / "re" / "bomb25_flat.exe"
FUNCS = ROOT / "re" / "export" / "functions.txt"
CSV = ROOT / "re" / "rtl" / "rtl_names.csv"
OVL_MAP = ROOT / "re" / "ovl_map.txt"

LOAD = 0x1000
LIB_SEGS = {
    0x1637,
    0x1651,
    0x166F,
    0x1691,
    0x175E,
    0x17A3,
    0x17AF,
    0x17C5,
    0x1827,
    0x1BE7,
    0x1C5B,
}


def load_image():
    raw = FLAT.read_bytes()
    hdr = struct.unpack_from("<H", raw, 8)[0] * 16
    nreloc = struct.unpack_from("<H", raw, 6)[0]
    reloff = struct.unpack_from("<H", raw, 0x18)[0]
    img = bytearray(raw[hdr:])
    for i in range(nreloc):
        off, seg = struct.unpack_from("<HH", raw, reloff + 4 * i)
        pos = seg * 16 + off
        if pos + 1 < len(img):
            val = struct.unpack_from("<H", img, pos)[0]
            struct.pack_into("<H", img, pos, (val + LOAD) & 0xFFFF)
    return bytes(img)


def game_ranges():
    """List of (ghidra_seg_start, ghidra_seg_end_exclusive) for game code."""
    ranges = [(0x1000, 0x1035), (0x1062, 0x1632)]
    for line in OVL_MAP.read_text().splitlines():
        if not line.startswith("ovl stub"):
            continue
        parts = line.split()
        # ovl stub XXXX ovr@... code NNNN -> seg SSSS
        size = int(parts[5])
        seg = int(parts[-1], 16)
        gseg = seg + LOAD
        paras = (size + 15) // 16
        ranges.append((gseg, gseg + paras))
    return ranges


def export_names():
    names = {}
    if not FUNCS.exists():
        return names
    for line in FUNCS.read_text().splitlines():
        addr, sz, name = line.split("\t")
        names[addr.lower()] = name
    return names


def csv_names():
    named = set()
    with CSV.open(newline="") as f:
        for row in csv.DictReader(f, delimiter=";"):
            named.add(row["address"].lower())
    return named


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    img = load_image()
    ranges = game_ranges()
    exp = export_names()
    csvn = csv_names()

    def is_named(seg, off):
        key = f"{seg:04x}:{off:04x}"
        if key in csvn:
            return True
        n = exp.get(key, "")
        if not n:
            return False
        if n.startswith("FUN_") or n.startswith("thunk_FUN_"):
            return False
        return True

    calls = collections.Counter()
    for a, b in ranges:
        start = (a - LOAD) * 16
        end = (b - LOAD) * 16
        i = start
        while i < min(end, len(img)) - 5:
            if img[i] == 0x9A:
                off, tseg = struct.unpack_from("<HH", img, i + 1)
                if tseg in LIB_SEGS:
                    calls[(tseg, off)] += 1
                i += 5
                continue
            i += 1

    total = sum(calls.values())
    named_n = 0
    unnamed = []
    for (seg, off), c in calls.items():
        if is_named(seg, off):
            named_n += c
        else:
            unnamed.append((c, seg, off, exp.get(f"{seg:04x}:{off:04x}", "?")))

    unnamed.sort(reverse=True)
    pct = 100.0 * named_n / total if total else 0.0

    print(f"game ranges: {len(ranges)} (from ovl_map + resident)")
    print(f"game→lib far calls: {total}")
    print(f"named call-sites:   {named_n}")
    print(f"coverage:           {pct:.2f}%")
    print(f"unique unnamed targets: {len(unnamed)}")
    print("top unnamed:")
    for c, seg, off, name in unnamed[:30]:
        print(f"  {c:4d}  {seg:04x}:{off:04x}  {name}")

    if args.json:
        import json

        print(
            json.dumps(
                {
                    "total": total,
                    "named": named_n,
                    "coverage_pct": pct,
                    "unnamed": [
                        {"count": c, "addr": f"{s:04x}:{o:04x}", "name": n}
                        for c, s, o, n in unnamed
                    ],
                }
            )
        )
    return 0 if pct >= 95.0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
