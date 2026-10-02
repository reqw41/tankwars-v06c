#!/usr/bin/env python3
"""Coverage: share of game→library far-call sites whose targets are named in rtl_names.csv."""
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
GAME_SEGS = {
    0x1000,
    0x1062,
    0x2185,
    0x21EE,
    0x224B,
    0x2583,
    0x285C,
    0x2B39,
    0x2CAB,
    0x2EEF,
    0x30B8,
    0x318E,
    0x32EC,
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


def g2i(seg, off):
    return (seg - LOAD) * 16 + off


def seg_ends():
    ends = collections.defaultdict(int)
    for line in FUNCS.read_text().splitlines():
        addr, sz, name = line.split("\t")
        s, o = (int(x, 16) for x in addr.split(":"))
        ends[s] = max(ends[s], o + int(sz))
        # also track names currently exported
    return ends


def export_names():
    names = {}
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
    ends = seg_ends()
    exp = export_names()
    csvn = csv_names()

    # A target is "named" if CSV has it OR export name does not look like FUN_/thunk_FUN_
    def is_named(seg, off):
        key = f"{seg:04x}:{off:04x}"
        if key in csvn:
            return True
        n = exp.get(key, "")
        if not n:
            # also accept if any function starts at this addr with non-FUN name in export
            return False
        if n.startswith("FUN_") or n.startswith("thunk_FUN_"):
            return False
        return True

    calls = collections.Counter()  # (seg,off) -> count
    for gs in sorted(GAME_SEGS):
        start = g2i(gs, 0)
        end = start + ends.get(gs, 0x1000)
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
    sys.path.insert(0, str(ROOT / "scripts"))
    raise SystemExit(main())
