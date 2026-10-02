#!/usr/bin/env python3
"""Склеивает Turbo Pascal 6 EXE + .OVR (FBOV) в один «плоский» MZ для статического анализа.

Каждый оверлей дописывается в конец образа как отдельный сегмент, его фиксапы
становятся MZ-релокациями, а входы заглушек (CD 3F off 00) заменяются на
JMP FAR newseg:off. Запускать полученный EXE нельзя (BSS перекрывается), только анализ.

usage: flatten_ovr.py BOMB.EXE BOMB.OVR out.exe [map.txt]
"""
import struct, sys

exe = open(sys.argv[1], 'rb').read()
ovr = open(sys.argv[2], 'rb').read()
assert ovr[:4] == b'FBOV'

(last, pages, nrel, hdrpar, minalloc, maxalloc, ss, sp, csum, ip, cs,
 reloff, ovlno) = struct.unpack('<13H', exe[2:28])
size = (pages - 1) * 512 + (last or 512)
img = bytearray(exe[hdrpar * 16:size])
relocs = [struct.unpack('<HH', exe[reloff + 4 * i:reloff + 4 * i + 4]) for i in range(nrel)]

# поиск настоящих заглушек: CD 3F на границе параграфа с корректным заголовком
stubs = []
for p in range(0, len(img), 16):
    if img[p:p + 2] != b'\xcd\x3f':
        continue
    save, fo, csz, fsz, nent = struct.unpack('<HIHHH', img[p + 2:p + 14])
    if not (8 <= fo and fo + csz + fsz <= len(ovr) and csz > 0 and fsz % 2 == 0 and 0 < nent < 200):
        continue
    ents = img[p + 32:p + 32 + 5 * nent]
    if not all(ents[5 * i:5 * i + 2] == b'\xcd\x3f' for i in range(nent)):
        continue
    stubs.append((p // 16, fo, csz, fsz, nent))

# ожидаем, что оверлеи покрывают OVR подряд
cover = sorted((fo, fo + csz + fsz) for _, fo, csz, fsz, _ in stubs)
pos = 8
for a, b in cover:
    assert a == pos, (hex(a), hex(pos))
    pos = b
assert pos == len(ovr), (hex(pos), hex(len(ovr)))

mp = []
for stubseg, fo, csz, fsz, nent in stubs:
    while len(img) % 16:
        img.append(0)
    newseg = len(img) // 16
    img += ovr[fo:fo + csz]
    for (fx,) in struct.iter_unpack('<H', ovr[fo + csz:fo + csz + fsz]):
        relocs.append((fx, newseg))
    for i in range(nent):
        e = stubseg * 16 + 32 + 5 * i
        off = struct.unpack('<H', img[e + 2:e + 4])[0]
        img[e:e + 5] = b'\xea' + struct.pack('<HH', off, newseg)
        relocs.append((32 + 5 * i + 3, stubseg))
        mp.append(f'stub {stubseg:04x}:{32 + 5 * i:04x} -> {newseg:04x}:{off:04x}')
    mp.insert(len(mp) - nent, f'ovl stub {stubseg:04x} ovr@{fo:06x} code {csz} -> seg {newseg:04x}')

while len(img) % 16:
    img.append(0)
hdrsize = 0x1c + 4 * len(relocs)
hdrpar2 = (hdrsize + 15) // 16
hdr = bytearray(hdrpar2 * 16)
total = hdrpar2 * 16 + len(img)
hdr[0:2] = b'MZ'
struct.pack_into('<13H', hdr, 2, total % 512, (total + 511) // 512, len(relocs), hdrpar2,
                 minalloc, maxalloc, ss, sp, 0, ip, cs, 0x1c, 0)
for i, (o, s) in enumerate(relocs):
    struct.pack_into('<HH', hdr, 0x1c + 4 * i, o, s)
open(sys.argv[3], 'wb').write(hdr + img)
print(f'{len(stubs)} overlays, {len(relocs)} relocs, image {len(img)} bytes')
if len(sys.argv) > 4:
    open(sys.argv[4], 'w').write('\n'.join(mp) + '\n')
