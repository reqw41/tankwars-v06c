; Закрашенный круг строками — disc() эталона: огонь и воронка взрыва, шар грязи.
; Строка dy: от cx-(w+1) до cx+(w+1), w — полуширина внешнего кольца из таблицы (disc_tab.inc); обрезка по полю.
; Вход: dk_x, dk_y — центр в координатах экрана (байты), dk_r — радиус (только из таблицы), dk_c — цвет 0..7.
; Заливка идёт байтами: левый неполный байт, целые байты, правый неполный — по каждой из трёх плоскостей.

DK_X0		equ	3
DK_X1		equ	252
DK_Y0		equ	27
DK_Y1		equ	252

disc:
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
	ld	c, (hl)
	inc	c			; полуширина + 1
	inc	hl
	ld	(dk_tp), hl
	ld	a, (dk_x)
	ld	b, a
	sub	c
	jp	c, dk_x1min
	cp	DK_X0
	jp	nc, dk_x1ok
dk_x1min:
	ld	a, DK_X0
dk_x1ok:
	ld	(dk_x1), a
	ld	a, b
	add	a, c
	jp	c, dk_x2max
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
	jp	c, dk_next		; пустой отрезок (центр за полем)
	; строка cy + dy
	ld	a, (dk_dy)
	ld	b, a
	ld	a, (dk_y)
	add	a, b
	jp	c, dk_up
	cp	DK_Y1 + 1
	jp	nc, dk_up
	cp	DK_Y0
	jp	c, dk_up
	call	hspan
dk_up:
	ld	a, (dk_dy)
	or	a
	jp	z, dk_next
	ld	b, a
	ld	a, (dk_y)
	sub	b
	jp	c, dk_next
	cp	DK_Y0
	jp	c, dk_next
	cp	DK_Y1 + 1
	jp	nc, dk_next
	call	hspan
dk_next:
	ld	a, (dk_r)
	ld	b, a
	ld	a, (dk_dy)
	cp	b
	ret	z
	inc	a
	ld	(dk_dy), a
	jp	dk_loop

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

dk_x:		db	0
dk_y:		db	0
dk_r:		db	0
dk_c:		db	0
dk_x1:		db	0
dk_x2:		db	0
dk_dy:		db	0
dk_tp:		dw	0
hs_l:		db	0
hs_h:		db	0
hs_n:		db	0
