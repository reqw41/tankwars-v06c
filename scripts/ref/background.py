"""Фон поля Tank Wars 2.5 (2eef:0000, вызывается из 2eef:0909 до рельефа).

Номер варианта — DS:8860 (0..5), 6 = Random(6). Каждый вариант рисуется одинаково в экран и в буфер фона
(1691 пишет в сегмент из DS:E3B6, игра подменяет его на буфер). В конце в буфер — рамка цветом 13
(в экран её рисует Graph Rectangle тем же цветом, пиксели те же). Палитра 30..59 анимируется (VRAM не меняется).
  0 пусто (чёрный)
  1 звёзды: 500 раз x=Random(299)+11, y=Random(159)+31, цвет Random(20)+30
  2 полосы: y=31..190, линия x 11..310 цветом (y mod 30)+30
  3 круги: r=0..170, эллипс 1691:025c во вьюпорте (11,31,309,189) в центре (149,79) и (150,79), цвет (r mod 30)+30
  4 «солнце»: линии 1691:08ef из (160,100) к каждой точке края поля, цвет (k mod 30)+30, k — сквозной счётчик
  5 полосы: y=31..190, линия x 11..310 цветом (y-30) div 8 + 30
"""
try:
    from tanks import line, rect
    from explosion import ring
except ImportError:  # pragma: no cover
    from .tanks import line, rect
    from .explosion import ring

VP = (11, 31, 309, 189)


def draw_background(kind: int, rng=None) -> bytearray:
    v = bytearray(64000)
    if kind == 1:
        for _ in range(500):
            x = rng.word(299) + 11
            y = rng.word(159) + 31
            c = rng.word(20) + 30
            v[y * 320 + x] = c
    elif kind == 2:
        for y in range(31, 191):
            line(v, 11, y, 310, y, (y % 30) + 30)
    elif kind == 3:
        for r in range(0, 171):
            ring(v, 149, 79, r, (r % 30) + 30, VP)
            ring(v, 150, 79, r, (r % 30) + 30, VP)
    elif kind == 4:
        k = 0
        def ray(x, y):
            nonlocal k
            line(v, 160, 100, x, y, (k % 30) + 30)
            k += 1
        for x in range(VP[0], VP[2] + 1):
            ray(x, VP[1])
        for y in range(VP[1], VP[3] + 1):
            ray(VP[2], y)
        for x in range(VP[2], VP[0] - 1, -1):
            ray(x, VP[3])
        for y in range(VP[3], VP[1] - 1, -1):
            ray(VP[0], y)
        for x in range(VP[0], (VP[2] + VP[0]) // 2 + 1):
            ray(x, VP[1])
    elif kind == 5:
        for y in range(31, 191):
            line(v, 11, y, 310, y, (y - 30) // 8 + 30)
    rect(v, 8, 28, 312, 192, 13)
    rect(v, 10, 30, 310, 190, 13)
    return v
