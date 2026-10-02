# T01b — отчёт: Graph по эффекту (unicorn+VGA256)

Скрипты: `scripts/emu16.py` (A000 + INT10/21/33, BIOS-шрифт F000:FA6E), `scripts/graph_env.py`,
`work/T01b/probe_effects.py` → `work/T01b/effects.json`.

## Гейт (числа из вывода скриптов)

| Проверка | Вывод |
|---|---|
| pytest | `293 passed in 0.33s` (`work/T01b/pytest_out.txt`) |
| coverage | `coverage: 100.00%` / `game→lib far calls: 2990` / `named: 2990` (`work/T01b/coverage_out.txt`) |
| Graph probes | OK 46/46, proven=33; calls≥5: 23/23 (`work/T01b/probe_effects.py`) |
| CSV имена | уникальны (скрипт обновления) |
| Ghidra | `ApplyRtlNames: renamed/kept=208 commented=208 skipped=0` (`work/T01b/ghidra_out.txt`) |

## Доказано

Имя по наблюдаемому эффекту (VRAM / AX / DS-глобалы / INT). Старое имя — из T01 CSV/`graph_game.py`.

| Адрес | Старое | Новое | Доказательство |
|---|---|---|---|
| 1827:1fe4 | PutPixel | GRAPH_PutPixel | PutPixel(10,20,5)→A000 pixel=5 |
| 1827:1fcc | SetFillStyle | GRAPH_GetPixel | GetPixel(15,25)→9 после записи |
| 1827:1dc2 | SetColor | GRAPH_SetColor | E660←9 |
| 1827:1c86 | Line | GRAPH_Line | Line bbox=(20,10,80,50,61) |
| 1827:1cce | Rectangle | GRAPH_Bar | после SetFillStyle заливка pix=14, n=1271 |
| 1827:10d2 | CloseGraph | GRAPH_Rectangle | 4×Line, угол=3, середина=0 |
| 1827:1f12 | Bar | GRAPH_OutTextXY | SI=08 MoveTo + SI=26 OutText; bbox текст |
| 1827:13f2 | RegisterBGIdriver | GRAPH_OutText | OutText at CP через OutTextXY; bbox |
| 1827:1f9b | OutText | GRAPH_TextWidth | TextWidth('Hello')→40 |
| 1827:1042 | SetViewPort | GRAPH_MoveTo | E666/E668←123/45 |
| 1827:105f | GetMaxX | GRAPH_GetX | AX←E666 |
| 1827:1072 | GetMaxY | GRAPH_GetMaxX | AX=319 ←E5E4 |
| 1827:1085 | GetMaxColor | GRAPH_GetMaxY | AX=199 ←E5E6 |
| 1827:0f93 | SetRGBPalette | GRAPH_SetViewPort | vp=[10,20,250,150] clip=1 |
| 1827:1131 | GraphResult_set | GRAPH_SetFillStyle | E684/E686←pattern/color |
| 1827:1119 | GetViewSettings | GRAPH_GetFillSettings | пишет E684/E686 в far buf |
| 1827:1454 | RegisterBGIfont | GRAPH_SetTextJustify | E6B4/E6B6←horiz/vert |
| 1827:1241 | GetColor | GRAPH_GetColor | AX=цвет после SetColor |
| 1827:04f3 | GraphResult | GRAPH_GraphResult | возвращает E63A, обнуляет |
| 1827:027e | InitGraph | GRAPH_GraphErrorMsg | code0→'No error' |
| 1827:0eb5 | RestoreCrtMode | GRAPH_CloseGraph | E670←0 |
| 1827:0f80 | SetActivePage | GRAPH_ClearDevice_MoveTo0 | CP←0,0 |
| 1827:1ffb | GetImage | GRAPH_GetImage | заголовок w×h |
| 1827:192b | SetAspectRatio | GRAPH_SetAspectRatio | E66C/E66E |
| 1827:1e4a | SetLineStyle | GRAPH_SetLineStyle | SI=1Ah, без падения |
| 1827:05d3 | DetectGraph2 | GRAPH_RegisterBGIdriver | путь 0569+SI=2 в make_graph_emu |
| 1827:0bae | RegisterBGIdriver2 | GRAPH_InitGraph | E642←драйвер |
| 1827:193e | InitGraph2 | GRAPH_InitUnit | unit init |
| 175e:0088 | GRAPHW_Rectangle | GRAPHW_Hypot | sqrt(3²+4²)→5.0 |
| 175e:00da | GRAPHW_PutPixel | GRAPHW_DegToRad | DegToRad(180)→π |
| 175e:0124 | GRAPHW_OutTextXY | GRAPHW_RadToDeg | RadToDeg(π)→180 |
| 175e:0190 | GRAPHW_Line | GRAPHW_MouseX_div2 | mouse_x=160→AX=80; INT33 |
| 175e:01cc | GRAPHW_Bar | GRAPHW_MouseGetY | mouse_y=123→AX=123; INT33 |

## Гипотезы

Вызваны, эффект слабый/частичный или без VRAM; имя осторожное / `GRAPH_*_unk`-стиль.

| Адрес | calls | Имя | Причина |
|---|---|---|---|
| 175e:0000 | 2 | GRAPHW_InitView | зовёт GetMaxX/Y/SetViewPort; полный init не разобран |
| 175e:0026 | 1 | GRAPHW_0026 | Real/Detect путь; мало calls |
| 175e:0057 | 1 | GRAPHW_0057 | то же |
| 175e:0293 | 55 | GRAPHW_StrOrCopy | System 1790+adc (Str/copy); семантика строки не до конца |
| 175e:02dc | 1 | GRAPHW_02dc | — |
| 175e:0393 | 1 | GRAPHW_0393 | — |
| 1827:06ca | 3 | GRAPH_RegisterBGIfont | регистрация шрифта; без полного font blob |
| 1827:1028 | 3 | GRAPH_1028 | AX=9 (Detect path) |
| 1827:11ea | 9 | GRAPH_11ea_SectorOrArc | 3 args→11b7+1d20; VRAM без изменений в пробе |
| 1827:131d | 4 | GRAPH_131d_ViewAdjust | правка far-struct от viewport |
| 1827:13d8 | 3 | GRAPH_13d8 | AX=10 |
| 1827:1496 | 19 | GRAPH_1496_LoadMode | INT21 file I/O; нужен файл драйвера/режима |
| 1827:16e3 | 14 | GRAPH_16e3_FillRect | валидация maxXY + 1f7e SI=24; VRAM пуст в пробе |

Функции Graph, которые игра не вызывает, в CSV: `verified=static`, при сомнении — `GRAPH_unk_<addr>` (уникальные имена).

## System (доработки)

- LongDiv `1c5b:0a2d`: частное DX:AX; остаток CX=lo, BX=hi; к нулю. Тест `-7/2 → -3 rem -1`.
- Real: roundtrip/арифметика с 1e6, 1e12, 1e30; Trunc/Round ±40000, ±70000.5.

## Coverage

`scripts/rtl_coverage.py` берёт границы из `re/ovl_map.txt` + полные диапазоны `1000→1035`, `1062→1632`.

## Эмуляция Graph

`make_graph_emu`: Graph init `193e` → reloc VGA256 через `0569` → E642 → driver SI=2 (mode 13h) → E670/maxX/maxY.
