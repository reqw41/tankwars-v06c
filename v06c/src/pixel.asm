; Точка в трёх плоскостях A000/C000/E000.
; Адрес байта: plane + (x>>3)*256 + (255-y). Бит 7 — левая точка столбца из 8.
; Развёртка Вектора идёт от младшего байта FFh (верх) к 00h (низ) — vector06js src/tv.js: fb_row = ScrollStart, затем fb_row -= 1.
; Цвет 0..7: bit0→A000, bit1→C000, bit2→E000.
; putpixel: D=x, E=y, A=цвет. getpixel: D=x, E=y → A=цвет. Вне 0..255 — не писать / читать 0.

putpixel:
	ld	(pix_c), a
	call	pix_addr
	ret	c			; вне экрана
	ld	a, (pix_c)
	and	7
	ld	b, a
	call	pix_apply		; A000, bit0
	ld	a, h
	add	a, 0x20
	ld	h, a
	ld	a, b
	rrca
	ld	b, a
	call	pix_apply		; C000, bit1
	ld	a, h
	add	a, 0x20
	ld	h, a
	ld	a, b
	rrca
	ld	b, a
	call	pix_apply		; E000, bit2
	ret
putpixel_end:

getpixel:
	call	pix_addr
	jp	nc, gp_ok
	xor	a
	ret
gp_ok:
	xor	a
	ld	(pix_c), a
	ld	a, (hl)
	and	c
	jp	z, gp1
	ld	a, (pix_c)
	or	1
	ld	(pix_c), a
gp1:
	ld	a, h
	add	a, 0x20
	ld	h, a
	ld	a, (hl)
	and	c
	jp	z, gp2
	ld	a, (pix_c)
	or	2
	ld	(pix_c), a
gp2:
	ld	a, h
	add	a, 0x20
	ld	h, a
	ld	a, (hl)
	and	c
	jp	z, gp3
	ld	a, (pix_c)
	or	4
	ld	(pix_c), a
gp3:
	ld	a, (pix_c)
	ret
getpixel_end:

; putpixel16: BC=x, DE=y, A=цвет (знаковые 16 бит; вне 0..255 — нет записи)
putpixel16:
	ld	(pix_c), a
	ld	a, b
	or	a
	ret	nz
	ld	a, d
	or	a
	ret	nz
	ld	d, c
	; E = y
	ld	a, (pix_c)
	jp	putpixel

; D=x, E=y → HL=A000+(x>>3)*256+y, C=маска; CF=1 если x/y не байт экрана
; Здесь D,E уже 0..255.
pix_addr:
	or	a			; CF=0
	ld	a, d
	rrca
	rrca
	rrca
	and	0x1F
	or	0xA0
	ld	h, a
	ld	a, e
	cpl				; младший байт адреса = 255-y: FFh — верхняя строка экрана Вектора
	ld	l, a
	ld	a, d
	and	7
	ld	b, a
	ld	c, 0x80
	ld	a, b
	or	a
	ret	z
pa_sh:
	ld	a, c
	or	a
	rra
	ld	c, a
	dec	b
	jp	nz, pa_sh
	or	a			; CF=0
	ret

; HL адрес плоскости, C маска, B.bit0 — значение
pix_apply:
	ld	a, b
	and	1
	jp	z, pix_clr
	ld	a, (hl)
	or	c
	ld	(hl), a
	ret
pix_clr:
	ld	a, c
	cpl
	and	(hl)
	ld	(hl), a
	ret
pixel_end:

pix_c:	db	0
