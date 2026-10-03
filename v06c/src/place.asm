; Отрисовка рельефа и расстановка танков — renderTerrain() и placeTanks() эталона web/tankwars.js (PROFILE_V06C).
;
; render_terrain: для каждого x = 0..255, где terr_top[x] != 0xFF, закрасить столбец землёй (цвет 1)
;                 от строки terr_top[x] до строки 252 включительно.
; place_tanks:    вход A = число игроков n (2..4), pl_rebound = 0 или 1; RandSeed в rand_seed.
;                 Выход: таблицы tk_x, tk_y, tk_angle, tk_facing (по 4 байта, игрок i = 1..n в ячейке i-1;
;                 tk_facing: 1 или 0xFF для -1) и нарисованные на экране танки.
; Все вызываемые подпрограммы портят AF, BC, DE, HL — счётчики и координаты в ячейках памяти.

render_terrain:
	ld	a, 1
	ld	(ln_c), a			; цвет земли
	xor	a
	ld	(rt_x), a			; x = 0
	ld	hl, terr_top
rte_lp:
	ld	a, (hl)				; top = terr_top[x]
	cp	0xFF
	jp	z, rte_next
	cp	253
	jp	nc, rte_next			; top > 252 — не рисуем
	ld	(rt_top), a
	ld	a, (rt_x)
	ld	(ln_x1), a			; x1 = x2 = x
	ld	(ln_x2), a
	xor	a
	ld	(ln_x1 + 1), a
	ld	(ln_x2 + 1), a
	ld	a, (rt_top)
	ld	(ln_y1), a			; y1 = top
	xor	a
	ld	(ln_y1 + 1), a
	ld	a, 252
	ld	(ln_y2), a			; y2 = 252
	xor	a
	ld	(ln_y2 + 1), a
	push	hl
	call	line
	pop	hl
rte_next:
	inc	hl
	ld	a, (rt_x)
	inc	a
	ld	(rt_x), a
	jp	nz, rte_lp
	ret

place_tanks:
	ld	(pt_n), a
	; first = Random(24) + 8, last = 248 - Random(24) — сначала первый, потом второй
	ld	de, 24
	call	random
	ld	a, l
	add	a, 8
	ld	(pt_first), a
	ld	de, 24
	call	random
	ld	a, 248
	sub	l
	ld	(pt_last), a
	; tk_x[0] = first, tk_x[n-1] = last
	ld	hl, tk_x
	ld	a, (pt_first)
	ld	(hl), a
	ld	a, (pt_n)
	dec	a
	ld	e, a
	ld	d, 0
	add	hl, de
	ld	a, (pt_last)
	ld	(hl), a
	; q = (last - first) / (n - 1), целое деление вычитанием
	ld	a, (pt_last)
	ld	hl, pt_first
	sub	(hl)
	ld	(pt_rem), a
	xor	a
	ld	(pt_q), a
	ld	a, (pt_n)
	dec	a
	ld	(pt_d), a
q_lp:
	ld	hl, pt_d
	ld	a, (pt_rem)
	sub	(hl)
	jp	c, q_done			; rem < d
	ld	(pt_rem), a
	ld	hl, pt_q
	inc	(hl)
	jp	q_lp
q_done:
	; tk_x[k] = k*q + first для k = 1..n-2
	ld	a, 1
	ld	(pt_k), a
k_lp:
	ld	a, (pt_n)
	dec	a
	ld	e, a
	ld	a, (pt_k)
	cp	e
	jp	nc, k_done			; k >= n-1
	ld	a, (pt_k)
	ld	(pt_cnt), a
	xor	a
	ld	(pt_val), a
v_lp:
	ld	a, (pt_cnt)
	or	a
	jp	z, v_done
	dec	a
	ld	(pt_cnt), a
	ld	hl, pt_q
	ld	a, (pt_val)
	add	a, (hl)
	ld	(pt_val), a
	jp	v_lp
v_done:
	ld	a, (pt_val)
	ld	hl, pt_first
	add	a, (hl)
	ld	b, a
	ld	a, (pt_k)
	ld	e, a
	ld	d, 0
	ld	hl, tk_x
	add	hl, de				; hl = &tk_x[k]
	ld	a, b
	ld	(hl), a
	ld	hl, pt_k
	inc	(hl)
	jp	k_lp
k_done:
	; основной цикл по игрокам i = 1..n
	ld	a, 1
	ld	(pt_i), a
