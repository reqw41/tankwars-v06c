# T01 — отчёт: опознание RTL Turbo Pascal 6

## Метрика покрытия (вывод `scripts/rtl_coverage.py`)

```
game→lib far calls: 2989
named call-sites:   2989
coverage:           100.00%
unique unnamed targets: 0
top unnamed:
```

## Pytest (вывод)

```
287 passed in 0.21s
```

Проверены исполнением (≥20 entry points): RealAdd, RealSub, RealMul, RealDiv, Sqr, RealCmp, LongToReal, Trunc, Round, Int, Frac, Sqrt, Sin, Cos, ArcTan, Abs, LongMul, LongDiv, RandomReal, RandomWord (+ roundtrip Real48).

## Таблица опознанного (сводка по юнитам)

| unit | записей в CSV | verified=yes | verified=static |
|---|---:|---:|---:|
| System | 71 | 28 | 43 |
| Graph | 67 | 0 | 67 |
| GraphWrap (175e) | 11 | 0 | 11 |
| CrtExt (17c5) | 12 | 0 | 12 |
| Crt (1be7) | 5 | 0 | 5 |
| Mouse (17a3) | 10 | 0 | 10 |
| Unit1691 | 20 | 0 | 20 |
| Unit166f / 1637 / Overlay / Printer | 12 | 0 | 12 |
| **всего** | **208** | **28** | **180** |

Полный список: `re/rtl/rtl_names.csv`.

## Доказано

Real48 передаётся в `DX:BX:AX` (левый) и `DI:SI:CX` (правый); результат в `DX:BX:AX`. FAR-обёртки `1c5b:112b..115b` вызывают near-ядра и делают `RETF`.

| адрес | имя | доказательство |
|---|---|---|
| 1c5b:112b / 0e27 | RealAdd | unicorn: 2+3→5 и набор из `tests/test_rtl.py` |
| 1c5b:1131 / 0e23 | RealSub | XOR DI,8000 + add; 10−4→6 |
| 1c5b:113d / 0eea | RealMul | 6×7→42 |
| 1c5b:1143 / 0fef | RealDiv | 15/3→5 |
| 1c5b:1137 | Sqr | дублирует операнд и MUL; 5→25 |
| 1c5b:114d / 1066 | RealCmp | флаги ZF/CF на парах (1,1)/(1,2)/(2,1) |
| 1c5b:1151 / 1090 | LongToReal | LongInt DX:AX → Real |
| 1c5b:1155 / 10cf CH=0 | Trunc | Trunc(3.7)=3 |
| 1c5b:115b / 10cf CH=1 | Round | Round(3.7)=4 |
| 1c5b:119f | Int | Int(4.75)=4.0 как Real |
| 1c5b:11f0 | Frac | Frac(4.75)=0.75 |
| 1c5b:1204 | Sqrt | Sqrt(4)=2 |
| 1c5b:1263 | Cos | Cos(0)≈1, Cos(π/6)≈√3/2 |
| 1c5b:1276 | Sin | Sin(π/6)=0.5 |
| 1c5b:144d | ArcTan | ArcTan(1)≈π/4 |
| 1c5b:1619 | Abs | AND DH,7Fh |
| 1c5b:15ea | Random(N) | LCG@1639 + DIV; значения ∈[0,N) |
| 1c5b:1600 | Random | LCG → Real ∈[0,1) |
| 1c5b:0a12 | LongMul | 12345×67=827115 |
| 1c5b:0a2d | LongDiv | ±100/±5 |
| 1c5b:1639 | RandInt | LCG пишет `DS:3774` RandSeed |
| 1c5b:1671 | Randomize | INT 21h AH=2Ch → RandSeed |

Скрипты: `scripts/real48.py`, `scripts/emu16.py`, `tests/test_rtl.py`.

Graph (статически): вызов драйвера `MOV SI,<cmd>; CALL FAR [DS:E642]`.
Примеры: SI=1Eh SetColor (`1827:1dc2`), SI=30h PutPixel (`1fe4`), SI=0Ch Line, SI=12h Rectangle, SI=08h Bar.

CrtExt `17c5` (используется игрой вместо почти пустого `1be7`): Sound OUT 61h/42h/43h (`02c7`), NoSound AND 61h (`02f4`), KeyPressed/ReadKey INT 16h (`02fb`/`030d`).

Mouse `17a3`: INT 33h AX=0/1/2/3 — Init/Show/Hide/GetX/GetY/ButtonPressed.

## Гипотезы

- Точные имена части Graph SI=0Eh / 14h / 3Ah (LineTo vs MoveTo, Circle vs DrawPoly, SetWriteMode) — по числу аргументов; возможны перестановки синонимов.
- `1691`, `166f`, `1637` — резидентные юниты с INT 10h; функции названы `U1691_*` / `U166f_*` / `U1637_*` без семантики игровой логики.
- Часть System file I/O (`1925`, `18bb`, `183a`…) — по DOS AH и структуре file record; детали Reset/Rewrite/Append не разделялись тестами.
- Стандартный Crt `1be7` почти не вызывается игрой (2 call-сайта); основной текстовый/звук/клавиатура путь — `17c5`.
- Exp/Ln в игровых far-call не встречаются; в CSV не выносились как used.

## Неопознанное

По метрике call-сайтов игра→библиотека: **пусто** (0 unnamed).

Внутри библиотечных сегментов остаются безымянные `FUN_*` (служебные near-хелперы, редкие Graph/Crt entry), не попадающие в far-call из игровых сегментов — см. `re/export/functions.txt` после фильтра `FUN_` в сегментах 1637..1c5b.

## Пересборка

```
JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home
G=/opt/homebrew/opt/ghidra/libexec
$G/support/analyzeHeadless re/ghidra bomb25 \
  -import re/bomb25_flat.exe -overwrite \
  -scriptPath $PWD/scripts \
  -preScript TpPrologues.java \
  -postScript ApplyRtlNames.java $PWD/re/rtl/rtl_names.csv \
  -postScript ExportAll.java $PWD/re/export
```

Лог: `work/T01/ghidra_rebuild.log` — `ApplyRtlNames: renamed/kept=208 skipped=0`, `Import succeeded`.
