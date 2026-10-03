; Корпус танка (33 точки) и крестик (5). Смещение — слово dx+dy*256.

SPRITE:
	dw	0, 1, 2, 3, 4, -1, -2, -3, -4
	dw	-256, -256-2, -256-3, -256-4, -256+2, -256+3, -256+4
	dw	-512, -512-1, -512-2, -512-3, -512+1, -512+2, -512+3
	dw	-768, -768-1, -768-2, -768-3, -768+1, -768+2, -768+3
	dw	-1024, -1024-1, -1024+1
SPRITE_N	equ	33

CROSS:
	dw	0, 256, -256, 1, -1
CROSS_N	equ	5

draw_tank:
	ld	(tk_c), a
	ld	l, d
	ld	h, e
	ld	(tk_base), hl
	ld	hl, SPRITE
	ld	a, SPRITE_N
	jp	spr_go

erase_tank:
	xor	a
	jp	draw_tank

draw_cross:
	ld	(tk_c), a
	ld	l, d
	ld	h, e
	ld	(tk_base), hl
	ld	hl, CROSS
	ld	a, CROSS_N
spr_go:
	ld	(tk_ptr), hl
	ld	(tk_n), a
spr_lp:
	ld	hl, (tk_ptr)
	ld	c, (hl)
	inc	hl
	ld	b, (hl)
	inc	hl
	ld	(tk_ptr), hl
	ld	hl, (tk_base)
	add	hl, bc
	ld	a, l
	rrca
	rrca
	rrca
	and	0x1F
	or	0xA0
	ld	d, a
	ld	a, h
	cpl
	ld	e, a
	ld	a, l
	and	7
	add	a, low pix_mask
	ld	l, a
	ld	a, high pix_mask
	ld	h, a
	ld	c, (hl)
	ld	h, d
	ld	l, e
	ld	a, (tk_c)
	or	a
	jp	z, tk_c0
	cp	3
	jp	z, tk_c3
	cp	4
	jp	z, tk_c4
	call	plot_hlc
	jp	spr_nx
tk_c0:
	ld	a, c
	cpl
	and	(hl)
	ld	(hl), a
	ld	a, h
	add	a, 0x20
	ld	h, a
	ld	a, c
	cpl
	and	(hl)
	ld	(hl), a
	ld	a, h
	add	a, 0x20
	ld	h, a
	ld	a, c
	cpl
	and	(hl)
	ld	(hl), a
	jp	spr_nx
tk_c3:
	ld	a, (hl)
	or	c
	ld	(hl), a
	ld	a, h
	add	a, 0x20
	ld	h, a
	ld	a, (hl)
	or	c
	ld	(hl), a
	ld	a, h
	add	a, 0x20
	ld	h, a
	ld	a, c
	cpl
	and	(hl)
	ld	(hl), a
	jp	spr_nx
tk_c4:
	ld	a, c
	cpl
	and	(hl)
	ld	(hl), a
	ld	a, h
	add	a, 0x20
	ld	h, a
	ld	a, c
	cpl
	and	(hl)
	ld	(hl), a
	ld	a, h
	add	a, 0x20
	ld	h, a
	ld	a, (hl)
	or	c
	ld	(hl), a
spr_nx:
	ld	a, (tk_n)
	dec	a
	ld	(tk_n), a
	jp	nz, spr_lp
	ret
draw_tank_end:
draw_cross_end:

tk_base:	dw	0
tk_ptr:		dw	0
tk_c:		db	0
tk_n:		db	0
