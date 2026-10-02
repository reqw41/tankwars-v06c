"""Покрытие базовых блоков сегмента Ghidra во время одного вызова (для чтения только исполняемого кода)."""
from unicorn import UC_HOOK_BLOCK
from unicorn.x86_const import UC_X86_REG_CS


def with_block_coverage(g, gseg, fn):
    abs_seg = g.ghidra_abs(gseg)
    blocks = {}

    def hb(uc, addr, size, d):
        if uc.reg_read(UC_X86_REG_CS) == abs_seg:
            off = addr - abs_seg * 16
            blocks[off] = blocks.get(off, 0) + 1
    h = g.uc.hook_add(UC_HOOK_BLOCK, hb)
    try:
        res = fn()
    finally:
        g.uc.hook_del(h)
    return res, blocks
