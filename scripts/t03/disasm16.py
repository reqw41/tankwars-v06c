#!/usr/bin/env python3
"""Дизассемблер для адресов Ghidra (seg:off) по релоцированному образу. usage: disasm16.py SEG:OFF [N|end]"""
import sys, csv, re
from pathlib import Path
from capstone import Cs, CS_ARCH_X86, CS_MODE_16
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
from emu16 import relocated_image

def names():
    n = {}
    for f in [ROOT / "re/rtl/rtl_names.csv", *sorted((ROOT / "re/game").glob("names_*.csv"))]:
        for r in csv.DictReader(open(f), delimiter=";"):
            n[r["address"].lower()] = r["name"]
    return n

def dis(seg, off, count=200, stop_ret=True):
    img = relocated_image(); nm = names()
    base = (seg - 0x1000) * 16
    md = Cs(CS_ARCH_X86, CS_MODE_16)
    code = img[base + off: base + off + 0x3000]
    out = []
    for i, ins in enumerate(md.disasm(code, off)):
        s = f"{seg:04x}:{ins.address:04x}  {ins.bytes.hex():14} {ins.mnemonic} {ins.op_str}"
        m = re.match(r"0x([0-9a-f]+):0x([0-9a-f]+)", ins.op_str)
        if ins.mnemonic == "lcall" and m:
            k = f"{int(m[1],16):04x}:{int(m[2],16):04x}"; s += f"   ; {nm.get(k, '')}"
        out.append(s)
        if (stop_ret and ins.mnemonic in ("retf", "ret") and i > 3) or i >= count:
            break
    return out

if __name__ == "__main__":
    s, o = (int(x, 16) for x in sys.argv[1].split(":"))
    n = int(sys.argv[2]) if len(sys.argv) > 2 and sys.argv[2] != "all" else 400
    print("\n".join(dis(s, o, n, stop_ret=not (len(sys.argv) > 3))))
