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
- Генерация ветра None/Norm/High/Gale (`3eae` + RandomWord/`×4`) — по декомпилу меню; в полёте используется только готовый `3ede`.
- Отрисовка ствола (`1062:059f`) множит Cos/Sin на **8**, а выстрел — на **10** (смещение дула vs спрайта).
- Поведение Laser/Sonic/наведения детально не разбиралось (только адреса ветвлений / post-hit `1054:0020`).

## Файлы

- `docs/spec/ballistics.md`
- `re/game/names_T02.csv`
- `scripts/ref/ballistics.py`, `scripts/probe/flight_trace.py`
- `tests/test_ballistics.py`
- `work/T02/` (asm export, traces, pytest logs) — не обязательно в git
