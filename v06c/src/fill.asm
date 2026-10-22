; Заливка экрана и очистка панели.
;   fill_screen:  A = цвет 0..7 — все три плоскости целиком (каждая — FFh или 00h по своему биту цвета).
;   clear_screen: то же цветом 0.
;   clear_panel:  строки 0..23 (панель хода, docs/spec/v06c-screen.md) цветом 0 во всех плоскостях.
; Портят все регистры.
;
; Заливка идёт командой PUSH: стек ставится на конец плоскости, и каждая PUSH пишет два байта за 11 тактов — это
; быстрее любого цикла LD (HL),A. В игре (ifdef GAME) на это время прерывания запрещаются: прерывание кадра положило бы
; адрес возврата прямо в плоскость. Стенд и так работает без прерываний.

fill_screen:
	ld	b, a
	rrca
	sbc	a, a		; бит 0 цвета -> 00h или FFh для A000h
	ld	(fl_p0), a
	ld	a, b
	rrca
	rrca
	sbc	a, a		; бит 1 -> C000h
	ld	(fl_p1), a
	ld	a, b
	rrca
	rrca
	rrca
	sbc	a, a		; бит 2 -> E000h
	ld	(fl_p2), a
	ld	a, (fl_p0)
	ld	hl, 0xC000
	call	fill_8k
	ld	a, (fl_p1)
	ld	hl, 0xE000
	call	fill_8k
	ld	a, (fl_p2)
	ld	hl, 0x0000		; конец плоскости E000h: стек заворачивает с 0000h на FFFFh
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
	ifdef	GAME
	di			; стек стоит на экране: прерывание испортило бы плоскость
	endif
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
	ifdef	GAME
	ei
	endif
	ret

clear_screen:
	xor	a
	jp	fill_screen

; панель — строки y = 0..23, то есть младшие байты адреса 232..255 в каждом из 32 столбцов
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
