; dx, dy для углов 0..90 (web/data/barrel.json)
barrel_tab:
	db	7, 0
	db	7, 0
	db	7, 0
	db	7, 0
	db	7, 0
	db	7, 0
	db	7, 0
	db	7, 0
	db	7, 1
	db	7, 1
	db	7, 1
	db	7, 1
	db	7, 1
	db	7, 1
	db	7, 1
	db	7, 2
	db	7, 2
	db	7, 2
	db	7, 2
	db	7, 2
	db	7, 2
	db	7, 2
	db	7, 2
	db	7, 3
	db	7, 3
	db	7, 3
	db	7, 3
	db	7, 3
	db	7, 3
	db	6, 3
	db	6, 4
	db	6, 4
	db	6, 4
	db	6, 4
	db	6, 4
	db	6, 4
	db	6, 4
	db	6, 4
	db	6, 4
	db	6, 5
	db	6, 5
	db	6, 5
	db	5, 5
	db	5, 5
	db	5, 5
	db	5, 5
	db	5, 5
	db	5, 5
	db	5, 5
	db	5, 6
	db	5, 6
	db	5, 6
	db	4, 6
	db	4, 6
	db	4, 6
	db	4, 6
	db	4, 6
	db	4, 6
	db	4, 6
	db	4, 6
	db	3, 6
	db	3, 6
	db	3, 7
	db	3, 7
	db	3, 7
	db	3, 7
	db	3, 7
	db	3, 7
	db	2, 7
	db	2, 7
	db	2, 7
	db	2, 7
	db	2, 7
	db	2, 7
	db	2, 7
	db	2, 7
	db	1, 7
	db	1, 7
	db	1, 7
	db	1, 7
	db	1, 7
	db	1, 7
	db	1, 7
	db	0, 7
	db	0, 7
	db	0, 7
	db	0, 7
	db	0, 7
	db	0, 7
	db	0, 7
	db	0, 7

draw_tank_barrel:
	ld	a, (tb_alive)
	or	a
	ret	z
	ld	a, (tb_x)
	ld	d, a
	ld	a, (tb_y)
	ld	e, a
	ld	a, (tb_idx)
	add	a, 3
	call	draw_tank
	call	tb_ends
	ld	a, (tb_idx)
	add	a, 3
	ld	(ln_c), a
	jp	line

erase_tank_barrel:
	ld	a, (tb_x)
	ld	d, a
	ld	a, (tb_y)
	ld	e, a
	call	erase_tank
	call	tb_ends
	xor	a
	ld	(ln_c), a
	jp	line

tb_ends:
	ld	a, (tb_x)
	ld	(ln_x1), a
	xor	a
	ld	(ln_x1 + 1), a
	ld	a, (tb_y)
	ld	(ln_y1), a
	xor	a
	ld	(ln_y1 + 1), a
	ld	hl, (tb_angle)
	add	hl, hl
	ld	de, barrel_tab
	add	hl, de
	ld	c, (hl)
	inc	hl
	ld	b, (hl)
	ld	a, (tb_x)
	ld	l, a
	ld	h, 0
	ld	a, (tb_facing)
	cp	1
	jp	nz, tb_fn
	ld	a, l
	add	a, c
	ld	(ln_x2), a
	ld	a, h
	adc	a, 0
	ld	(ln_x2 + 1), a
	jp	tb_y2
tb_fn:
	ld	a, l
	sub	c
	ld	(ln_x2), a
	ld	a, h
	sbc	a, 0
	ld	(ln_x2 + 1), a
tb_y2:
	ld	a, (tb_y)
	sub	b
	ld	(ln_y2), a
	ld	a, 0
	sbc	a, 0
	ld	(ln_y2 + 1), a
	ret

draw_tank_barrel_end:

tb_x:		db	0
tb_y:		db	0
tb_idx:		db	0
tb_angle:	dw	0
tb_facing:	db	0
tb_alive:	db	0
