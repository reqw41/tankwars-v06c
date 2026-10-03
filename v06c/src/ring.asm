; Кольцо эллипса ring() / ringRestore() эталона: ellipsePoints + VIEWPORT.
; ring_cx, ring_cy — слова знаковые (координаты поля), ring_r 0..61, ring_c цвет.
; ringRestore при нулевом фоне = ring с цветом 0.

ring_restore:
	xor	a
	ld	(ring_c), a
ring:
	ld	hl, (ring_cx)
	ld	de, 3
	add	hl, de
	ld	(el_x), hl
	ld	hl, (ring_cy)
	ld	de, 27
	add	hl, de
	ld	(el_y), hl
	ld	a, (ring_r)
	ld	(el_r), a
	ld	e, a
	call	mul8			; HL = r*r = a2
	ld	(el_a2), hl
	ld	(el_b2), hl
	add	hl, hl
	ld	(el_two_a2), hl
	ld	(el_two_b2), hl
	ld	hl, (el_x)
	ld	(brx), hl
	ld	(trx), hl
	ld	(blx), hl
	ld	(tlx), hl
	ld	a, (el_r)
	ld	e, a
	ld	d, 0
	ld	hl, (el_y)
	add	hl, de
	ld	(bry), hl
	ld	(bly), hl
	ld	a, (el_r)
	ld	c, a
	xor	a
	ld	b, a
	ld	hl, (el_y)
	ld	a, l
	sub	c
	ld	l, a
	ld	a, h
	sbc	a, b
	ld	h, a
	ld	(try), hl
	ld	(tly), hl
	ld	hl, 0
	ld	(el_px), hl
	ld	(el_px + 2), hl
	jp	el_py32

; --- 16-bit HL * 8-bit E → 32-bit result in (el_mul)
mul16x8:
	ld	(el_m16), hl
	ld	a, e
	ld	(el_m8), a
	ld	hl, 0
	ld	(el_mul), hl
	ld	(el_mul + 2), hl
	ld	b, 8
m168:
	push	bc
	ld	hl, el_mul
	call	shl32
	ld	a, (el_m8)
	rla
	ld	(el_m8), a
	jp	nc, m168n
	ld	hl, (el_m16)
	ex	de, hl
	ld	hl, el_mul
	call	add32_de
m168n:
	pop	bc
	dec	b
	jp	nz, m168
	ld	hl, (el_mul + 2)
	ex	de, hl
	ld	hl, (el_mul)
	ret

el_py32:
	ld	hl, (el_two_a2)
	ld	a, (el_r)
	ld	e, a
	call	mul16x8
	ld	(el_py), hl
	ex	de, hl
	ld	(el_py + 2), hl
	; p = (a2>>2) + b2 - a2*r
	ld	hl, (el_a2)
	ld	a, (el_r)
	ld	e, a
	call	mul16x8
	ld	(el_ar), hl
	ex	de, hl
	ld	(el_ar + 2), hl
	; a2>>2
	ld	hl, (el_a2)
	or	a
	ld	a, h
	rra
	ld	h, a
	ld	a, l
	rra
	ld	l, a
	or	a
	ld	a, h
	rra
	ld	h, a
	ld	a, l
	rra
	ld	l, a
	ld	(el_t16), hl
	; p32 = (a2>>2) + b2 - a2*r
	ld	hl, 0
	ld	(el_p + 2), hl
	ld	hl, (el_t16)
	push	hl
	ld	hl, (el_b2)
	ex	de, hl
	pop	hl
	add	hl, de
	ld	(el_p), hl
	jp	nc, el_p_nc
	ld	hl, (el_p + 2)
	inc	hl
	ld	(el_p + 2), hl
el_p_nc:
	; p -= a2*r
	ld	hl, el_p
	ld	de, el_ar
	call	sub32
	ld	a, (el_r)
	ld	l, a
	ld	h, 0
	ld	(el_yc), hl
	xor	a
	ld	(el_cl), a
	ld	(el_ch), a
el_w1:
	; while px-py < 0
	ld	hl, el_px
	ld	de, el_py
	call	sub32_tmp		; tmp = px-py
	ld	a, (el_tmp + 3)
	and	0x80
	jp	z, el_w2
	call	el_plot4
	ld	a, 1
	ld	(el_cl), a
	xor	a
	ld	(el_ch), a
	ld	a, (el_p + 3)
	and	0x80
	jp	nz, el_w1b		; p<0 skip
	; p>=0: ch=1, yc--, py -= two_a2, p -= py
	ld	a, 1
	ld	(el_ch), a
	ld	hl, (el_yc)
	dec	hl
	ld	(el_yc), hl
	ld	hl, el_py
	ld	de, el_two_a2
	call	sub32_de16
	ld	hl, el_p
	ld	de, el_py
	call	sub32
