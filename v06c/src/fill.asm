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
	ld	hl, 0xA000
	ld	a, (fl_p0)
	call	fill_8k
	ld	hl, 0xC000
	ld	a, (fl_p1)
	call	fill_8k
	ld	hl, 0xE000
	ld	a, (fl_p2)
	jp	fill_8k

; HL начало плоскости, A байт, 32 столбца × 256.
fill_8k:
	ld	d, 32
f8c:
	ld	e, a
f8r:
	ld	(hl), a
	inc	l
	jp	nz, f8r
	inc	h
	ld	a, e
	dec	d
	jp	nz, f8c
	ret

clear_screen:
	xor	a
	jp	fill_screen

; Строки y=0..23 (L=232..255) во всех столбцах трёх плоскостей, цвет 0.
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
c24r:
	ld	(hl), a
	inc	l
	jp	nz, c24r
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
