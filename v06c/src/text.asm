; Знак и строка — drawChar / drawText эталона (docs/spec/v06c-screen.md, «Текст»).
; Экран — 32×32 знакоместа 8×8; знак 5×7 стоит в столбцах 1..5 и строках 0..6 знакоместа, остальное знакоместо
; закрашивается цветом 0 — так новый текст поверх старого не требует отдельной очистки.
; Шрифт font.inc — 96 знаков по 8 байт-строк (бит 7 — левая точка), его делает v06c/tools/font2rows.mjs из таблицы
; FONT эталона: знаки 20h..5Fh и русские прописные А..Я (коды CP866 80h..9Fh, знаки 64..95). Строчные латинские
; выводятся прописными, всё остальное — знаком «?».
;
;   draw_char: ch_col, ch_row (0..31), ch (код), ch_c (цвет 0..7). Знакоместо вне экрана не рисуется.
;   draw_text: DE = строка, B = длина (0 — ничего); с ch_col вправо, ch_row и ch_c — как у draw_char.
; Портят все регистры.

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
	sub	0x40		; А..Я (80h..9Fh) — знаки 64..95
	jp	dc_idx
; латиница: строчные -> прописные; коды вне 20h..5Fh -> «?»
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
; A = номер знака 0..95 -> адрес глифа font + 8·A
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
	or	0xA0			; столбец знакоместа = столбец байтов: D — старший байт адреса в A000h
	ld	d, a
	ld	b, a
	ld	a, (ch_row)
	add	a, a
	add	a, a
	add	a, a
	cpl			; E = 255 − 8·строка: младший байт адреса верхней точечной строки знакоместа
	ld	e, a
	ld	a, (ch_c)
	cp	2
	jp	z, dc_c2
	ld	b, 8
; общий путь, любой цвет: каждая из трёх плоскостей получает строку глифа или 0 по своему биту цвета
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

; Цвет 2 (цвет текста и рамки — почти весь текст игры): только плоскость C000h, A000h и E000h — нули.
; Цикл развёрнут на 8 строк; B хранит старший байт адреса A000h, чтобы вернуться к нему без вычитания.
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
