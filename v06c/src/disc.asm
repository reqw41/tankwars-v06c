; Закрашенный круг строками — disc() эталона: огонь и воронка взрыва, шар грязи.
; Строка dy: от cx-(w+1) до cx+(w+1), w — полуширина внешнего кольца из таблицы (disc_tab.inc); обрезка по полю.
; Вход: dk_x, dk_y — центр в координатах экрана (знаковые слова: центр может быть за полем), dk_r — радиус (только из
; таблицы), dk_c — цвет 0..7, dk_el/dk_er — добавка слева и справа: 1,1 — взрыв и грязь; 0,1 — круги гибели танка.
; Заливка идёт байтами: левый неполный байт, целые байты, правый неполный — по каждой из трёх плоскостей.

DK_X0		equ	3
DK_X1		equ	252
DK_Y0		equ	27
DK_Y1		equ	252

disc:
	; пометить столбцы круга для осыпания: центр ± (радиус + 2); центр за экраном — весь экран
	ld	a, (dk_x + 1)
	or	a
	jp	z, dk_mk1
	call	cr_mark_all
	jp	dk_mk2
dk_mk1:
	ld	a, (dk_r)
	add	a, 2
	ld	b, a
	ld	a, (dk_x)
	call	cr_mark_x
dk_mk2:
	ld	a, (dk_r)
	ld	b, a
	ld	hl, dk_tabs
dk_find:
	ld	a, (hl)
	cp	0xFF
	ret	z			; радиуса нет в таблице
	inc	hl
	ld	e, (hl)
	inc	hl
	ld	d, (hl)
	inc	hl
	cp	b
	jp	nz, dk_find
	ex	de, hl
	ld	(dk_tp), hl
	xor	a
	ld	(dk_dy), a
dk_loop:
	ld	hl, (dk_tp)
	ld	c, (hl)			; полуширина внешнего кольца в строке dy
	inc	hl
	ld	(dk_tp), hl
	; x1 = max(cx - (w + el), X0)
	ld	a, (dk_el)
	add	a, c
	cpl
	ld	e, a
	ld	d, 0xFF
	inc	de			; DE = -(w + el)
	ld	hl, (dk_x)
	add	hl, de
	ld	a, h
	or	a
	jp	m, dk_x1min		; отрицательное
	jp	nz, dk_next		; левее поля быть не может: x1 > 255 — строки нет
	ld	a, l
	cp	DK_X0
	jp	nc, dk_x1ok
dk_x1min:
	ld	a, DK_X0
dk_x1ok:
	ld	(dk_x1), a
	; x2 = min(cx + (w + er), X1)
	ld	a, (dk_er)
	add	a, c
	ld	e, a
	ld	d, 0
	ld	hl, (dk_x)
	add	hl, de
	ld	a, h
	or	a
	jp	m, dk_next		; весь отрезок левее экрана
	jp	nz, dk_x2max
	ld	a, l
	cp	DK_X1 + 1
	jp	c, dk_x2ok
dk_x2max:
	ld	a, DK_X1
dk_x2ok:
	ld	(dk_x2), a
	ld	b, a
	ld	a, (dk_x1)
	ld	c, a
	ld	a, b
	cp	c
	jp	c, dk_next		; пустой отрезок
	; строка cy + dy
	ld	a, (dk_dy)
	ld	e, a
	ld	d, 0
	ld	hl, (dk_y)
	add	hl, de
	call	dk_row
	; строка cy - dy (кроме dy = 0)
	ld	a, (dk_dy)
	or	a
	jp	z, dk_next
	cpl
	ld	e, a
	ld	d, 0xFF
	inc	de
	ld	hl, (dk_y)
	add	hl, de
	call	dk_row
dk_next:
	ld	a, (dk_r)
	ld	b, a
	ld	a, (dk_dy)
	cp	b
	ret	z
	inc	a
	ld	(dk_dy), a
	jp	dk_loop

; HL — строка (знаковое слово); рисует отрезок, если строка в поле
dk_row:
	ld	a, h
	or	a
	ret	nz
	ld	a, l
	cp	DK_Y0
	ret	c
	cp	DK_Y1 + 1
	ret	nc
	; провал в hspan

; Горизонтальный отрезок dk_x1..dk_x2 в строке A цветом dk_c.
hspan:
	cpl
	ld	(hs_l), a		; младший байт адреса = 255 - y
	ld	a, (dk_x1)
	ld	d, a
	rrca
	rrca
	rrca
	and	0x1F
	ld	b, a			; столбец байта слева
	ld	a, (dk_x2)
	ld	e, a
	rrca
	rrca
	rrca
	and	0x1F
	sub	b
	ld	(hs_n), a		; байтов после левого
	ld	a, b
	or	0xA0
	ld	(hs_h), a
	ld	a, d
	and	7
	ld	c, a
	ld	b, 0
	ld	hl, hs_lmask
	add	hl, bc
	ld	d, (hl)			; левая маска
	ld	a, e
	and	7
	ld	c, a
	ld	hl, hs_rmask
	add	hl, bc
	ld	e, (hl)			; правая маска
	ld	a, (hs_n)
	or	a
	jp	nz, hs_go
	ld	a, d
	and	e
	ld	d, a			; отрезок в одном байте
hs_go:
	ld	a, (hs_l)
	ld	l, a
	ld	a, (hs_h)
	ld	h, a
	ld	a, (dk_c)
	ld	c, a
	call	hs_plane
	ld	a, (hs_h)
	add	a, 0x20
	ld	h, a
	ld	a, c
	rrca
	ld	c, a
	call	hs_plane
	ld	a, (hs_h)
	add	a, 0x40
	ld	h, a
	ld	a, c
	rrca
	ld	c, a
	; третья плоскость — провал в hs_plane

; H — столбец, L — строка, D/E — левая и правая маски, бит 0 в C — значение плоскости.
hs_plane:
	ld	a, (hs_n)
	ld	b, a
	ld	a, c
	rrca
	jp	c, hs_set
	ld	a, d
	cpl
	and	(hl)
	ld	(hl), a
	ld	a, b
	or	a
	ret	z
	inc	h
	dec	b
	jp	z, hs_clr_r
hs_clr_m:
	ld	(hl), 0
	inc	h
	dec	b
	jp	nz, hs_clr_m
hs_clr_r:
	ld	a, e
	cpl
	and	(hl)
	ld	(hl), a
	ret
hs_set:
	ld	a, d
	or	(hl)
	ld	(hl), a
	ld	a, b
	or	a
	ret	z
	inc	h
	dec	b
	jp	z, hs_set_r
hs_set_m:
	ld	(hl), 0xFF
	inc	h
	dec	b
	jp	nz, hs_set_m
hs_set_r:
	ld	a, e
	or	(hl)
	ld	(hl), a
	ret

hs_lmask:	db	0xFF, 0x7F, 0x3F, 0x1F, 0x0F, 0x07, 0x03, 0x01
hs_rmask:	db	0x80, 0xC0, 0xE0, 0xF0, 0xF8, 0xFC, 0xFE, 0xFF
	include	"disc_tab.inc"
disc_end:

dk_x:		dw	0
dk_y:		dw	0
dk_el:		db	1
dk_er:		db	1
dk_r:		db	0
dk_c:		db	0
dk_x1:		db	0
dk_x2:		db	0
dk_dy:		db	0
dk_tp:		dw	0
hs_l:		db	0
hs_h:		db	0
hs_n:		db	0
