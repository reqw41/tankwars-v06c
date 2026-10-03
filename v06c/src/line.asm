; Линия — тот же обход, что line() в web/tankwars.js (не «учебный» Брезенхем).
; Входы: ln_x1, ln_y1, ln_x2, ln_y2 (слова, знаковые), ln_c (байт).
; 8080: нет ld de,(nn) / ld (nn),de — только ld hl,(nn) / ld (nn),hl.

line:
	ld	hl, (ln_x1)
	ex	de, hl
	ld	hl, (ln_x2)
	call	sub16			; HL = x2-x1 = cx
	ld	a, h
	or	l
	jp	nz, ln_notvert
	; cx==0: вертикаль от min(y) до max(y)
	ld	hl, (ln_y2)
	ex	de, hl
	ld	hl, (ln_y1)
	call	cmp16			; y1 ? y2
	jp	c, ln_v_y1		; y1 < y2
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
	inc	hl			; count = yb-ya+1
	ld	(ln_cnt), hl
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
	; if cx<0: swap endpoints
	ld	hl, (ln_x1)
	ex	de, hl
	ld	hl, (ln_x2)
	call	sub16			; cx = x2-x1
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
	call	sub16			; bx = y2-y1
	ld	a, h
	or	l
	jp	nz, ln_nothoriz
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

ln_nothoriz:
	ld	a, 1
	ld	(ln_sy), a
	ld	hl, (ln_y1)
	ex	de, hl
	ld	hl, (ln_y2)
	call	sub16			; bx = y2-y1
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
	call	cmp16			; bx ? cx
	jp	z, ln_prep		; JS: ymajor только при bx > cx
	jp	c, ln_prep		; bx < cx
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
	call	sub16			; err = d2-cx
	ld	(ln_err), hl
	ld	hl, (ln_cx)
	add	hl, hl			; 2*cx
	ex	de, hl
	ld	hl, (ln_d2)
	call	sub16			; d22 = d2-2*cx
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

; HL = HL - DE
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

; беззнаковое HL ? DE: CF если HL<DE, ZF если равны
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
