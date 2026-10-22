; Рамка поля — drawFrame(v, rebound) эталона (в оригинале 2b39:0386): два прямоугольника цветом 2 и, если стены
; не отражают, линия земли по дну поля цветом 1. Геометрия — docs/spec/v06c.md, «Экран 256×256»:
;   внешний прямоугольник (0,24)–(255,255), внутренний (2,26)–(253,253), линия земли y = 252, x = 3..252.
; Эталон рисует их четырьмя line(); картинка от порядка не зависит, поэтому здесь сразу байтами: горизонтали —
; целыми байтами с масками краёв, вертикали — шагом DEC L по готовому адресу.
; Вход: A = «стены отражают» (0 — нарисовать и линию земли). Портит все регистры.

draw_frame:
	ld	(fr_reb), a
; внешний прямоугольник: строки 24 и 255 целиком, столбцы x = 0 (байт 0, маска 80h) и x = 255 (байт 31, маска 01h)
; от L = 231 (y = 24) до L = 0 (y = 255)
	ld	a, 24
	call	fr_row_full2
	ld	a, 255
	call	fr_row_full2
	ld	d, 0xA0
	ld	c, 0x80
	ld	l, 231
	ld	e, 0
	call	fr_vert2
	ld	d, 0xBF
	ld	c, 0x01
	ld	l, 231
	ld	e, 0
	call	fr_vert2
; внутренний: строки 26 и 253 от x = 2 до x = 253 (маски краёв 3Fh и FCh), столбцы x = 2 (20h) и x = 253 (04h)
; от L = 229 (y = 26) до L = 2 (y = 253)
	ld	a, 26
	ld	c, 0x3F
	ld	b, 0xFC
	call	fr_row_mid2
	ld	a, 253
	ld	c, 0x3F
	ld	b, 0xFC
	call	fr_row_mid2
	ld	d, 0xA0
	ld	c, 0x20
	ld	l, 229
	ld	e, 2
	call	fr_vert2
	ld	d, 0xBF
	ld	c, 0x04
	ld	l, 229
	ld	e, 2
	call	fr_vert2
; линия земли y = 252 от x = 3 до x = 252 (маски 1Fh и F8h) — только когда стены не отражают
	ld	a, (fr_reb)
	or	a
	ret	nz
	ld	a, 252
	cpl
	ld	l, a
	ld	c, 0x1F
	ld	b, 0xF8
	jp	fr_row_mid1

; Полная строка y в A, цвет 2 (плоскость C).
fr_row_full2:
	cpl
	ld	l, a
	ld	h, 0xA0
	xor	a
	ld	b, 32
frf_a:
	ld	(hl), a
	inc	h
	dec	b
	jp	nz, frf_a
	ld	h, 0xC0
	ld	a, 0xFF
	ld	b, 32
frf_c:
	ld	(hl), a
	inc	h
	dec	b
	jp	nz, frf_c
	ld	h, 0xE0
	xor	a
	ld	b, 32
frf_e:
	ld	(hl), a
	inc	h
	dec	b
	jp	nz, frf_e
	ret

; Строка y=A, цвет 2; крайние маски C (col0) и B (col31), середина 0xFF.
fr_row_mid2:
	cpl
	ld	l, a
	ld	a, b
	ld	(fr_mr), a
	ld	a, c
	ld	(fr_ml), a
	ld	h, 0xA0
	call	fr_rm2
	ld	h, 0xC0
	call	fr_rm2
	ld	h, 0xE0
; одна плоскость строки: в C000h точки ставятся, в A000h и E000h снимаются (цвет 2 = только бит 1)
fr_rm2:
	ld	a, h
	ld	(fr_ph), a
	and	0xE0
	cp	0xC0
	jp	z, fr_rm2s
	ld	a, (fr_ml)
	cpl
	and	(hl)
	ld	(hl), a
	inc	h
	ld	b, 30
	xor	a
fr_rm2z:
	ld	(hl), a
	inc	h
	dec	b
	jp	nz, fr_rm2z
	ld	a, (fr_mr)
	cpl
	and	(hl)
	ld	(hl), a
	ret
; плоскость C000h
fr_rm2s:
	ld	a, (fr_ml)
	or	(hl)
	ld	(hl), a
	inc	h
	ld	b, 30
	ld	a, 0xFF
fr_rm2f:
	ld	(hl), a
	inc	h
	dec	b
	jp	nz, fr_rm2f
	ld	a, (fr_mr)
	or	(hl)
	ld	(hl), a
	ret

; Строка y уже в L, цвет 1; маски C/B как mid.
fr_row_mid1:
	ld	a, b
	ld	(fr_mr), a
	ld	a, c
	ld	(fr_ml), a
	ld	h, 0xA0
	ld	a, (fr_ml)
	or	(hl)
	ld	(hl), a
	inc	h
	ld	b, 30
	ld	a, 0xFF
frm1a:
	ld	(hl), a
	inc	h
	dec	b
	jp	nz, frm1a
	ld	a, (fr_mr)
	or	(hl)
	ld	(hl), a
	ld	h, 0xC0
	call	frm1cl
	ld	h, 0xE0
frm1cl:
	ld	a, (fr_ml)
	cpl
	and	(hl)
	ld	(hl), a
	inc	h
	ld	b, 30
	xor	a
frm1z:
	ld	(hl), a
	inc	h
	dec	b
	jp	nz, frm1z
	ld	a, (fr_mr)
	cpl
	and	(hl)
	ld	(hl), a
	ret

; Вертикаль цвета 2: D=H плоскости A, C=маска, L=старт, E=конечный L включительно.
; за два шага на виток — развёрнутый цикл
fr_vert2:
	ld	h, d
	ld	a, c
	cpl
	ld	b, a
frv2:
	ld	a, b
	and	(hl)
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
	ld	a, b
	and	(hl)
	ld	(hl), a
	ld	a, h
	sub	0x40
	ld	h, a
	ld	a, l
	cp	e
	ret	z
	dec	l
	ld	a, b
	and	(hl)
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
	ld	a, b
	and	(hl)
	ld	(hl), a
	ld	a, h
	sub	0x40
	ld	h, a
	ld	a, l
	cp	e
	ret	z
	dec	l
	jp	frv2

draw_frame_end:

; fr_ph записывается в fr_rm2, но нигде не читается
fr_reb:	db	0
fr_ml:	db	0
fr_mr:	db	0
fr_ph:	db	0