el_w1b:
	; px += two_b2; p += px + b2
	ld	hl, el_px
	ld	de, el_two_b2
	call	add32_de16
	ld	hl, el_p
	ld	de, el_px
	call	add32
	ld	hl, el_p
	ld	de, el_b2
	call	add32_de16
	jp	el_w1

el_w2:
	; t = a2-b2; t = t+(t>>1); p += (t-px-py)>>1
	; a2==b2 for circle → t=0
	ld	hl, (el_a2)
	push	hl
	ld	hl, (el_b2)
	ex	de, hl
	pop	hl
	ld	a, l
	sub	e
	ld	l, a
	ld	a, h
	sbc	a, d
	ld	h, a
	ld	(el_t16), hl
	; t += t>>1
	ld	e, l
	ld	d, h
	or	a
	ld	a, h
	rra
	ld	h, a
	ld	a, l
	rra
	ld	l, a
	add	hl, de
	ld	(el_t16), hl
	; tmp = t - px - py (32)
	ld	a, (el_t16)
	ld	(el_tmp), a
	ld	a, (el_t16 + 1)
	ld	(el_tmp + 1), a
	xor	a
	ld	(el_tmp + 2), a
	ld	(el_tmp + 3), a
	; sign-extend t16
	ld	a, (el_t16 + 1)
	and	0x80
	jp	z, el_tpos
	ld	a, 0xFF
	ld	(el_tmp + 2), a
	ld	(el_tmp + 3), a
el_tpos:
	ld	hl, el_tmp
	ld	de, el_px
	call	sub32
	ld	hl, el_tmp
	ld	de, el_py
	call	sub32
	; >>1 arithmetic
	ld	hl, el_tmp
	call	sar32
	ld	hl, el_p
	ld	de, el_tmp
	call	add32
el_w2l:
	call	el_plot4
	xor	a
	ld	(el_cl), a
	ld	a, 1
	ld	(el_ch), a
	ld	a, (el_p + 3)
	and	0x80
	jp	z, el_w2g
	; p<0: cl=1, px += two_b2, p += px
	ld	a, 1
	ld	(el_cl), a
	ld	hl, el_px
	ld	de, el_two_b2
	call	add32_de16
	ld	hl, el_p
	ld	de, el_px
	call	add32
el_w2g:
	; py -= two_a2; p -= py - a2; yc--
	ld	hl, el_py
	ld	de, el_two_a2
	call	sub32_de16
	ld	hl, el_p
	ld	de, el_py
	call	sub32
	ld	hl, el_p
	ld	de, el_a2
	call	add32_de16
	ld	hl, (el_yc)
	dec	hl
	ld	(el_yc), hl
	ld	a, h
	and	0x80
	jp	z, el_w2l
	ret

el_plot4:
	ld	a, (el_cl)
	ld	c, a
	ld	b, 0
	ld	hl, (brx)
	add	hl, bc
	ld	(brx), hl
	ld	a, (el_ch)
	ld	c, a
	ld	hl, (bry)
	ld	a, l
	sub	c
	ld	l, a
	ld	a, h
	sbc	a, b
	ld	h, a
	ld	(bry), hl
	ld	hl, (trx)
	ld	a, (el_cl)
	ld	c, a
	add	hl, bc
	ld	(trx), hl
	ld	hl, (try)
	ld	a, (el_ch)
	ld	c, a
	add	hl, bc
	ld	(try), hl
	ld	hl, (blx)
	ld	a, (el_cl)
	ld	c, a
	ld	a, l
	sub	c
	ld	l, a
	ld	a, h
	sbc	a, b
	ld	h, a
	ld	(blx), hl
	ld	hl, (bly)
	ld	a, (el_ch)
	ld	c, a
	ld	a, l
	sub	c
	ld	l, a
	ld	a, h
	sbc	a, b
	ld	h, a
	ld	(bly), hl
	ld	hl, (tlx)
	ld	a, (el_cl)
	ld	c, a
	ld	a, l
	sub	c
	ld	l, a
	ld	a, h
	sbc	a, b
	ld	h, a
	ld	(tlx), hl
	ld	hl, (tly)
	ld	a, (el_ch)
	ld	c, a
	add	hl, bc
	ld	(tly), hl
	ld	hl, (brx)
	ex	de, hl
	ld	hl, (bry)
	call	plot_vp
	ld	hl, (trx)
	ex	de, hl
	ld	hl, (try)
	call	plot_vp
	ld	hl, (blx)
	ex	de, hl
	ld	hl, (bly)
	call	plot_vp
	ld	hl, (tlx)
	ex	de, hl
	ld	hl, (tly)
	jp	plot_vp

