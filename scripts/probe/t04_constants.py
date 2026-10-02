"""Константы T04 из образа: множества оружия и цены. Числа для отчёта — отсюда."""
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'scripts'))
from emu16 import relocated_image  # noqa: E402

img = relocated_image()


def members(seg, off, n=32):
    b = img[(seg - 0x1000) * 16 + off:(seg - 0x1000) * 16 + off + n]
    return [i for i in range(n * 8) if b[i // 8] & (1 << (i % 8))]


def longs(seg_ds, off, count):
    b = img[(0x1E0D - 0x1000) * 16 + off:]
    return [struct.unpack_from('<i', b, 4 * i)[0] for i in range(count)]


def words(off, count):
    b = img[(0x1E0D - 0x1000) * 16 + off:]
    return [struct.unpack_from('<H', b, 2 * i)[0] for i in range(count)]


print('set 318e:0000 standard', members(0x318E, 0x0000))
print('set 318e:0020 cri', members(0x318E, 0x0020))
print('set 318e:0040 tank colors', members(0x318E, 0x0040))
print('set 318e:0060 cri D', members(0x318E, 0x0060))
print('set 318e:0080 sonic', members(0x318E, 0x0080))
print('set 318e:00a0 dirt', members(0x318E, 0x00A0))
print('set 318e:00c0 xdirt', members(0x318E, 0x00C0))
print('set 2583:24f1 flight', members(0x2583, 0x24F1))
print('set 2583:2511 laser', members(0x2583, 0x2511))
print('set 2583:0180 herb', members(0x2583, 0x0180))
print('set 2583:01a0 vick', members(0x2583, 0x01A0))
print('guidance prices 2F8C', longs(0x1E0D, 0x2F8C, 2), 'counts 2F94', words(0x2F94, 2))
print('shield prices 3398', longs(0x1E0D, 0x3398, 2), 'words 33A0', words(0x33A0, 4))
