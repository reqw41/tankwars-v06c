; Кольцо эллипса ring() / ringRestore(): 24-бит (r≤61), plot без общего putpixel.
; ring_cx, ring_cy — слова знаковые, ring_r 0..61, ring_c цвет.

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
	call	mul8
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
	xor	a
	ld	(el_px + 2), a
	ld	hl, (el_two_a2)
	ld	a, (el_r)
	ld	e, a
	call	mul16x8
	ld	(el_py), hl
	ld	a, e
	ld	(el_py + 1), a
	ld	a, d
	ld	(el_py + 2), a
	ld	hl, (el_a2)
	ld	a, (el_r)
	ld	e, a
	call	mul16x8
	ld	(el_ar), hl
	ld	a, e
	ld	(el_ar + 1), a
	ld	a, d
	ld	(el_ar + 2), a
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
	ex	de, hl
	ld	hl, (el_b2)
	add	hl, de
	ld	(el_p), hl
	ld	a, 0
	adc	a, 0
	ld	(el_p + 2), a
	ld	hl, el_p
	ld	de, el_ar
	call	sub24
	ld	a, (el_r)
	ld	l, a
	ld	h, 0
	ld	(el_yc), hl
	xor	a
	ld	(el_cl), a
	ld	(el_ch), a
el_w1:
	ld	a, (el_px + 2)
	ld	b, a
	ld	a, (el_py + 2)
	cp	b
	jp	c, el_w2
	jp	nz, el_w1go
	ld	a, (el_px + 1)
	ld	b, a
	ld	a, (el_py + 1)
	cp	b
	jp	c, el_w2
	jp	nz, el_w1go
	ld	a, (el_px)
	ld	b, a
	ld	a, (el_py)
	cp	b
	jp	c, el_w2
	jp	z, el_w2
el_w1go:
	call	el_plot4
	ld	a, 1
	ld	(el_cl), a
	xor	a
	ld	(el_ch), a
	ld	a, (el_p + 2)
	and	0x80
	jp	nz, el_w1b
	ld	a, 1
	ld	(el_ch), a
	ld	hl, (el_yc)
	dec	hl
	ld	(el_yc), hl
	ld	hl, (el_two_a2)
	ex	de, hl
	ld	hl, el_py
	call	sub24_de
	ld	hl, el_p
	ld	de, el_py
	call	sub24
el_w1b:
	ld	hl, (el_two_b2)
	ex	de, hl
	ld	hl, el_px
	call	add24_de
	ld	hl, el_p
	ld	de, el_px
	call	add24
	ld	hl, (el_b2)
	ex	de, hl
	ld	hl, el_p
	call	add24_de
	jp	el_w1

el_w2:
	ld	hl, (el_a2)
	ld	a, l
	ld	c, a
	ld	a, h
	ld	b, a
	ld	hl, (el_b2)
	ld	a, c
	sub	l
	ld	l, a
	ld	a, b
	sbc	a, h
	ld	h, a
	ld	(el_t16), hl
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
	ld	a, l
	ld	(el_tmp), a
	ld	a, h
	ld	(el_tmp + 1), a
	rla
	sbc	a, a
	ld	(el_tmp + 2), a
	ld	hl, el_tmp
	ld	de, el_px
	call	sub24
	ld	hl, el_tmp
	ld	de, el_py
	call	sub24
	ld	hl, el_tmp
	call	sar24
	ld	hl, el_p
	ld	de, el_tmp
	call	add24
el_w2l:
	call	el_plot4
	xor	a
	ld	(el_cl), a
	ld	a, 1
	ld	(el_ch), a
	ld	a, (el_p + 2)
	and	0x80
	jp	z, el_w2g
	ld	a, 1
	ld	(el_cl), a
	ld	hl, (el_two_b2)
	ex	de, hl
	ld	hl, el_px
	call	add24_de
	ld	hl, el_p
	ld	de, el_px
	call	add24
el_w2g:
	ld	hl, (el_two_a2)
	ex	de, hl
	ld	hl, el_py
	call	sub24_de
	ld	hl, el_p
	ld	de, el_py
	call	sub24
	ld	hl, (el_a2)
	ex	de, hl
	ld	hl, el_p
	call	add24_de
	ld	hl, (el_yc)
	dec	hl
	ld	(el_yc), hl
	ld	a, h
	and	0x80
	jp	z, el_w2l
	ret

el_plot4:
	ld	a, (el_cl)
	or	a
	jp	z, ep4_x
	ld	hl, (brx)
	inc	hl
	ld	(brx), hl
	ld	hl, (trx)
	inc	hl
	ld	(trx), hl
	ld	hl, (blx)
	dec	hl
	ld	(blx), hl
	ld	hl, (tlx)
	dec	hl
	ld	(tlx), hl
