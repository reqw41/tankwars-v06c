; Точка в трёх плоскостях A000/C000/E000.
; Адрес: plane + (x>>3)*256 + (255-y). Бит 7 — левая точка. Цвет 0..7.
; putpixel: D=x, E=y, A=цвет. getpixel: D=x, E=y → A.
; putpixel16: BC=x, DE=y знаковые; вне 0..255 — не писать.

putpixel:
	ld	b, a
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
	jp	z, pp_mask
	ld	e, a
pp_sh:
	ld	a, c
	rrca
	ld	c, a
	dec	e
	jp	nz, pp_sh
pp_mask:
	ld	a, b
	and	7
	cp	3
	jp	nz, pp_other
	; цвет 3: плоскости A и C — 1, E — 0 (замер putpixel(40,50,3))
	ld	a, (hl)
	or	c
	ld	(hl), a
	ld	a, h
	add	a, 0x20
	ld	h, a
	ld	a, (hl)
	or	c
	ld	(hl), a
	ld	a, h
	add	a, 0x20
	ld	h, a
	ld	a, c
	cpl
	and	(hl)
	ld	(hl), a
	ret
pp_other:
	ld	a, c
	cpl
	ld	e, a
	ld	d, b
	call	pp_plane
	ld	a, h
	add	a, 0x20
	ld	h, a
	call	pp_plane
	ld	a, h
	add	a, 0x20
	ld	h, a
pp_plane:
	ld	a, d
	rrca
	ld	d, a
	jp	nc, pp_clr
	ld	a, (hl)
	or	c
	ld	(hl), a
	ret
pp_clr:
	ld	a, e
	and	(hl)
	ld	(hl), a
	ret
putpixel_end:

getpixel:
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
	jp	z, gp_mask
	ld	e, a
gp_sh:
	ld	a, c
	rrca
	ld	c, a
	dec	e
	jp	nz, gp_sh
gp_mask:
	xor	a
	ld	b, a
	ld	a, (hl)
	and	c
	jp	z, gp1
	ld	b, 1
gp1:
	ld	a, h
	add	a, 0x20
	ld	h, a
	ld	a, (hl)
	and	c
	jp	z, gp2
	ld	a, b
	or	2
	ld	b, a
gp2:
	ld	a, h
	add	a, 0x20
	ld	h, a
	ld	a, (hl)
	and	c
	jp	z, gp3
	ld	a, b
	or	4
	ld	b, a
gp3:
	ld	a, b
	ret
getpixel_end:

putpixel16:
	ld	(pix_c), a
	ld	a, b
	or	a
	ret	nz
	ld	a, d
	or	a
	ret	nz
	ld	d, c
	ld	a, (pix_c)
	jp	putpixel

; HL = адрес плоскости A, C = маска, A = цвет. Портит A,B,D,E; HL возвращается на A.
plot_hlc:
	ld	b, a
	ld	a, c
	cpl
	ld	e, a
	ld	d, b
	call	pp_plane
	ld	a, h
	add	a, 0x20
	ld	h, a
	call	pp_plane
	ld	a, h
	add	a, 0x20
	ld	h, a
	call	pp_plane
	ld	a, h
	sub	0x40
	ld	h, a
	ret

pixel_end:

pix_c:	db	0
	ds	(8 - ($ & 7)) & 7
pix_mask:
	db	0x80, 0x40, 0x20, 0x10, 0x08, 0x04, 0x02, 0x01