i_lp:
	; x = tk_x[i-1]
	ld	hl, tk_x
	ld	a, (pt_i)
	dec	a
	ld	e, a
	ld	d, 0
	add	hl, de
	ld	a, (hl)
	ld	(pt_x), a
	; angle = 75 для i = 1 и i = n, иначе 90; facing = 0xFF для i = n, иначе 1
	ld	a, 90
	ld	(pt_angle), a
	ld	a, 1
	ld	(pt_facing), a
	ld	a, (pt_i)
	cp	1
	jp	z, ang75
	ld	e, a
	ld	a, (pt_n)
	cp	e
	jp	nz, fac_done
	ld	a, 0xFF
	ld	(pt_facing), a
ang75:
	ld	a, 75
	ld	(pt_angle), a
fac_done:
	ld	a, 28
	ld	(pt_y), a
	; any = «хотя бы один dx из -4..4 даёт sup(x+dx, y)» — если да, танк не рисуется
	ld	a, -4
	ld	(pt_dx), a
any_lp:
	call	pt_supx
	jp	c, pt_tables
	ld	hl, pt_dx
	inc	(hl)
	ld	a, (pt_dx)
	cp	5
	jp	nz, any_lp
	; спуск: стереть, y+1, нарисовать корпус; все dx sup — выход
drop_lp:
	ld	a, (pt_x)
	ld	d, a
	ld	a, (pt_y)
	ld	e, a
	call	erase_tank
	ld	hl, pt_y
	inc	(hl)
	ld	a, (pt_x)
	ld	d, a
	ld	a, (pt_y)
	ld	e, a
	ld	a, (pt_i)
	add	a, 3
	call	draw_tank
	ld	a, -4
	ld	(pt_dx), a
all_lp:
	call	pt_supx
	jp	nc, drop_lp
	ld	hl, pt_dx
	inc	(hl)
	ld	a, (pt_dx)
	cp	5
	jp	nz, all_lp
	; танк со стволом + рамка
	ld	a, (pt_x)
	ld	(tb_x), a
	ld	a, (pt_y)
	ld	(tb_y), a
	ld	a, (pt_i)
	ld	(tb_idx), a
	ld	a, (pt_angle)
	ld	(tb_angle), a
	xor	a
	ld	(tb_angle + 1), a
	ld	a, (pt_facing)
	ld	(tb_facing), a
	ld	a, 1
	ld	(tb_alive), a
	call	draw_tank_barrel
	ld	a, (pl_rebound)
	call	draw_frame
	; записи в таблицы
pt_tables:
	ld	hl, tk_y
	call	pt_tab_addr
	ld	a, (pt_y)
	ld	(hl), a
	ld	hl, tk_angle
	call	pt_tab_addr
	ld	a, (pt_angle)
	ld	(hl), a
	ld	hl, tk_facing
	call	pt_tab_addr
	ld	a, (pt_facing)
	ld	(hl), a
	ld	hl, pt_i
	inc	(hl)
	ld	a, (pt_i)
	ld	e, a
	ld	a, (pt_n)
	cp	e
	jp	nc, i_lp
	ret

; sup(x, y): цвет (x, y+1) равен 1 или 2. Вход: pt_x, pt_dx, pt_y. Выход: CF=1 если sup. Портит AF, BC, DE, HL.
pt_supx:
	ld	hl, pt_dx
	ld	a, (pt_x)
	add	a, (hl)
	ld	d, a
	ld	a, (pt_y)
	inc	a
	ld	e, a
	call	getpixel
	cp	1
	jp	z, pt_sup_yes
	cp	2
	jp	z, pt_sup_yes
	xor	a
	ret
pt_sup_yes:
	scf
	ret

; Вход: HL = адрес таблицы (tk_*). Выход: HL = таблица + (pt_i - 1). Портит AF, DE.
pt_tab_addr:
	ld	a, (pt_i)
	dec	a
	ld	e, a
	ld	d, 0
	add	hl, de
	ret
place_end:

pl_rebound:	db	0
tk_x:		ds	4
tk_y:		ds	4
tk_angle:	ds	4
tk_facing:	ds	4

rt_x:		db	0
rt_top:		db	0
pt_n:		db	0
pt_first:	db	0
pt_last:	db	0
pt_rem:		db	0
pt_d:		db	0
pt_q:		db	0
pt_k:		db	0
pt_cnt:		db	0
pt_val:		db	0
pt_i:		db	0
pt_x:		db	0
pt_y:		db	0
pt_angle:	db	0
pt_facing:	db	0
pt_dx:		db	0