; DE=x, HL=y знаковые
plot_vp:
	ld	a, d
	or	a
	ret	nz
	ld	a, h
	or	a
	ret	nz
	ld	a, e
	cp	3
	ret	c
	cp	253
	ret	nc
	ld	a, l
	cp	27
	ret	c
	cp	253
	ret	nc
	ld	d, e
	ld	e, l
	ld	a, (ring_c)
	jp	putpixel

; A*E → HL (беззнаковое 8×8)
mul8:
	ld	d, 0
	ld	h, d
	ld	l, d
	or	a
	ret	z
	ld	b, 8
mul8l:
	add	hl, hl
	rla
	jp	nc, mul8n
	add	hl, de
mul8n:
	dec	b
	jp	nz, mul8l
	ret

; dest HL += (DE) 32-bit. HL ptr dest, DE ptr src
add32:
	ld	b, 4
	or	a
ad32:
	ld	a, (de)
	adc	a, (hl)
	ld	(hl), a
	inc	hl
	inc	de
	dec	b
	jp	nz, ad32
	ret

sub32:
	ld	b, 4
	or	a
sb32:
	ld	a, (de)
	ld	c, a
	ld	a, (hl)
	sbc	a, c
	ld	(hl), a
	inc	hl
	inc	de
	dec	b
	jp	nz, sb32
	ret

; dest HL += unsigned 16 at (DE)
add32_de16:
	ld	a, (de)
	add	a, (hl)
	ld	(hl), a
	inc	hl
	inc	de
	ld	a, (de)
	adc	a, (hl)
	ld	(hl), a
	inc	hl
	ld	a, 0
	adc	a, (hl)
	ld	(hl), a
	inc	hl
	ld	a, 0
	adc	a, (hl)
	ld	(hl), a
	ret

sub32_de16:
	ld	a, (hl)
	ld	b, a
	ld	a, (de)
	ld	c, a
	ld	a, b
	sub	c
	ld	(hl), a
	inc	hl
	inc	de
	ld	a, (hl)
	ld	b, a
	ld	a, (de)
	ld	c, a
	ld	a, b
	sbc	a, c
	ld	(hl), a
	inc	hl
	ld	a, (hl)
	sbc	a, 0
	ld	(hl), a
	inc	hl
	ld	a, (hl)
	sbc	a, 0
	ld	(hl), a
	ret

; tmp = (HL) - (DE) 32
sub32_tmp:
	push	hl
	ld	hl, el_tmp
	ld	b, 4
	xor	a
stz:
	ld	(hl), a
	inc	hl
	dec	b
	jp	nz, stz
	pop	hl
	push	de
	ld	de, el_tmp
	ld	b, 4
stc:
	ld	a, (hl)
	ld	(de), a
	inc	hl
	inc	de
	dec	b
	jp	nz, stc
	pop	de
	ld	hl, el_tmp
	jp	sub32

shl32:
	ld	b, 4
	or	a
sh32:
	ld	a, (hl)
	rla
	ld	(hl), a
	inc	hl
	dec	b
	jp	nz, sh32
	ret

sar32:
	ld	bc, 3
	add	hl, bc
	ld	a, (hl)
	ld	b, a
	rlca
	ld	a, b
	rra
	ld	(hl), a
	dec	hl
	ld	a, (hl)
	rra
	ld	(hl), a
	dec	hl
	ld	a, (hl)
	rra
	ld	(hl), a
	dec	hl
	ld	a, (hl)
	rra
	ld	(hl), a
	ret

; dest ptr HL += DE as 16-bit unsigned into 32
add32_de:
	ld	a, e
	add	a, (hl)
	ld	(hl), a
	inc	hl
	ld	a, d
	adc	a, (hl)
	ld	(hl), a
	inc	hl
	ld	a, 0
	adc	a, (hl)
	ld	(hl), a
	inc	hl
	ld	a, 0
	adc	a, (hl)
	ld	(hl), a
	ret

ring_end:

ring_cx:	dw	0
ring_cy:	dw	0
ring_r:		db	0
ring_c:		db	0
el_x:		dw	0
el_y:		dw	0
el_r:		db	0
el_a2:		dw	0
el_b2:		dw	0
el_two_a2:	dw	0
el_two_b2:	dw	0
el_px:		ds	4
el_py:		ds	4
el_p:		ds	4
el_ar:		ds	4
el_tmp:		ds	4
el_mul:		ds	4
el_m16:		dw	0
el_m8:		db	0
el_t16:		dw	0
el_yc:		dw	0
el_cl:		db	0
el_ch:		db	0
brx:		dw	0
bry:		dw	0
trx:		dw	0
try:		dw	0
blx:		dw	0
bly:		dw	0
tlx:		dw	0
tly:		dw	0
