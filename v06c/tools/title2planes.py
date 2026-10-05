#!/usr/bin/env python3
"""Заставка оригинала -> экран Вектора: 256×160 по центру, 16 цветов из палитры R3G3B2, четыре плоскости.
Источник — кадр настоящей игры docs/img/orig-title.png (картинка BOMB1.RAW + буквы TANK WARS, которые игра рисует
поверх); строки с копирайтом берутся из самой BOMB1.RAW — без надписи.
  v06c/tools/title2planes.py [--dither сила] [--despeckle] [--preview файл.png]
Пишет v06c/build/title.bin (весь экран: плоскости 8000/A000/C000/E000, 32768 байт) и v06c/src/title_pal.inc
(16 байт BBGGGRRR по номеру регистра палитры).
Номер регистра точки: бит 3 — плоскость 8000, бит 2 — A000, бит 1 — C000, бит 0 — E000 (как в pal_out)."""
import re, sys
from pathlib import Path
import numpy as np
from PIL import Image
ROOT = Path(__file__).resolve().parents[2]
W, H, Y0 = 256, 160, 48
COPY_Y = 172                # с этой строки кадра (из 200) — надпись копирайта
TEXT_REG = 6                # регистр самого светлого цвета — им пишется надпись
TEXT, TEXT_COL, TEXT_ROW = 'НАЖМИТЕ ЛЮБУЮ КЛАВИШУ', 5, 27

frame = Image.open(ROOT / 'docs/img/orig-title.png').convert('RGB').resize((320, 200), Image.NEAREST)
raw = (ROOT / 'orig/bomb/BOMB1.RAW').read_bytes()
pic = Image.frombytes('P', (320, 200), raw[:64000]); pic.putpalette([v * 255 // 63 for v in raw[64000:64768]])
frame.paste(pic.convert('RGB').crop((0, COPY_Y, 320, 200)), (0, COPY_Y))
px = np.asarray(frame.resize((W, H), Image.LANCZOS), dtype=np.float64).reshape(-1, 3)

# все 256 цветов Вектора
vec = np.array([[(i & 7) * 255 / 7, (i >> 3 & 7) * 255 / 7, (i >> 6) * 255 / 3] for i in range(256)])
WGT = np.array([2.0, 4.0, 1.5])     # вес каналов в расстоянии
def nearest(points, pal):
    d = (((points[:, None, :] - pal[None, :, :]) ** 2) * WGT).sum(axis=2)
    return d.argmin(axis=1), d.min(axis=1)

# подбор 16 цветов из 256: k-средних для начала, затем замены по одному цвету, пока ошибка падает; чёрный закреплён.
# Считается по гистограмме (цвета точек, округлённые до 5 бит) и готовой таблице расстояний до цветов Вектора.
q, cnt = np.unique((px / 8).round().astype(np.int32), axis=0, return_counts=True)
hp = q * 8.0
D = (((hp[:, None, :] - vec[None, :, :]) ** 2) * WGT).sum(axis=2) * cnt[:, None]
def total(ii): return D[:, ii].min(axis=1).sum()
best = None
for seed in range(6):
    rng = np.random.default_rng(seed)
    cent = np.vstack([[0, 0, 0], hp[rng.choice(len(hp), 15, replace=False, p=cnt / cnt.sum())]])
    for _ in range(30):
        k, _ = nearest(hp, cent)
        for i in range(1, 16):
            if (k == i).any(): cent[i] = np.average(hp[k == i], axis=0, weights=cnt[k == i])
    ids = sorted(set(nearest(cent, vec)[0].tolist()) | {0})
    while len(ids) < 16:
        ids.append(min((c for c in range(256) if c not in ids), key=lambda c: total(ids + [c])))
    cur = total(ids); improved = True
    while improved:
        improved = False
        for j in range(16):
            if ids[j] == 0: continue
            for c in range(256):
                if c in ids: continue
                t = ids[:j] + [c] + ids[j + 1:]; e = total(t)
                if e < cur - 1e-6: ids, cur, improved = t, e, True
    if best is None or cur < best[0]: best = (cur, ids)
ids = best[1]

# регистры: 0 — чёрный, TEXT_REG — самый светлый, остальные по яркости
lum = lambda c: 2 * (c & 7) / 7 + 4 * (c >> 3 & 7) / 7 + (c >> 6) / 3
rest = sorted((c for c in ids if c != 0), key=lum)
light = rest.pop()
regs = [0] * 16; free = [r for r in range(1, 16) if r != TEXT_REG]
regs[TEXT_REG] = light
for r, c in zip(free, rest): regs[r] = c
pal = vec[regs]

strength = float(sys.argv[sys.argv.index('--dither') + 1]) if '--dither' in sys.argv else 0.0
buf = px.reshape(H, W, 3).copy(); out = np.zeros((H, W), dtype=np.uint8)
if strength == 0:
    out = nearest(px, pal)[0].reshape(H, W).astype(np.uint8)
else:
    for y in range(H):
        for x in range(W):
            p = buf[y, x]; k = int((((pal - p) ** 2) * WGT).sum(axis=1).argmin()); out[y, x] = k
            e = (p - pal[k]) * strength
            for dx, dy, w in ((1, 0, 7 / 16), (-1, 1, 3 / 16), (0, 1, 5 / 16), (1, 1, 1 / 16)):
                X, Y = x + dx, y + dy
                if 0 <= X < W and Y < H: buf[Y, X] += e * w

# одиночные точки (не совпадают ни с одним из четырёх соседей) заменяются самым частым соседом: крап переходов
# неба почти не сжимается, а линии букв и танка при этом целы
if '--despeckle' in sys.argv:
    src = out.copy()
    for y in range(H):
        for x in range(W):
            nb = [int(src[Y, X]) for X, Y in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)) if 0 <= X < W and 0 <= Y < H]
            if int(src[y, x]) not in nb: out[y, x] = max(set(nb), key=nb.count)

