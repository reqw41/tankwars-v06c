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
