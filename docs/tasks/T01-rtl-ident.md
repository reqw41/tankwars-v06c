# T01. Опознание RTL Turbo Pascal 6 в Tank Wars 2.5

Прочитай сначала `docs/CONTRACTS.md` и `re/NOTES.md`.

## Контекст
Tank Wars 2.5 (BOMB.EXE + BOMB.OVR) написан на Turbo Pascal 6.0. Он уже склеен в `re/bomb25_flat.exe`
и разобран в Ghidra (`re/ghidra/bomb25`, экспорт в `re/export/`). Игровой код (оверлеи 2185..32ec,
главная программа 1000 и резидентная часть 1062) вызывает библиотечные функции через безымянные `FUN_xxxx_yyyy`.
Особенно мешают Real48-операции: без имён физика не читается.
**Цель:** дать имена и сигнатуры библиотечным функциям, чтобы последующие задачи читали логику игры.

Библиотечные сегменты (адреса Ghidra): 1c5b System, 1827 Graph, 1be7 Crt, 175e и 17a3..17c5 обёртки
и прочие юниты, 1651 Overlay, 166f, 1637, 1691 (что это — выяснить), 17af (Printer?, строка LPT1).

## Что сделать
1. **System (1c5b), в первую очередь:** пролог/StackCheck, вход/выход программы, RunError,
   Real48 (TP передаёт Real в DX:BX:AX): сложение, вычитание, умножение, деление, сравнение, преобразование
   Integer/LongInt→Real, Trunc, Round, Int, Frac, Abs, Sqr, Sqrt, Sin, Cos, ArcTan, Exp, Ln.
   Также Random, Randomize, LongInt mul/div/mod/shl/shr, строковые операции (присваивание, конкатенация,
   сравнение, Copy, Str/Val), Write/WriteLn/Read, Move, FillChar, работа с файлами.
2. **Graph (1827) и Crt (1be7):** по возможности все используемые игрой процедуры: InitGraph, PutPixel, GetPixel,
   Line, LineTo, MoveTo, SetColor, SetFillStyle, Bar, Rectangle, Circle, Arc, PieSlice, FloodFill, OutTextXY,
   SetTextStyle, TextWidth, GetImage, PutImage, ImageSize, SetPalette, SetRGBPalette, ClearDevice, SetViewPort;
   Crt: KeyPressed, ReadKey, Delay, Sound, NoSound, GotoXY, ClrScr, TextColor.
3. Остальные резидентные юниты: определить назначение (мышь? звук? EMS?), назвать функции, если они очевидны.
4. **Не трогать игровую логику.** Игровые функции не переименовывать, только библиотечные.

## Метод и доказательства
- Окружение Python: `python3 -m venv .venv && .venv/bin/pip install unicorn pytest` (в системном Python unicorn нет).
- Опознание по коду, по строкам и по тому, как функцию вызывают (регистры, стек).
- **Каждую Real48- и LongInt-функцию проверить исполнением:** эмулировать её (Python + `unicorn`, 16-битный
  real mode, грузить код из `re/bomb25_flat.exe` с применёнными релокациями) на ≥6 входах, включая
  отрицательные, ноль и большие значения. Результат сравнить с эталоном на Python
  (Real48 ↔ float — свой конвертер в `scripts/real48.py`, с тестом туда-обратно). Допуск — 1 младший бит мантиссы.
- Для Graph/Crt достаточно статического доказательства: номер функции BGI-драйвера, вектор INT 10h/16h,
  порт 61h/42h и т.п. Указать его в evidence.
- Не скачивать дистрибутивы Turbo Pascal и FLIRT-сигнатуры сомнительного происхождения.

## Выходные файлы (строго эти)
- `re/rtl/rtl_names.csv` — `address;name;signature;unit;evidence;verified(yes/static)`.
  Сигнатура в Ghidra-синтаксисе, если её удалось вывести.
- `scripts/ApplyRtlNames.java` — headless-скрипт, применяет CSV (имя, сигнатура, комментарий) к проекту.
  Должен быть идемпотентным.
- `scripts/real48.py`, `scripts/emu16.py` (обвязка unicorn), `tests/test_rtl.py` (pytest, все проверки исполнением).
- `scripts/rtl_coverage.py` — метрика: доля call-сайтов из игровых сегментов (1000, игровая часть 1062,
  2185..32ec), которые ведут в библиотечные сегменты и цель которых имеет имя. Плюс список
  неназванных целей, отсортированный по числу вызовов.
- Перегенерированный `re/export/` (после ApplyRtlNames).
- `docs/tasks/T01-report.md`: таблица опознанного, вывод метрики (скопирован из вывода скрипта),
  разделы «Доказано» и «Гипотезы», список неопознанного.
- Раздел «T01» в `re/NOTES.md`: краткая карта юнитов и соглашение о передаче Real.

## Гейт приёмки
- `pytest tests/test_rtl.py` зелёный, в нём ≥ 20 функций проверены исполнением, включая все Real48-операции,
  которые встречаются в игровом коде.
- Покрытие по `rtl_coverage.py` ≥ 95% call-сайтов (игра → библиотека).
- Пересборка с нуля проходит: import → TpPrologues → ApplyRtlNames → ExportAll. Команду записать в NOTES.
- Один коммит (или несколько) только со своими файлами, сообщение начинается с `T01:`.