# весь экран 256×256: картинка в строках Y0..Y0+H-1, под ней надпись шрифтом игры (v06c/src/font.inc) цветом TEXT_REG
scr = np.zeros((256, W), dtype=np.uint8); scr[Y0:Y0 + H] = out
font = [int(v, 16) for v in re.findall(r'0x([0-9a-fA-F]{2})', (ROOT / 'v06c/src/font.inc').read_text())]
for i, ch in enumerate(TEXT):
    for r in range(8):
        g = 64 + ord(ch) - 0x410 if 'А' <= ch <= 'Я' else ord(ch) - 32      # русские прописные — знаки 64..95
        bits = font[g * 8 + r]
        for b in range(8):
            if bits & (0x80 >> b): scr[TEXT_ROW * 8 + r, (TEXT_COL + i) * 8 + b] = TEXT_REG
mem = bytearray(32768)          # с 8000h: плоскости 8000, A000, C000, E000
for y in range(256):
    for x in range(W):
        c = int(scr[y, x])
        if not c: continue
        off = (x >> 3) * 256 + (255 - y); m = 0x80 >> (x & 7)
        for bit, plane in ((3, 0), (2, 1), (1, 2), (0, 3)):
            if c >> bit & 1: mem[plane * 8192 + off] |= m
(ROOT / 'v06c/build').mkdir(exist_ok=True)
(ROOT / 'v06c/build/title.bin').write_bytes(mem)
(ROOT / 'v06c/src/title_pal.inc').write_text('; палитра заставки (title2planes.py): регистры 0..15, байт BBGGGRRR\n\tdb\t' + ', '.join('0x%02X' % c for c in regs) + '\n')
if '--preview' in sys.argv:
    Image.fromarray(pal[scr].round().astype(np.uint8)).resize((512, 512), Image.NEAREST).save(sys.argv[sys.argv.index('--preview') + 1])
print('палитра', ['%02X' % c for c in regs], 'цветов', len(set(regs)), 'ошибка %.0f' % best[0])
