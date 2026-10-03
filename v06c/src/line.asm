; Линия — тот же обход, что line() в web/tankwars.js (не «учебный» Брезенхем).
; Входы: ln_x1, ln_y1, ln_x2, ln_y2 (слова, знаковые), ln_c (байт).
; Горизонталь: запись байтами; вертикаль: шаг DEC L.

line:
	ld	hl, (ln_x1)
	ex	de, hl
	ld	hl, (ln_x2)
	call	sub16
	ld	a, h
	or	l
	jp	nz, ln_notvert
	ld	hl, (ln_y2)
	ex	de, hl
	ld	hl, (ln_y1)
	call	cmp16
	jp	c, ln_v_y1
	jp	z, ln_v_y1
	ld	hl, (ln_y2)
	ld	(ln_ya), hl
	ld	hl, (ln_y1)
	ld	(ln_yb), hl
	jp	ln_v_go
ln_v_y1:
	ld	hl, (ln_y1)
	ld	(ln_ya), hl
	ld	hl, (ln_y2)
	ld	(ln_yb), hl
ln_v_go:
	ld	hl, (ln_ya)
	ex	de, hl
	ld	hl, (ln_yb)
	call	sub16
	inc	hl
	ld	(ln_cnt), hl
	ld	a, (ln_x1 + 1)
	or	a
	jp	nz, ln_v_slow
	ld	a, (ln_ya + 1)
	or	a
	jp	nz, ln_v_slow
	ld	a, (ln_yb + 1)
	or	a
	jp	nz, ln_v_slow
	ld	a, (ln_x1)
	ld	d, a
	ld	a, (ln_ya)
	ld	e, a
	ld	a, (ln_c)
	call	putpixel
	ld	hl, (ln_cnt)
	dec	hl
	ld	a, h
	or	l
	jp	z, ln_ret
	ld	(ln_cnt), hl
	; HL после putpixel — не адрес; считаем адрес заново и шагаем DEC L
	ld	a, (ln_x1)
	ld	d, a
	ld	a, (ln_ya)
	ld	e, a
	call	ln_addr
ln_v_fast:
	dec	l
	ld	a, (ln_c)
	call	plot_hlc
	push	hl
	ld	hl, (ln_cnt)
	dec	hl
	ld	(ln_cnt), hl
	ld	a, h
	or	l
	pop	hl
	jp	nz, ln_v_fast
	jp	ln_ret

ln_v_slow:
	ld	hl, (ln_x1)
	ld	(ln_x), hl
	ld	hl, (ln_ya)
	ld	(ln_y), hl
ln_v_lp:
	ld	hl, (ln_cnt)
	ld	a, h
	or	l
	jp	z, ln_ret
	dec	hl
	ld	(ln_cnt), hl
	call	ln_plot
	ld	hl, (ln_y)
	inc	hl
	ld	(ln_y), hl
	jp	ln_v_lp

ln_notvert:
	ld	hl, (ln_x1)
	ex	de, hl
	ld	hl, (ln_x2)
	call	sub16
	ld	a, h
	and	0x80
	jp	z, ln_cxpos
	ld	hl, (ln_x1)
	ld	(ln_tmp), hl
	ld	hl, (ln_x2)
	ld	(ln_x1), hl
	ld	hl, (ln_tmp)
	ld	(ln_x2), hl
	ld	hl, (ln_y1)
	ld	(ln_tmp), hl
	ld	hl, (ln_y2)
	ld	(ln_y1), hl
	ld	hl, (ln_tmp)
	ld	(ln_y2), hl
ln_cxpos:
	ld	hl, (ln_x1)
	ex	de, hl
	ld	hl, (ln_x2)
	call	sub16
	ld	(ln_cx), hl
	ld	hl, (ln_y1)
	ex	de, hl
	ld	hl, (ln_y2)
	call	sub16
	ld	a, h
	or	l
	jp	nz, ln_nothoriz
	ld	a, (ln_x1 + 1)
	or	a
	jp	nz, ln_h_slow
	ld	a, (ln_x2 + 1)
	or	a
	jp	nz, ln_h_slow
	ld	a, (ln_y1 + 1)
	or	a
	jp	nz, ln_h_slow
	jp	ln_horiz

