; Осыпание crumbleColumns(v, bg=0): байтовые столбцы, поле x 3..252, y 27..253.
; Столбец без «земля над пустотой» пропускается (байты трёх плоскостей).

crumble:
	ld	a, 0xA0
	ld	(cr_ah), a
	xor	a
	ld	(cr_col), a
cr_cols:
	ld	a, (cr_col)
	or	a
	ld	b, 0x1F
	jp	z, cr_gotm
	cp	31
	ld	b, 0xFF
	jp	nz, cr_gotm
	ld	b, 0xF8
cr_gotm:
	ld	a, b
	ld	(cr_vm), a
	ld	a, 227
	ld	(cr_n), a
	ld	a, (cr_ah)
	ld	h, a
	ld	l, 2
	xor	a
	ld	c, a
	ld	e, a
cr_sk:
	ld	a, h
	add	a, 0x20
	ld	h, a
	ld	a, (hl)
	ld	(cr_pc), a
	ld	a, h
	add	a, 0x20
	ld	h, a
	ld	a, (hl)
	ld	(cr_pe), a
	ld	a, h
	sub	0x40
	ld	h, a
	ld	a, (hl)
	ld	(cr_pa), a
	ld	b, a
	ld	a, (cr_pc)
	or	b
	ld	b, a
	ld	a, (cr_pe)
	or	b
	ld	(cr_occ), a
	cpl
	ld	(cr_em), a
	ld	a, (cr_pc)
	cpl
	ld	b, a
	ld	a, (cr_pe)
	cpl
	and	b
	ld	b, a
	ld	a, (cr_pa)
	and	b
	ld	b, a
	and	c
	or	e
	ld	e, a
	ld	a, b
	cpl
	ld	b, a
	ld	a, (cr_occ)
	and	b
	cpl
	and	c
	ld	c, a
	ld	a, (cr_em)
	or	c
	ld	c, a
	inc	l
	ld	a, (cr_n)
	dec	a
	ld	(cr_n), a
	jp	nz, cr_sk
	ld	a, (cr_vm)
	and	e
	jp	z, cr_nxt
	ld	hl, cr_fl
	ld	b, 8
	ld	a, 0xFF
cr_fli:
	ld	(hl), a
	inc	hl
	dec	b
	jp	nz, cr_fli
	ld	a, 227
	ld	(cr_n), a
	ld	a, (cr_ah)
	ld	h, a
	ld	l, 2
cr_row:
	ld	a, l
	ld	(cr_l), a
	ld	a, h
	add	a, 0x20
	ld	h, a
	ld	a, (hl)
	ld	(cr_pc), a
	ld	a, h
	add	a, 0x20
	ld	h, a
	ld	a, (hl)
	ld	(cr_pe), a
	ld	a, h
	sub	0x40
	ld	h, a
	ld	a, (hl)
	ld	(cr_pa), a
	ld	a, 0x80
	ld	(cr_bit), a
	xor	a
	ld	(cr_bi), a
cr_bits:
	ld	a, (cr_vm)
	ld	d, a
	ld	a, (cr_bit)
	and	d
	jp	z, cr_bn
	ld	d, a
	ld	a, (cr_pa)
	ld	e, a
	ld	a, (cr_pc)
	or	e
	ld	e, a
	ld	a, (cr_pe)
	or	e
	and	d
	jp	z, cr_emp
	ld	a, (cr_pc)
	ld	e, a
	ld	a, (cr_pe)
	or	e
	and	d
	jp	nz, cr_rst
	ld	a, (cr_bi)
	ld	e, a
	ld	d, 0
	ld	hl, cr_fl
	add	hl, de
	ld	a, (hl)
	cp	0xFF
	jp	z, cr_rst
	ld	e, a
	ld	a, (cr_ah)
	ld	h, a
	ld	a, (cr_l)
	ld	l, a
	ld	a, (cr_bit)
	cpl
	and	(hl)
	ld	(hl), a
	ld	l, e
	ld	a, (cr_bit)
	or	(hl)
	ld	(hl), a
	inc	e
	ld	a, (cr_bi)
	ld	c, a
	ld	b, 0
	ld	hl, cr_fl
	add	hl, bc
	ld	(hl), e
	jp	cr_bn
cr_emp:
	ld	a, (cr_bi)
	ld	e, a
	ld	d, 0
	ld	hl, cr_fl
	add	hl, de
	ld	a, (hl)
	cp	0xFF
	jp	nz, cr_bn
	ld	a, (cr_l)
	ld	(hl), a
	jp	cr_bn
cr_rst:
	ld	a, (cr_bi)
	ld	e, a
	ld	d, 0
	ld	hl, cr_fl
	add	hl, de
	ld	a, 0xFF
	ld	(hl), a
cr_bn:
	ld	a, (cr_bi)
	inc	a
	ld	(cr_bi), a
	ld	a, (cr_bit)
	or	a
	rra
	ld	(cr_bit), a
	jp	nz, cr_bits
	ld	a, (cr_ah)
	ld	h, a
	ld	a, (cr_l)
	ld	l, a
	inc	l
	ld	a, (cr_n)
	dec	a
	ld	(cr_n), a
	jp	nz, cr_row
cr_nxt:
	ld	a, (cr_ah)
	inc	a
	ld	(cr_ah), a
	ld	a, (cr_col)
	inc	a
	ld	(cr_col), a
	cp	32
	jp	nz, cr_cols
	ret
crumble_end:

; Заменить цвет 3 на 0 для o=65535..1 (точку (0,0) не трогать).
replace_tmp:
	ld	d, 0
	ld	e, 0
rt_lp:
	inc	d
	jp	nz, rt_go
	inc	e
	ld	a, e
	or	d
	ret	z
rt_go:
	call	rt_one
	jp	rt_lp
rt_one:
	push	de
	call	getpixel
	cp	3
	jp	nz, rt_no
	pop	de
	push	de
	xor	a
	call	putpixel
rt_no:
	pop	de
	ret
replace_tmp_end:

cr_ah:	db	0
cr_col:	db	0
cr_vm:	db	0
cr_pa:	db	0
cr_pc:	db	0
cr_pe:	db	0
cr_occ:	db	0
cr_em:	db	0
cr_l:	db	0
cr_bit:	db	0
cr_bi:	db	0
cr_n:	db	0
cr_fl:	ds	8
