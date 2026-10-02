# T02 — отчёт: баллистика выстрела

Скрипты: `scripts/probe/flight_trace.py` → `work/T02/traces/`, модель `scripts/ref/ballistics.py`,
спека `docs/spec/ballistics.md`, имена `re/game/names_T02.csv`.

## Гейт (числа из вывода скриптов)

| Проверка | Вывод |
|---|---|
| сценарии unicorn | `25` (`work/T02/traces/summary.json`) |
| pytest ballistics | `32 passed in 13.62s` (`work/T02/pytest_ballistics.txt`) |
| pytest целиком | `332 passed in 15.92s` (`work/T02/pytest_all.txt`) |
| модель = оригинал пиксель-в-пиксель | `25/25` |
| fixed-point (16.16) совпадение точки падения | `18/25` (`work/T02/fp_impact_matches.txt`) |

## Доказано

- Полёт — `2583:01c0` (`TW_FireShot`). Дизасм `work/T02/export/FUN_2583_01c0.asm`; unicorn с зеркалом DS=`0x5000` (иначе `DS:81xx` пересекается с кодом `2583` в flat-образе).
- Мuzzle: `x = tank_x + Cos(DegToRad(θ))*10*facing`, `y = tank_y − Sin(θ)*10` (константа Real48 `10.0` на `2583:0397`).
- Скорость: `vx=(power/50)*Cos*facing`, `vy=−(power/50)*Sin` (`50.0` на `2583:044f`; negate Sin при `AL≠0`).
- Шаг: `x+=vx/10; y+=vy/10; vy+=0.1/10; vx+=wind/5000/10` (`3eb0←10`, gravity `0.1`, wind denom `5000.0`).
- Trunc к 0 для пикселей; столзия — ромб ±1, цвета `2` и `20..29` (`1691:0b0a`).
- Стены: `8200≠0` → отражение на `x∈{10,310}`, `y∈{30,190}`; иначе wind-snap `y←200` у краёв.
- Конец: `y∉[-5000,193]` или hit.
- Эталонные трассы: `work/T02/traces/*.json` (хук записи `2583:0b91`).

### Диапазоны Real (из `work/T02/ranges.json`, прогон модели по 25 сценариям)

| величина | min | max |
|---|---|---|
| x | 7.197795688822225 | 2734.4353624992073 |
| y | -157.92968644574285 | 193.43637429713272 |
| vx | -29.556266659259563 | 29.556266659259563 |
| vy | -8.863269777109963 | 8.220442416204605 |

**Fixed-point:** signed **16.16** достаточен по динамическому диапазону; расхождение траекторий — `18/25` совпадений impact-пикселя.

## Гипотезы

- Точные пороги «collision band» (`y>33` vs `y>4` в соседних проверках отрисовки) выведены из Real48-компараторов; краевые пиксели у UI-рамок могут отличаться от «игрового поля» в доке.
- Отрисовка ствола (`1062:059f`) множит Cos/Sin на **8**, а выстрел — на **10** (смещение дула vs спрайта).
- Поведение Laser/Sonic/наведения детально не разбиралось (только адреса ветвлений / post-hit `1054:0020`).

## Addendum 1

Скрипты: `scripts/ref/wind.py`, `scripts/ref/fp_compare.py`, `tests/test_wind.py`.  
`pytest tests/`: `387 passed in 7.68s` (`work/T02/pytest_all_addendum1.txt`).

### Доказано

**Ветер** — оригинальный код `2583:2567..2675` внутри `FUN_2583_2531`, исполнен в unicorn (`generate_wind_emu`).  
Режимы `DS:81f6`: 0 None / 1 Low(20) / 2 Norm(100) / 3 High(300) / 4 Gale(4000) / 5 RND→`RandomWord(5)`.  
`wind = span/2 − RandomWord(span)`; до 4× `×4` если `RandomReal() < {0.1,0.1,0.05,0.05}`; clamp ±30000.

Распределения n=1000 (`work/T02/wind_dist.json`):

| mode | min | max |
|---|---|---|
| None | 0 | 0 |
| Low | -320 | 320 |
| Norm | -752 | 2880 |
| High | -2352 | 2880 |
| Gale | -29184 | 28960 |

Модель `generate_wind_model` совпадает с emu на тех же RandSeed (`tests/test_wind.py`).  
Сценарии `wind_gale_{pos,neg,max,min}` используют крайние Gale ±28960/−29184.

**Порог остановки** (`2583:01ce`, `0d2d`, `0d6c`): сравнивается именно **power** (`+0x3f0a`) с локальным `thresh = 1000 − 2*Men` (`Men` at `+0x3f10`).  
Также `done` при `3eac==3eb0` или цвете танка; отмена при `power==thresh && color==2`.  
Не ветка Balls-o-Dirt: общий код для всех оружий в `TW_FireShot`. При Men≤9 любой легальный power < thresh → dirt всегда останавливает.

**Угол:** UI = **0..90 + facing ±1**; метка `a180_p200` заменена на `a0_facem1_p200` (+ `a90_facem1_p200`).

**Fixed-point** (`scripts/ref/fp_compare.py` → `work/T02/fp_compare.txt`):

| формат | impact match | max pixel-dev | mean max-dev |
|---|---|---|---|
| 16.16 | 26/28 | 1 | 0.8214285714285714 |
| pos16.8+vel8.8 | 4/28 | 231 | 61.17857142857143 |
| pos24.8+vel8.16 | 12/28 | 6 | 2.642857142857143 |

Источники ошибки (из скрипта): `1/5000` в 8.8 → 0; накопление `0.01` (1619 шагов: true 16.19 vs 8.8→18.97).  
Cycle Delay: `CRT_Delay(3)` → ≥333.3 step/s; 1619 steps ≈4.86 s; бюджет 8080@3 МГц ≈9000 цикл/шаг.  
**Рекомендация:** 16.16 (цитата из `fp_compare.json`).

### Гипотезы (addendum)

- Именование Low/Norm в меню vs DOC «None/Norm/High/Gale» — Low есть в бинаре (`None/Low/Norm/High/Gale/RND`); DOC сокращён.
- Оценка циклов 8080 — порядковая, не замеры на железе.

## Файлы

- `docs/spec/ballistics.md`
- `re/game/names_T02.csv`
- `scripts/ref/ballistics.py`, `scripts/ref/wind.py`, `scripts/ref/fp_compare.py`
- `scripts/probe/flight_trace.py`
- `tests/test_ballistics.py`, `tests/test_wind.py`
- `work/T02/` (traces, wind_dist, fp_compare, pytest logs) — не обязательно в git
