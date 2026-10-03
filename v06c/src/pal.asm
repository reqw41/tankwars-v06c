; Палитра 16 регистров парами. 0..3 — страница, 4..7 — tankRGB(p) затем R,G>>3, B>>4.
; pal_men/divr/divg/divb: по 4 слова (игроки 0..3).

pal_apply:
	ld	de, pal_page
	ld	hl, pal_byte
	ld	b, 4
pa_cp:
	ld	a, (de)
	ld	(hl), a
	inc	de
	inc	hl
	dec	b
	jp	nz, pa_cp
	xor	a
	ld	(pal_cur), a
pa_tn:
	call	tank_rgb_byte
	ld	hl, pal_byte + 4
	ld	a, (pal_cur)
	ld	e, a
	ld	d, 0
	add	hl, de
	ld	a, (tr_byte)
	ld	(hl), a
	ld	a, (pal_cur)
	inc	a
	ld	(pal_cur), a
	cp	4
	jp	nz, pa_tn
	ld	a, 0x88
	out	(0), a
	xor	a
	out	(3), a
	out	(1), a
	ld	b, 0
	ld	hl, RESULT
pa_out:
	ld	a, b
	and	0x04
	ld	c, 0
	jp	z, pa_p1
	ld	c, 1
pa_p1:
	ld	a, b
	and	0x02
	jp	z, pa_p2
	ld	a, c
	or	2
	ld	c, a
pa_p2:
	ld	a, b
	and	0x01
	jp	z, pa_p3
	ld	a, c
	or	4
	ld	c, a
pa_p3:
	ld	e, c
	ld	d, 0
	push	hl
	ld	hl, pal_byte
	add	hl, de
	ld	c, (hl)
	pop	hl
	ld	a, b
	out	(2), a
	ld	a, c
	out	(0x0C), a
	out	(0x0C), a
	ld	(hl), c
	inc	hl
	inc	b
	ld	a, b
	cp	16
	jp	c, pa_out
	xor	a
	out	(2), a
	ret

tank_rgb_byte:
	ld	a, (pal_cur)
	ld	e, a
	ld	d, 0
	ld	hl, pal_men
	add	hl, de
	add	hl, de
	ld	e, (hl)
	inc	hl
	ld	d, (hl)
	ld	a, d
	and	0x80
	jp	z, tr_ok
	xor	a
	ld	(tr_byte), a
	ret
tr_ok:
	ld	h, d
	ld	l, e
	ld	b, 63
	call	mulhl_b
	ld	de, 100
	call	udiv_hl_de
	ld	(tr_L), hl
	ld	a, (pal_cur)
	ld	e, a
	ld	d, 0
	ld	hl, pal_divr
	add	hl, de
	add	hl, de
	ld	e, (hl)
	inc	hl
	ld	d, (hl)
	ld	hl, (tr_L)
	call	udiv_hl_de
	ld	a, l
	rrca
	rrca
	rrca
	and	7
	ld	(tr_r), a
	ld	a, (pal_cur)
	ld	e, a
	ld	d, 0
	ld	hl, pal_divg
	add	hl, de
	add	hl, de
	ld	e, (hl)
	inc	hl
	ld	d, (hl)
	ld	hl, (tr_L)
	call	udiv_hl_de
	ld	a, l
	rrca
	rrca
	rrca
	and	7
	ld	(tr_g), a
	ld	a, (pal_cur)
	ld	e, a
	ld	d, 0
	ld	hl, pal_divb
	add	hl, de
	add	hl, de
	ld	e, (hl)
	inc	hl
	ld	d, (hl)
	ld	hl, (tr_L)
	call	udiv_hl_de
	ld	a, l
	rrca
	rrca
	rrca
	rrca
	and	3
	ld	(tr_b), a
	rlca
	rlca
	rlca
	rlca
	rlca
	rlca
	ld	b, a
	ld	a, (tr_g)
	rlca
	rlca
	rlca
	or	b
	ld	b, a
	ld	a, (tr_r)
	or	b
	ld	(tr_byte), a
	ret

; HL * B → HL (младшие 16)
mulhl_b:
	ld	a, b
	or	a
	jp	nz, mhb0
	ld	hl, 0
	ret
mhb0:
	ex	de, hl
	ld	hl, 0
mhb1:
	add	hl, de
	dec	b
	jp	nz, mhb1
	ret

; HL / DE → HL. DE=0 → 0. Частное циклом (L≤63 в tankRGB).
udiv_hl_de:
	ld	a, d
	or	e
	jp	nz, ud0
	ld	hl, 0
	ret
ud0:
	ld	bc, 0
ud_cmp:
	ld	a, h
	cp	d
	jp	c, ud_done
	jp	nz, ud_sub
	ld	a, l
	cp	e
	jp	c, ud_done
ud_sub:
	ld	a, l
	sub	e
	ld	l, a
	ld	a, h
	sbc	a, d
	ld	h, a
	inc	bc
	jp	ud_cmp
ud_done:
	ld	h, b
	ld	l, c
	ret

pal_apply_end:

pal_page:
	db	0x00, 0x29, 0xAD, 0x77
pal_byte:	ds	8
pal_men:	ds	8
pal_divr:	ds	8
pal_divg:	ds	8
pal_divb:	ds	8
pal_cur:	db	0
tr_L:		dw	0
tr_r:		db	0
tr_g:		db	0
tr_b:		db	0
tr_byte:	db	0
ud_n:		db	0