ln_h_slow:
	ld	hl, (ln_cx)
	inc	hl
	ld	(ln_cnt), hl
	ld	hl, (ln_x1)
	ld	(ln_x), hl
	ld	hl, (ln_y1)
	ld	(ln_y), hl
ln_h_lp:
	ld	hl, (ln_cnt)
	ld	a, h
	or	l
	jp	z, ln_ret
	dec	hl
	ld	(ln_cnt), hl
	call	ln_plot
	ld	hl, (ln_x)
	inc	hl
	ld	(ln_x), hl
	jp	ln_h_lp

; Горизонталь y в 0..255, x1<=x2 в 0..255: маски краёв и полные байты.
; Бит 7 — левая точка столбца (x&7==0). Сдвиг маски — логический (RRA при CY=0).
ln_horiz:
	ld	a, (ln_y1)
	cpl
	ld	(ln_row), a
	ld	a, (ln_x1)
	ld	c, a
	ld	a, (ln_x2)
	ld	b, a
	ld	a, c
	rrca
	rrca
	rrca
	and	0x1F
	ld	d, a
	ld	a, b
	rrca
	rrca
	rrca
	and	0x1F
	ld	e, a
	ld	a, d
	cp	e
	jp	nz, ln_h_span
	ld	a, c
	and	7
	ld	c, a
	ld	a, b
	and	7
	sub	c
	inc	a
	ld	b, a
	call	mask_shr_c
	call	mask_or_b
	jp	ln_apply

ln_h_span:
	push	de
	push	bc
	ld	a, c
	and	7
	ld	c, a
	ld	a, 8
	sub	c
	ld	b, a
	call	mask_shr_c
	call	mask_or_b
	call	ln_apply
	pop	bc
	pop	de
	inc	d
	ld	a, d
	cp	e
	jp	z, ln_h_last
ln_h_mid:
	ld	c, 0xFF
	push	de
	push	bc
	call	ln_apply
	pop	bc
	pop	de
	inc	d
	ld	a, d
	cp	e
	jp	nz, ln_h_mid
ln_h_last:
	ld	a, b
	and	7
	inc	a
	ld	b, a
	ld	a, 0x80
	ld	e, a
	call	mask_or_b
	jp	ln_apply

; C = сколько раз сдвинуть 80h вправо → E. C=0 → E=80h.
mask_shr_c:
	ld	a, 0x80
	ld	e, a
	ld	a, c
	or	a
	ret	z
msc_lp:
	xor	a
	ld	a, e
	rra
	ld	e, a
	dec	c
	jp	nz, msc_lp
	ret

; C = OR B бит начиная с E (логически вправо). Результат в C.
mask_or_b:
	ld	c, 0
mob_lp:
	ld	a, c
	or	e
	ld	c, a
	xor	a
	ld	a, e
	rra
	ld	e, a
	dec	b
	jp	nz, mob_lp
	ret

; D=столбец 0..31, C=маска, ln_row, ln_c
ln_apply:
	ld	a, d
	and	0x1F
	or	0xA0
	ld	h, a
	ld	a, (ln_row)
	ld	l, a
	ld	a, (ln_c)
	ld	b, a
	ld	a, c
	cpl
	ld	e, a
	call	ln_pl
	ld	a, h
	add	a, 0x20
	ld	h, a
	call	ln_pl
	ld	a, h
	add	a, 0x20
	ld	h, a
	jp	ln_pl
ln_pl:
	ld	a, b
	rrca
	ld	b, a
	jp	nc, ln_pl0
	ld	a, (hl)
	or	c
	ld	(hl), a
	ret
ln_pl0:
	ld	a, e
	and	(hl)
	ld	(hl), a
	ret

ln_nothoriz:
	ld	a, 1
	ld	(ln_sy), a
	ld	hl, (ln_y1)
	ex	de, hl
	ld	hl, (ln_y2)
	call	sub16
	ld	a, h
	and	0x80
	jp	z, ln_bxpos
	ld	a, 0xFF
	ld	(ln_sy), a
	call	neg16
ln_bxpos:
	ld	(ln_bx), hl
	xor	a
	ld	(ln_ymajor), a
	ld	hl, (ln_cx)
	ex	de, hl
	ld	hl, (ln_bx)
	call	cmp16
	jp	z, ln_prep
	jp	c, ln_prep
	ld	a, 1
	ld	(ln_ymajor), a
	ld	hl, (ln_bx)
	ld	(ln_tmp), hl
	ld	hl, (ln_cx)
	ld	(ln_bx), hl
	ld	hl, (ln_tmp)
	ld	(ln_cx), hl
