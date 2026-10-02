"""Генератор случайных чисел Turbo Pascal 6 (System 1c5b:1639/15ea/1600), побитно.

RandSeed (DS:3774, LongInt):  seed = seed * 0x08088405 + 1  (mod 2^32)
Random(n) (1c5b:15ea):        (seed >> 16) mod n   — остаток DIV, не старшее слово произведения; n=0 -> 0
Random    (1c5b:1600):        seed / 2^32, нормализовано в Real48 без потерь (32 бита мантиссы)
"""
MULT = 0x08088405


class TPRandom:
    def __init__(self, seed: int):
        self.seed = seed & 0xFFFFFFFF

    def _next(self) -> int:
        self.seed = (self.seed * MULT + 1) & 0xFFFFFFFF
        return self.seed

    def word(self, n: int) -> int:
        hi = self._next() >> 16
        return hi % n if n else 0

    def real(self) -> float:
        return self._next() / 4294967296.0