ep4_x:
	ld	a, (el_ch)
	or	a
	jp	z, ep4_y
	ld	hl, (bry)
	dec	hl
	ld	(bry), hl
	ld	hl, (bly)
	dec	hl
	ld	(bly), hl
	ld	hl, (try)
	inc	hl
	ld	(try), hl
	ld	hl, (tly)
	inc	hl
	ld	(tly), hl
ep4_y:
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

; DE=x, HL=y знаковые; обрезка VIEWPORT, затем адрес+маска.
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
	ld	a, e
	rrca
	rrca
	rrca
	and	0x1F
	or	0xA0
	ld	b, a
	ld	a, l
	cpl
	ld	l, a
	ld	a, e
	and	7
	add	a, low pix_mask
	ld	e, a
	ld	d, high pix_mask
	ld	a, (de)
	ld	c, a
	cpl
	ld	e, a
	ld	h, b
	ld	a, (ring_c)
	ld	d, a
	rrca
	ld	d, a
	jp	nc, rp0c
	ld	a, (hl)
	or	c
	jp	rp0s
rp0c:
	ld	a, e
	and	(hl)
rp0s:
	ld	(hl), a
	ld	a, h
	add	a, 0x20
	ld	h, a
	ld	a, d
	rrca
	ld	d, a
	jp	nc, rp1c
	ld	a, (hl)
	or	c
	jp	rp1s
rp1c:
	ld	a, e
	and	(hl)
rp1s:
	ld	(hl), a
	ld	a, h
	add	a, 0x20
	ld	h, a
	ld	a, d
	rrca
	jp	nc, rp2c
	ld	a, (hl)
	or	c
	ld	(hl), a
	ret
rp2c:
	ld	a, e
	and	(hl)
	ld	(hl), a
	ret

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

; HL * E → 24-bit в A:E:HL?  возвращаем HL=low16, DE=high: mid in E, high in D (D только младший байт 24)
; фактически: result 24 = D:E:L wait I'll use el_mul and return HL=low, DE = byte1 in E, byte2 in D
mul16x8:
	ld	(el_m16), hl
	ld	a, e
	ld	(el_m8), a
	ld	hl, 0
	ld	(el_mul), hl
	xor	a
	ld	(el_mul + 2), a
	ld	b, 8
m168:
	push	bc
	ld	hl, el_mul
	call	shl24
	ld	a, (el_m8)
	rla
	ld	(el_m8), a
	jp	nc, m168n
	ld	hl, (el_m16)
	ex	de, hl
	ld	hl, el_mul
	call	add24_de
m168n:
	pop	bc
	dec	b
	jp	nz, m168
	ld	hl, (el_mul)
	ld	a, (el_mul + 1)
	ld	e, a
	ld	a, (el_mul + 2)
	ld	d, a
	ret

add24:
	ld	a, (de)
	add	a, (hl)
	ld	(hl), a
	inc	hl
	inc	de
	ld	a, (de)
	adc	a, (hl)
	ld	(hl), a
	inc	hl
	inc	de
	ld	a, (de)
	adc	a, (hl)
	ld	(hl), a
	ret

sub24:
	or	a
	ld	a, (de)
	ld	c, a
	ld	a, (hl)
	sbc	a, c
	ld	(hl), a
	inc	hl
	inc	de
	ld	a, (de)
	ld	c, a
	ld	a, (hl)
	sbc	a, c
	ld	(hl), a
	inc	hl
	inc	de
	ld	a, (de)
	ld	c, a
	ld	a, (hl)
	sbc	a, c
	ld	(hl), a
	ret

add24_16:
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
	ret

sub24_16:
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
	ret

sub24_tmp:
	ld	a, (hl)
	ld	(el_tmp), a
	inc	hl
	ld	a, (hl)
	ld	(el_tmp + 1), a
	inc	hl
	ld	a, (hl)
	ld	(el_tmp + 2), a
	ld	hl, el_tmp
	jp	sub24

shl24:
	or	a
	ld	a, (hl)
	rla
	ld	(hl), a
	inc	hl
	ld	a, (hl)
	rla
	ld	(hl), a
	inc	hl
	ld	a, (hl)
	rla
	ld	(hl), a
	ret

sar24:
	inc	hl
	inc	hl
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
	ret

add24_de:
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
	ret

sub24_de:
	ld	a, (hl)
	sub	e
	ld	(hl), a
	inc	hl
	ld	a, (hl)
	sbc	a, d
	ld	(hl), a
	inc	hl
	ld	a, (hl)
	sbc	a, 0
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
el_px:		ds	3
el_py:		ds	3
el_p:		ds	3
el_ar:		ds	3
el_tmp:		ds	3
el_mul:		ds	3
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
