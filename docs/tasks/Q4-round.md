# Q4. Начало раунда на ассемблере 8080 (маленькая задача)

Нужно написать ОДНУ подпрограмму `round_start` в файле `v06c/src/round.asm`. Больше никакие файлы менять нельзя.

## Проверка (единственный критерий готовности)
```
sh v06c/build.sh && node v06c/test/round.mjs
```
Готово, когда вторая команда печатает строку, начинающуюся с `OK  начало раунда:`. Пока печатает `FAIL ...` — не готово:
в сообщении написано, что не совпало. После зелёного теста запусти ещё `node v06c/test/place.mjs`,
`node v06c/test/match.mjs`, `node v06c/test/run.mjs` — все должны закончиться `OK ...`.

Это перенос функций `roundStart` и `generateWind` из `web/tankwars.js` (прочитай их). Почти вся работа уже сделана
готовыми подпрограммами — нужно вызвать их в правильном порядке и добавить немного своей логики.

## Алгоритм (порядок менять нельзя: от него зависит, какие случайные числа берутся и когда)
```
1. r = rnd_hi()                                   ; ВСЕГДА вызвать, даже если стены заданы
   rebound = 1, если r < 32768, иначе 0           ; беззнаковое сравнение HL с 32768
   если rs_walls == 0: rebound = 0
   если rs_walls == 2: rebound = 1
   rs_rebound = rebound
2. clear_screen
3. draw_frame с A = 1
4. gen_terrain с A = n_players
5. render_terrain
6. pl_rebound = rs_rebound;  place_tanks с A = n_players
7. для каждого игрока i = 1..n (запись номер i − 1 в таблице players, длина записи PL_SIZE):
       PL_X = tk_x[i − 1];  PL_Y = tk_y[i − 1];  PL_ANGLE = tk_angle[i − 1];  PL_FACING = tk_facing[i − 1]
       PL_POWER = 200 (слово);  PL_MEN = 100 (слово);  PL_ALIVE = 1;  PL_AI_N = 0
   остальные поля записи не трогать
8. rs_first = Random(n)                           ; байт 0..n−1
9. ветер:
       mode = rs_windmode
       если mode == 5:  eff = Random(5), иначе eff = mode          ; Random(5) берётся ТОЛЬКО при mode == 5
       span = таблица[eff]: 0, 20, 100, 300, 4000
       r = Random(span)                           ; вызвать ВСЕГДА, даже если span == 0 (тогда r = 0)
       w = span/2 − r                             ; слово со знаком
       четыре раза подряд, с порогами 6554, 6554, 3277, 3277:
           t = rnd_hi();  если t < порог:  w = w·4 (16 бит, старшие биты отбрасываются)
       если w > 30000: w = 30000;   если w < −30000: w = −30000
       rs_wind = w
```

## Готовые подпрограммы и данные (их не менять, только использовать)
Все подпрограммы портят регистры AF, BC, DE, HL — свои счётчики и значения храни в ячейках памяти (`db`/`dw`).
- `rnd_hi` (random.asm): выход HL = число 0..65535.
- `random` (random.asm): вход DE = n, выход HL = Random(n). При n = 0 возвращает 0, но шаг генератора делает.
- `clear_screen` (fill.asm), `draw_frame` (frame.asm, вход A), `gen_terrain` (terrain.asm, вход A = n),
  `render_terrain` и `place_tanks` (place.asm, вход A = n; перед вызовом записать `pl_rebound`).
- `tk_x`, `tk_y`, `tk_angle`, `tk_facing` (place.asm) — таблицы по 4 байта, результат расстановки.
- `n_players` (байт) и `players` (match.asm); смещения полей — `v06c/src/player.inc`.

Подсказка: сравнение «HL < порог» беззнаковое — `ld a,h` / `cp старший_байт` и т.д., или вычитанием с переносом.
Умножение w на 4 — два раза `add hl,hl`.

## Правила ассемблера (важно)
Синтаксис — мнемоники Z80 в sjasmplus, но процессор 8080: разрешены только команды, которые есть у 8080.
Нельзя: `jr`, `djnz`, `ix`, `iy`, `ex af`, `exx`, `ldir`, `bit`/`set`/`res`, `sla`/`sra`/`srl`/`rl`/`rr` (кроме `rla`, `rra`,
`rlca`, `rrca`), `neg`, `sbc hl`, `adc hl`, `ld bc,(nn)`, `ld de,(nn)`, `ld (nn),bc`, `ld (nn),de`.
Нельзя писать `sub (метка)`, `cp (метка)` или `ld e,(метка)` — sjasmplus примет это за число. Значение из ячейки бери
так: `ld a,(метка)`, а слово — `ld hl,(метка)`.
Можно: `ld hl,(nn)`, `ld (nn),hl`, `ld a,(nn)`, `ld (nn),a`, `add hl,de`, `ex de,hl`, `jp`, `jp z/nz/c/nc/m/p`, `call`, `ret`,
`inc`/`dec`, `cp`, `sub`, `sbc a`, `add a`, `adc a`, `and`, `or`, `xor`, `cpl`, `push`/`pop`.
Имена своих меток начинай с `rs_`. Образцы стиля — `v06c/src/match.asm`, `v06c/src/place.asm`.

Метки `round_start`, `round_end`, `rs_walls`, `rs_windmode`, `rs_rebound`, `rs_first`, `rs_wind` должны остаться с этими
именами; ячейки `rs_rebound`, `rs_first`, `rs_wind` должны идти подряд именно в этом порядке (тест читает их одним куском).

## Чего не делать
- Не менять ничего, кроме `v06c/src/round.asm`. Не трогать тесты, `web/`, другие `.asm` и `.inc`.
- Не делать `git stash`, `checkout`, `reset`. Когда тест зелёный — один коммит:
  `git add v06c/src/round.asm && git commit -m "Q4: начало раунда на 8080"`.
- Не писать отчётов и других файлов.
