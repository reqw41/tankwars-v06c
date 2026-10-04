#!/usr/bin/env python3
"""Заставка оригинала (кадр игры docs/img/orig-title.png: 320×200, 256 цветов VGA) -> экран Вектора: 256×160 по центру, 8 цветов из палитры
R3G3B2, три плоскости A000/C000/E000 одним куском 24576 байт (сжимается ZX0) и палитра.
  v06c/tools/title2planes.py [--dither] [--preview файл.png]
Пишет v06c/build/title.bin, v06c/src/title_pal.inc."""
import sys, random
from pathlib import Path
from PIL import Image
ROOT = Path(__file__).resolve().parents[2]
# источник — кадр настоящей игры (заставка = картинка BOMB1.RAW + надписи, которые игра рисует поверх): 640×400, точки удвоены
src = Image.open(ROOT / 'docs/img/orig-title.png').convert('RGB').resize((320, 200), Image.NEAREST)
W, H, Y0 = 256, 160, 48
img = src.resize((W, H), Image.LANCZOS)
px = list(img.getdata())
def v332(c):   # ближайший цвет палитры Вектора: R 0..7, G 0..7, B 0..3
    return (round(c[0] / 255 * 7), round(c[1] / 255 * 7), round(c[2] / 255 * 3))
def to_rgb(q): return (q[0] * 255 // 7, q[1] * 255 // 7, q[2] * 255 // 3)
# k-средних на 8 цветов; чёрный закреплён цветом 0 — им залит остальной экран и бордюр
random.seed(1)
cent = [(0, 0, 0)] + random.sample(px, 7)
dist = lambda a, b: 2 * (a[0] - b[0]) ** 2 + 4 * (a[1] - b[1]) ** 2 + 3 * (a[2] - b[2]) ** 2
for _ in range(25):
    sums = [[0, 0, 0, 0] for _ in cent]
    for p in px[::3]:
        k = min(range(8), key=lambda i: dist(p, cent[i])); s = sums[k]; s[0] += p[0]; s[1] += p[1]; s[2] += p[2]; s[3] += 1
    cent = [(0, 0, 0)] + [tuple(s[j] / s[3] for j in range(3)) if s[3] else cent[i] for i, s in enumerate(sums)][1:]
palv = [v332(c) for c in cent]; palrgb = [to_rgb(q) for q in palv]
dither = '--dither' in sys.argv
buf = [list(map(float, p)) for p in px]; out = [0] * (W * H)
for y in range(H):
    for x in range(W):
        o = y * W + x; p = buf[o]
        k = min(range(8), key=lambda i: dist(p, palrgb[i])); out[o] = k
        if dither:
            e = [(p[j] - palrgb[k][j]) * 0.6 for j in range(3)]
            for dx, dy, w in ((1, 0, 7 / 16), (-1, 1, 3 / 16), (0, 1, 5 / 16), (1, 1, 1 / 16)):
                X, Y = x + dx, y + dy
                if 0 <= X < W and Y < H:
                    q = buf[Y * W + X]
                    for j in range(3): q[j] += e[j] * w
mem = bytearray(24576)
for y in range(H):
    for x in range(W):
        c = out[y * W + x]; off = (x >> 3) * 256 + (255 - (y + Y0)); m = 0x80 >> (x & 7)
        for b in range(3):
            if c >> b & 1: mem[b * 8192 + off] |= m
(ROOT / 'v06c/build').mkdir(exist_ok=True)
(ROOT / 'v06c/build/title.bin').write_bytes(mem)
(ROOT / 'v06c/src/title_pal.inc').write_text('; палитра заставки (title2planes.py): цвета 0..7, байт BBGGGRRR\n\tdb\t' + ', '.join('0x%02X' % (q[2] << 6 | q[1] << 3 | q[0]) for q in palv) + '\n')
if '--preview' in sys.argv:
    pv = Image.new('RGB', (W, 256)); pv.putdata([(0, 0, 0)] * (W * Y0) + [palrgb[k] for k in out] + [(0, 0, 0)] * (W * (256 - Y0 - H)))
    pv.resize((512, 512), Image.NEAREST).save(sys.argv[sys.argv.index('--preview') + 1])
print('палитра', palv)
