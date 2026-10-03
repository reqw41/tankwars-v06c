; Корпус танка (33 точки SPRITE) и крестик мяча (5 точек).
; Координаты как эталон: o = (y*256+x + dy*256+dx) & 0xffff, затем байты x,y.
; draw_tank: D=x, E=y, A=цвет. erase_tank: то же, цвет 0.
; draw_cross: D=x, E=y, A=цвет (3) или 0 при стирании.

SPRITE:
	db	0,0, 1,0, 2,0, 3,0, 4,0, -1,0, -2,0, -3,0, -4,0
	db	0,-1, -2,-1, -3,-1, -4,-1, 2,-1, 3,-1, 4,-1
	db	0,-2, -1,-2, -2,-2, -3,-2, 1,-2, 2,-2, 3,-2
	db	0,-3, -1,-3, -2,-3, -3,-3, 1,-3, 2,-3, 3,-3
	db	0,-4, -1,-4, 1,-4
SPRITE_N	equ	33

CROSS:
	db	0,0, 0,1, 0,-1, 1,0, -1,0
CROSS_N	equ	5

draw_tank:
	ld	(tk_c), a
	ld	a, d
	ld	(tk_x), a
	ld	a, e
	ld	(tk_y), a
	ld	hl, SPRITE
	ld	b, SPRITE_N
	jp	spr_go

erase_tank:
	xor	a
	jp	draw_tank

draw_cross:
	ld	(tk_c), a
	ld	a, d
	ld	(tk_x), a
	ld	a, e
	ld	(tk_y), a
	ld	hl, CROSS
	ld	b, CROSS_N
spr_go:
	ld	a, (hl)
	ld	c, a
	inc	hl
	ld	a, (hl)
	inc	hl
	push	hl
	push	bc
	ld	e, a			; dy
	ld	a, (tk_x)
	ld	l, a
	ld	a, (tk_y)
	ld	h, a			; HL = y*256+x
	ld	a, c
	ld	c, a			; dx
	rla
	sbc	a, a
	ld	b, a
	add	hl, bc			; + dx (знаковый)
	ld	a, h
	add	a, e			; + dy*256
	ld	h, a
	ld	d, l			; x
	ld	e, h			; y
	ld	a, (tk_c)
	call	putpixel
	pop	bc
	pop	hl
	dec	b
	jp	nz, spr_go
	ret
draw_tank_end:
draw_cross_end:

tk_x:	db	0
tk_y:	db	0
tk_c:	db	0
