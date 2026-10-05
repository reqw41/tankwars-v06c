; Знак и строка: drawChar / drawText. Шрифт 96×8 байт-строк (font2rows.mjs из FONT эталона): знаки 20h..5Fh
; (строчные латинские → прописные) и русские прописные А..Я с кодами CP866 80h..9Fh.

font:
	include	"font.inc"

draw_char:
	ld	a, (ch_col)
	cp	32
	ret	nc
	ld	a, (ch_row)
	cp	32
	ret	nc
	ld	a, (ch)
	cp	0x80
	jp	c, dc_lat
	cp	0xA0
	jp	nc, dc_qm
	sub	0x40			; А..Я — знаки 64..95
	jp	dc_idx
dc_lat:
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
dc_idx:
	ld	l, a
	ld	h, 0
	add	hl, hl
	add	hl, hl
	add	hl, hl
	ld	de, font
	add	hl, de
	ld	(ch_gly), hl
	ld	a, (ch_col)
	or	0xA0
	ld	d, a
	ld	b, a
	ld	a, (ch_row)
	add	a, a
	add	a, a
	add	a, a
	cpl
	ld	e, a
	ld	a, (ch_c)
	cp	2
	jp	z, dc_c2
	ld	b, 8
dc_y:
	ld	hl, (ch_gly)
	ld	c, (hl)
	inc	hl
	ld	(ch_gly), hl
	ld	h, d
	ld	l, e
	ld	a, (ch_c)
	rrca
	jp	nc, dc_a0
	ld	a, c
	ld	(hl), a
	jp	dc_a1
dc_a0:
	xor	a
	ld	(hl), a
dc_a1:
	ld	a, h
	add	a, 0x20
	ld	h, a
	ld	a, (ch_c)
	rrca
	rrca
	jp	nc, dc_b0
	ld	a, c
	ld	(hl), a
	jp	dc_b1
dc_b0:
	xor	a
	ld	(hl), a
dc_b1:
	ld	a, h
	add	a, 0x20
	ld	h, a
	ld	a, (ch_c)
	rrca
	rrca
	rrca
	jp	nc, dc_c0
	ld	a, c
	ld	(hl), a
	jp	dc_c1
dc_c0:
	xor	a
	ld	(hl), a
dc_c1:
	dec	e
	dec	b
	jp	nz, dc_y
	ret

dc_c2:
	ld	hl, (ch_gly)
	dup	8
	ld	c, (hl)
	inc	hl
	ex	de, hl
	xor	a
	ld	(hl), a
	ld	a, h
	add	a, 0x20
	ld	h, a
	ld	(hl), c
	add	a, 0x20
	ld	h, a
	xor	a
	ld	(hl), a
	ld	h, b
	dec	l
	ex	de, hl
	edup
	ret

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
