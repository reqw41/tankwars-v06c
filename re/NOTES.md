# Tank Wars 2.5 — заметки по реверсу

Исходник: `orig/TankWarsV2.5sw1990kennyMorsestrategy/` (BOMB.EXE 17.05.1991 + BOMB.OVR).

## Инструменты
- Ghidra 12.1.4 (brew formula `ghidra`), JDK: `JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home`
- `scripts/flatten_ovr.py` — склейка EXE+OVR в `re/bomb25_flat.exe` (оверлеи → сегменты, стабы INT 3Fh → JMP FAR), карта в `re/ovl_map.txt`
- `scripts/TpPrologues.java` (preScript) — функции по прологу 55 89 E5
- `scripts/ExportAll.java` (postScript) — `re/export/{functions.txt,decomp.c,strings.txt}`
- Проект Ghidra: `re/ghidra/bomb25`

Пересборка:
```
analyzeHeadless re/ghidra bomb25 -import re/bomb25_flat.exe -overwrite \
  -preScript TpPrologues.java -postScript ExportAll.java $PWD/re/export -scriptPath $PWD/scripts
```

## Бинарник
- Turbo Pascal 6.0 (RTL «1983,90»), без упаковщика. BGI VGA256 320x200x256 + шрифты, вшиты в EXE.
- Оверлеи TP6 (FBOV): стаб = `CD 3F`, +2 save, +4 dd fileoff (абсолютный в OVR), +8 codesize, +10 fixupsize,
  +12 nentries; входы с +32 по 5 байт `CD 3F off16 00`. Фиксапы — слова-смещения сегментных слов
  (значения относительно начала образа, как MZ-релокации).
- BOMB1.RAW / BOMB2.RAW = 64000 пикселей + 768 палитра.

## Сегменты (адреса Ghidra = образ + 0x1000)
| сегмент | что |
|---|---|
| 1000 | главная программа (инициализация, регистрация BGI) |
| 1035..1057 | стабы оверлеев |
| 1062 | резидентный код игры + вшитые BGI-драйвер/шрифты; строки «Game Status», «MASS KILL» |
| 1651 | инициализация оверлеев |
| 175e | обёртки Graph |
| 1827 | Graph unit (BGI) |
| 1be7 | Crt |
| 1c5b | System RTL (в т.ч. Real48-арифметика) |
| 1e0d | **DS** (0x0E0D в образе), ~14 КБ инициализированных данных |
| 2185 | ovl: загрузка bomb1/2.raw |
| 21ee | ovl: EMS, сводка памяти |
| 224b | ovl: магазин (Purchase/Done/DOLLARS), таблица счёта |
| 2583 | ovl: игровой экран (Angle/Power/Wind/Men), видимо ход и полёт |
| 285c, 2b39, 2cab, 2eef | ovl: TODO (2b39 — «Birdy Bonker») |
| 30b8 | ovl: статус игрока, наведение («Please click on target») |
| 32ec | ovl: главное меню, настройки, выбор ИИ, BOMB.CFG |

## DS: таблицы
- 0x0020: `array[0..6] of string[255]` — ИИ: Random, Mr. Stupid, Lobber, Rifleman, Lob & Shoot, Windless Wit, Twanger
- 0x0720: `array[1..18] of string[255]` — полные имена оружия
- 0x1920: `array[1..18] of string[255]` — короткие имена
- 0x2B20: `array[1..18] of LongInt` — цены (-1 у Lead Ball и Hand Grenade = бесплатно/бесконечно?)
- 0x2B68: `array[1..18] of Word` — 0,100,10,2,1,1000,5,10,3,3,1,0,10,10,7,3,1,10 (количество за покупку? проверить по коду)
- 0x2B8C: наведение (4 строки), 0x2F8C: цены 20000,20000 + слова 5,5
- 0x2F98: щиты (4 строки), 0x3398: 20000,10000,1000,100…, далее битмапы 16-битных спрайтов (танк?)

## T01 — RTL Turbo Pascal 6

Карта юнитов (Ghidra):
| seg | unit |
|---|---|
| 1c5b | System (Real48, LongInt, строки, файлы, Random) |
| 1827 | Graph (BGI через `CALL FAR [DS:E642]`, команда в SI = смещение в таблице драйвера) |
| 175e | GraphWrap / хелперы игры (Hypot, DegToRad/RadToDeg, мышь) — **не** тонкие обёртки Graph |
| 17c5 | Crt-подобный (Sound/NoSound/KeyPressed/ReadKey/Delay) — **им пользуется игра** |
| 1be7 | стандартный Crt (почти не вызывается) |
| 17a3 | Mouse (INT 33h) |
| 17af | Printer (LPT1) |
| 1651 | Overlay |
| 1691, 166f, 1637 | прочие резидентные (INT 10h и др.), имена `U1691_*`… |

Соглашение Real48: значение в регистрах **DX:BX:AX** (младшее слово AX = exp в младшем байте + младшие биты мантиссы). Бинарные операции: левый = DX:BX:AX, правый = DI:SI:CX, результат = DX:BX:AX. FAR-entry: `1c5b:112b` Add, `1131` Sub, `113d` Mul, `1143` Div, `114d` Cmp, `1151` LongToReal, `1155` Trunc, `115b` Round. RandSeed = `DS:3774` (LongInt). LongDiv `0a2d`: частное DX:AX, остаток CX=lo/BX=hi, к нулю.

