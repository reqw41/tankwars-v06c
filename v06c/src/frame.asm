; Рамка поля — drawFrame(v, rebound) эталона PROFILE_V06C.
; A=0: две рамки цветом 2 и линия земли цветом 1; A≠0: без земли.

draw_frame:
	ld	(fr_reb), a
	ld	a, 0
	ld	(ln_x1), a
	xor	a
	ld	(ln_x1 + 1), a
	ld	a, 24
	ld	(ln_y1), a
	xor	a
	ld	(ln_y1 + 1), a
	ld	a, 255
	ld	(ln_x2), a
	xor	a
	ld	(ln_x2 + 1), a
	ld	a, 255
	ld	(ln_y2), a
	xor	a
	ld	(ln_y2 + 1), a
	ld	a, 2
	ld	(ln_c), a
	call	rect
	ld	a, 2
	ld	(ln_x1), a
	xor	a
	ld	(ln_x1 + 1), a
	ld	a, 26
	ld	(ln_y1), a
	xor	a
	ld	(ln_y1 + 1), a
	ld	a, 253
	ld	(ln_x2), a
	xor	a
	ld	(ln_x2 + 1), a
	ld	a, 253
	ld	(ln_y2), a
	xor	a
	ld	(ln_y2 + 1), a
	ld	a, 2
	ld	(ln_c), a
	call	rect
	ld	a, (fr_reb)
	or	a
	ret	nz
	ld	a, 3
	ld	(ln_x1), a
	xor	a
	ld	(ln_x1 + 1), a
	ld	a, 252
	ld	(ln_y1), a
	xor	a
	ld	(ln_y1 + 1), a
	ld	a, 252
	ld	(ln_x2), a
	xor	a
	ld	(ln_x2 + 1), a
	ld	a, 252
	ld	(ln_y2), a
	xor	a
	ld	(ln_y2 + 1), a
	ld	a, 1
	ld	(ln_c), a
	jp	line

; Прямоугольник: стороны через line(), концы в ln_x1/y1/x2/y2, цвет ln_c.
rect:
	ld	hl, (ln_x1)
	ld	(fr_x1), hl
	ld	hl, (ln_y1)
	ld	(fr_y1), hl
	ld	hl, (ln_x2)
	ld	(fr_x2), hl
	ld	hl, (ln_y2)
	ld	(fr_y2), hl
	; x2,y1 — x2,y2
	ld	hl, (fr_x2)
	ld	(ln_x1), hl
	ld	hl, (fr_y1)
	ld	(ln_y1), hl
	ld	hl, (fr_x2)
	ld	(ln_x2), hl
	ld	hl, (fr_y2)
	ld	(ln_y2), hl
	call	line
	; x1,y1 — x1,y2
	ld	hl, (fr_x1)
	ld	(ln_x1), hl
	ld	hl, (fr_y1)
	ld	(ln_y1), hl
	ld	hl, (fr_x1)
	ld	(ln_x2), hl
	ld	hl, (fr_y2)
	ld	(ln_y2), hl
	call	line
	; x1,y2 — x2,y2
	ld	hl, (fr_x1)
	ld	(ln_x1), hl
	ld	hl, (fr_y2)
	ld	(ln_y1), hl
	ld	hl, (fr_x2)
	ld	(ln_x2), hl
	ld	hl, (fr_y2)
	ld	(ln_y2), hl
	call	line
	; x1,y1 — x2,y1
	ld	hl, (fr_x1)
	ld	(ln_x1), hl
	ld	hl, (fr_y1)
	ld	(ln_y1), hl
	ld	hl, (fr_x2)
	ld	(ln_x2), hl
	ld	hl, (fr_y1)
	ld	(ln_y2), hl
	jp	line

draw_frame_end:

fr_reb:	db	0
fr_x1:	dw	0
fr_y1:	dw	0
fr_x2:	dw	0
fr_y2:	dw	0
