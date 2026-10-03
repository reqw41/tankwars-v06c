; Начало раунда — roundStart() эталона web/tankwars.js (PROFILE_V06C).
; Вход: n_players (match.asm), rs_walls (0 — стены обычные, 1 — случайно, 2 — отражают), rs_windmode (0..5),
;       RandSeed в rand_seed, записи игроков в players.
; Выход: rs_rebound (0/1), rs_first (0..n-1), rs_wind (слово со знаком); в записях игроков заполнены
;        PL_X, PL_Y, PL_ANGLE, PL_FACING, PL_POWER = 200, PL_MEN = 100, PL_ALIVE = 1, PL_AI_N = 0; экран раунда нарисован.
; ЗАГЛУШКА: задача Q4 (docs/tasks/Q4-round.md).

round_start:
	ret
round_end:

rs_walls:	db	0
rs_windmode:	db	0
rs_rebound:	db	0
rs_first:	db	0
rs_wind:	dw	0
