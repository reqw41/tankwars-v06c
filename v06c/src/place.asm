; Отрисовка рельефа и расстановка танков — renderTerrain() и placeTanks() эталона web/tankwars.js (PROFILE_V06C).
;
; render_terrain: для каждого x = 0..255, где terr_top[x] != 0xFF, закрасить столбец землёй (цвет 1)
;                 от строки terr_top[x] до строки 252 включительно.
; place_tanks:    вход A = число игроков n (2..4), pl_rebound = 0 или 1; RandSeed в rand_seed.
;                 Выход: таблицы tk_x, tk_y, tk_angle, tk_facing (по 4 байта, игрок i = 1..n в ячейке i-1;
;                 tk_facing: 1 или 0xFF для -1) и нарисованные на экране танки.
; ЗАГЛУШКА: задача Q2 (docs/tasks/Q2-place.md).

render_terrain:
	ret

place_tanks:
	ret
place_end:

pl_rebound:	db	0
tk_x:		ds	4
tk_y:		ds	4
tk_angle:	ds	4
tk_facing:	ds	4