ln_prep:
	ld	hl, (ln_bx)
	add	hl, hl
	ld	(ln_d2), hl
	ld	hl, (ln_cx)
	ex	de, hl
	ld	hl, (ln_d2)
	call	sub16
	ld	(ln_err), hl
	ld	hl, (ln_cx)
	add	hl, hl
	ex	de, hl
	ld	hl, (ln_d2)
	call	sub16
	ld	(ln_d22), hl
	ld	hl, (ln_cx)
	inc	hl
	ld	(ln_cnt), hl
	ld	hl, (ln_x1)
	ld	(ln_x), hl
	ld	hl, (ln_y1)
	ld	(ln_y), hl
ln_loop:
	ld	hl, (ln_cnt)
	ld	a, h
	or	l
	jp	z, ln_ret
	dec	hl
	ld	(ln_cnt), hl
	call	ln_plot
	ld	hl, (ln_x)
	inc	hl
	ld	(ln_x), hl
	ld	a, (ln_ymajor)
	or	a
	jp	nz, ln_ym
	ld	hl, (ln_err)
	ld	a, h
	and	0x80
	jp	z, ln_xm_ge
	ld	hl, (ln_d2)
	ex	de, hl
	ld	hl, (ln_err)
	add	hl, de
	ld	(ln_err), hl
	jp	ln_loop
ln_xm_ge:
	ld	hl, (ln_d22)
	ex	de, hl
	ld	hl, (ln_err)
	add	hl, de
	ld	(ln_err), hl
	call	ln_step_y
	jp	ln_loop
ln_ym:
	call	ln_step_y
	ld	hl, (ln_err)
	ld	a, h
	and	0x80
	jp	z, ln_ym_ge
	ld	hl, (ln_d2)
	ex	de, hl
	ld	hl, (ln_err)
	add	hl, de
	ld	(ln_err), hl
	ld	hl, (ln_x)
	dec	hl
	ld	(ln_x), hl
	jp	ln_loop
ln_ym_ge:
	ld	hl, (ln_d22)
	ex	de, hl
	ld	hl, (ln_err)
	add	hl, de
	ld	(ln_err), hl
	jp	ln_loop

ln_ret:
	ret

ln_plot:
	ld	hl, (ln_x)
	ld	c, l
	ld	b, h
	ld	hl, (ln_y)
	ld	e, l
	ld	d, h
	ld	a, (ln_c)
	jp	putpixel16

ln_step_y:
	ld	a, (ln_sy)
	ld	hl, (ln_y)
	cp	1
	jp	z, ln_yinc
	dec	hl
	ld	(ln_y), hl
	ret
ln_yinc:
	inc	hl
	ld	(ln_y), hl
	ret

; D=x, E=y → HL адрес A, C маска (оба 0..255)
ln_addr:
	ld	a, d
	rrca
	rrca
	rrca
	and	0x1F
	or	0xA0
	ld	h, a
	ld	a, e
	cpl
	ld	l, a
	ld	a, d
	and	7
	ld	c, 0x80
	jp	z, ln_ad0
	ld	e, a
ln_ads:
	ld	a, c
	rrca
	ld	c, a
	dec	e
	jp	nz, ln_ads
ln_ad0:
	ret

sub16:
	ld	a, l
	sub	e
	ld	l, a
	ld	a, h
	sbc	a, d
	ld	h, a
	ret

neg16:
	ld	a, l
	cpl
	ld	l, a
	ld	a, h
	cpl
	ld	h, a
	inc	hl
	ret

cmp16:
	ld	a, h
	cp	d
	ret	nz
	ld	a, l
	cp	e
	ret
line_end:

ln_x1:		dw	0
ln_y1:		dw	0
ln_x2:		dw	0
ln_y2:		dw	0
ln_c:		db	0
ln_tmp:		dw	0
ln_cx:		dw	0
ln_bx:		dw	0
ln_d2:		dw	0
ln_d22:		dw	0
ln_err:		dw	0
ln_cnt:		dw	0
ln_x:		dw	0
ln_y:		dw	0
ln_ya:		dw	0
ln_yb:		dw	0
ln_sy:		db	0
ln_ymajor:	db	0
ln_row:		db	0
