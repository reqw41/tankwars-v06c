; Заливка экрана цветом A (0..7). Панель y=0..23 — clear_panel (цвет 0).

fill_screen:
	ld	b, a
	rrca
	sbc	a, a
	ld	(fl_p0), a
	ld	a, b
	rrca
	rrca
	sbc	a, a
	ld	(fl_p1), a
	ld	a, b
	rrca
	rrca
	rrca
	sbc	a, a
	ld	(fl_p2), a
	ld	a, (fl_p0)
	ld	hl, 0xC000
	call	fill_8k
	ld	a, (fl_p1)
	ld	hl, 0xE000
	call	fill_8k
	ld	a, (fl_p2)
	ld	hl, 0x0000
	jp	fill_8k

; A байт, HL = адрес сразу за плоскостью (C000/E000/0000). 4096× PUSH.
fill_8k:
	ld	(fl_end), hl
	ld	d, a
	ld	e, a
	ld	hl, 0
	add	hl, sp
	ld	(fl_save), hl
	ld	hl, (fl_end)
	ld	sp, hl
	ld	b, 0
f8_lp:
	push	de
	push	de
	push	de
	push	de
	push	de
	push	de
	push	de
	push	de
	push	de
	push	de
	push	de
	push	de
	push	de
	push	de
	push	de
	push	de
	dec	b
	jp	nz, f8_lp
	ld	hl, (fl_save)
	ld	sp, hl
	ret

clear_screen:
	xor	a
	jp	fill_screen

clear_panel:
	xor	a
	ld	h, 0xA0
	call	clr24
	ld	h, 0xC0
	call	clr24
	ld	h, 0xE0
clr24:
	ld	d, 32
c24c:
	ld	l, 232
	dup	3
	ld	(hl), a
	inc	l
	ld	(hl), a
	inc	l
	ld	(hl), a
	inc	l
	ld	(hl), a
	inc	l
	ld	(hl), a
	inc	l
	ld	(hl), a
	inc	l
	ld	(hl), a
	inc	l
	ld	(hl), a
	inc	l
	edup
	inc	h
	dec	d
	jp	nz, c24c
	ret

fill_screen_end:
clear_screen_end:
clear_panel_end:

fl_p0:	db	0
fl_p1:	db	0
fl_p2:	db	0
fl_save:	dw	0
fl_end:	dw	0