### T01b — Graph по эффекту (unicorn + VGA256)

Имена Graph/GraphWrap из T01 (по первому MOV SI) **отменены**. Переименованы по эффекту в `work/T01b/effects.json` / `docs/tasks/T01b-report.md`. Ключевые правки:
- `1fcc` = GetPixel (не SetFillStyle); `1f12` = OutTextXY (SI=08+26); `1cce` = Bar; `10d2` = Rectangle (4×Line)
- `13f2` = OutText; `1454` = SetTextJustify; `1131` = SetFillStyle; `0f93` = SetViewPort; `1042` = MoveTo
- `1f9b` = TextWidth; `175e:0088` = Hypot; `00da`/`0124` = DegToRad/RadToDeg
- **Addendum 1:** `11ea` = Circle (VGA256 SI=14 stub → hook в `graph_env`); `1496` = SetTextStyle; `16e3` = SetUserCharSize; `175e:0293` = IntToStr. Тесты ≥30 entry points в `tests/test_graph.py`.

Эмуляция: `scripts/emu16.py` + `scripts/graph_env.py` (reloc вшитого VGA256, A000, INT10, BIOS-шрифт F000:FA6E).

Имена: `re/rtl/rtl_names.csv`, скрипт `scripts/ApplyRtlNames.java`.
Проверка: `pytest tests/`, покрытие `scripts/rtl_coverage.py` (границы из `re/ovl_map.txt`).

## T02 — баллистика (`2583:01c0`)

Выстрел: `TW_FireShot` = `2583:01c0`. Спека `docs/spec/ballistics.md`, имена `re/game/names_T02.csv`,
модель `scripts/ref/ballistics.py`, эталон `scripts/probe/flight_trace.py`.

Физика (Real48): muzzle `Cos/Sin*10*facing`; `v = power/50`; шаг `/10`; `g = +0.1/10` на vy;
ветер `3ede/5000/10` на vx. Trunc→пиксель. Hit: цвет 2 или 20..29, ромб ±1 через `1691:0b0a`.
Стены `8200`. В flat-образе `DS:81xx` пересекается с кодом `2583` — для unicorn зеркалить DS (напр. `0x5000`).

Ветер раунда: `2583:2567` в `FUN_2583_2531`; режимы None/Low/Norm/High/Gale/RND (`81f6`);
модель `scripts/ref/wind.py`. Угол UI = 0..90 + facing ±1. FP сравнение: `scripts/ref/fp_compare.py`.

Пересборка с RTL:
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

## Открытые вопросы (архитектор, 02.10)
- **Circle/Arc (`1827:11ea`) в настоящей игре.** Вшитый VGA256 на SI=14h указывает на заглушку EMULATE
  по смещению 0x10 (`C3 00 00 00 00` = ret + место под far-указатель). Обычно BGI-ядро при InitGraph
  превращает её в переход на свою программную эмуляцию. `graph_env.make_graph_emu` обходит InitGraph,
  поэтому эллипс в тестах рисует хук стенда, а не код игры. Выяснить при разборе взрывов (T03):
  пройти настоящий путь InitGraph и посмотреть, чем станет driver+0x10 и что реально рисуется.
- **ГСЧ для порта.** `Random(N)` TP6 = LCG (`1c5b:1639`, RandSeed `DS:3774`) + остаток от деления (DIV), а не
  старшее слово произведения. Видно на ветре: сид 182 даёт базу 45 и в Norm (50−5), и в High (150−105).
  В порте воспроизводить точно, если нужна совместимость раундов по сиду. Описать в спеке при T04/порте.

## T03 — поле, взрывы, осыпание (итог, 03.10)
- **Полный запуск игры:** `scripts/t03/gamerun.py` (+ `scripts/probe/t03_common.py`: `boot_to_round`, `run_to`,
  `computer_keys`). Адреса Ghidra ↔ запуск: `Game.ghidra_abs(seg)`, `Game.to_ghidra(abs)`. ~20 млн инстр/с.
- Спеки: `docs/spec/terrain.md`, `docs/spec/explosions.md`; отчёт `docs/tasks/T03-report.md`; имена `re/game/names_T03.csv`.
- Номера оружия с 0 (0 Lead Ball … 17 Explosive Dirt). Поля игрока (+смещение от DS:3EFC+0x61*i): x 0, y 2, score 4 (L),
  power 0E, angle 10, facing 12, men 14, alive 16, weapon 17, Energy Shield 45 (L), Inertia Dampener 49 (L).
- **Открытый вопрос EMULATE закрыт:** Circle в настоящей игре рисует (ядро Graph эмулирует); стенд T01b — нет.
- `1827:1028` = GetViewSettings. Здоровье в начале раунда = 100 (см. поправку для T02 в отчёте T03).
- Клавиатура во время хода — свой INT 9, таблица DS:3B90[скан-код].
