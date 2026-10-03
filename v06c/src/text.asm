; Знак и строка: drawChar / drawText эталона. Шрифт 64×5 байт, бит 0 — верх.
; Знакоместо 8×8 = один столбец байт; фон клетки пишется 0.

font:
	include	"font.inc"

draw_char:
	ld	a, (ch_col)
	and	0x80
	ret	nz
	ld	a, (ch_col)
	cp	32
	ret	nc
	ld	a, (ch_row)
	and	0x80
	ret	nz
	ld	a, (ch_row)
	cp	32
	ret	nc
	ld	a, (ch)
	cp	'a'
	jp	c, dc_nu
	cp	'z' + 1
	jp	nc, dc_nu
	sub	32
dc_nu:
	cp	0x20
	jp	c, dc_qm
	cp	0x60
	jp	c, dc_ok
dc_qm:
	ld	a, 0x3F
dc_ok:
	sub	0x20
	ld	e, a
	ld	d, 0
	ld	h, d
	ld	l, a
	add	hl, hl
	add	hl, hl
	add	hl, de
	ld	de, font
	add	hl, de
	ld	(ch_gly), hl
	ld	a, (ch_col)
	or	0xA0
	ld	(ch_h), a
	ld	a, (ch_row)
	add	a, a
	add	a, a
	add	a, a
	cpl
	ld	(ch_l), a
	xor	a
	ld	(ch_yi), a
dc_y:
	ld	a, (ch_yi)
	cp	7
	ld	c, 0
	jp	z, dc_put
	ld	hl, (ch_gly)
	ld	c, 0
	ld	a, 0x40
	ld	(ch_m), a
	ld	b, 5
dc_colb:
	ld	a, (hl)
	ld	e, a
	ld	a, (ch_yi)
	or	a
	jp	z, dc_tst
	ld	d, a
dc_shr:
	xor	a
	ld	a, e
	rra
	ld	e, a
	dec	d
	jp	nz, dc_shr
dc_tst:
	ld	a, e
	and	1
	jp	z, dc_nx
	ld	a, (ch_m)
	or	c
	ld	c, a
dc_nx:
	ld	a, (ch_m)
	or	a
	rra
	ld	(ch_m), a
	inc	hl
	dec	b
	jp	nz, dc_colb
dc_put:
	ld	a, (ch_h)
	ld	h, a
	ld	a, (ch_l)
	ld	l, a
	ld	a, (ch_c)
	ld	b, a
	call	dc_plane
	ld	a, h
	add	a, 0x20
	ld	h, a
	call	dc_plane
	ld	a, h
	add	a, 0x20
	ld	h, a
	call	dc_plane
	ld	a, (ch_l)
	dec	a
	ld	(ch_l), a
	ld	a, (ch_yi)
	inc	a
	ld	(ch_yi), a
	cp	8
	jp	nz, dc_y
	ret

dc_plane:
	ld	a, b
	rrca
	ld	b, a
	jp	nc, dc_z
	ld	a, c
	ld	(hl), a
	ret
dc_z:
	xor	a
	ld	(hl), a
	ret

; DE = адрес строки, B = длина, ch_col/ch_row/ch_c заданы
draw_text:
	ld	a, b
	or	a
	ret	z
dtxt_lp:
	ld	a, (de)
	ld	(ch), a
	push	de
	push	bc
	call	draw_char
	pop	bc
	pop	de
	inc	de
	ld	a, (ch_col)
	inc	a
	ld	(ch_col), a
	dec	b
	jp	nz, dtxt_lp
	ret

draw_char_end:
draw_text_end:

ch_col:	db	0
ch_row:	db	0
ch:	db	0
ch_c:	db	0
ch_gly:	dw	0
ch_h:	db	0
ch_l:	db	0
ch_yi:	db	0
ch_m:	db	0
