; Особое оружие — sonic() (12), explosiveDirt() (17), cri() (6..10) эталона web/tankwars.js (PROFILE_V06C).
;   special: вход — ячейки взрыва ex_x, ex_y, ex_hit, ex_shooter, ex_weapon (explode.asm), as_crumble (процент осыпания).
; Вызывается из explode для оружия, которое не обычный взрыв и не шар грязи. Порядок случайных чисел — как в эталоне.

special:
	ld	a, (ex_weapon)
	cp	12
	jp	z, sx_sonic
	cp	17
	jp	z, sx_xdirt
	cp	6
	ret	c
	cp	11
	jp	c, sx_cri
	ret

; --- Sonic Blaster: 300 случайных чисел (в оригинале — звук), точка и четыре соседа, осыпание ---
sx_sonic:
	ld	hl, 300
sx_sn1:
	ld	(sx_n), hl
	ld	de, 64
	call	random
	ld	hl, (sx_n)
	dec	hl
	ld	a, h
	or	l
	jp	nz, sx_sn1
	call	sx_xy			; sx_cx, sx_cy = trunc(x), trunc(y)
	; четыре точки вокруг (x + X0, y + Y0) — только внутри поля
	ld	hl, sx_dir4
	ld	a, 4
sx_sn2:
	ld	(sx_i), a
	ld	e, (hl)
	inc	hl
	ld	a, e
	rla
	sbc	a, a
	ld	d, a
	push	hl
	ld	hl, (sx_cx)
	add	hl, de
	ld	de, LZ_X0
	add	hl, de
	ld	(lz_gx), hl
	pop	hl
	ld	e, (hl)
	inc	hl
	ld	a, e
	rla
	sbc	a, a
	ld	d, a
	push	hl
	ld	hl, (sx_cy)
	add	hl, de
	ld	de, LZ_Y0
	add	hl, de
	ld	(lz_gy), hl
	call	lz_infield
	jp	nc, sx_sn3
	xor	a
	call	lz_put
sx_sn3:
	pop	hl
	ld	a, (sx_i)
	dec	a
	jp	nz, sx_sn2
	; сама точка (x, y) — на экране
	ld	hl, (sx_cx)
	ld	(lz_gx), hl
	ld	hl, (sx_cy)
	ld	(lz_gy), hl
	xor	a
	call	lz_put
	jp	crumble
sx_dir4:
	db	0, 1,  0, -1,  1, 0,  -1, 0

; --- Xplosive Dirt: строки комьев над точкой попадания, потом осыпание с вероятностью 2·процент ---
sx_xdirt:
	ld	de, 100
	call	random
	ld	de, 300
	add	hl, de
	ld	(sx_n), hl
	ld	de, 8
	call	random
	ld	a, l
	add	a, 3
	ld	(sx_rows), a
	; центр: trunc(x − X0) + X0, trunc(y − Y0) + Y0
	ld	hl, ex_x
	ld	de, -LZ_X0
	call	ex_ctr
	ld	(sx_cx), hl
	ld	hl, ex_y
	ld	de, -LZ_Y0
	call	ex_ctr
	ld	(sx_cy), hl
	ld	a, 1
sx_xr:
	ld	(sx_row), a
	ld	hl, (sx_n)
sx_xc:
	ld	(sx_c), hl
	; span = Random(row · 10)
	ld	a, (sx_row)
	ld	l, a
	ld	h, 0
	add	hl, hl
	ld	d, h
	ld	e, l
	add	hl, hl
	add	hl, hl
	add	hl, de
	ex	de, hl
	call	random
	ld	(sx_span), hl
	; r = Random(span + 1); сдвиг = trunc(r − span/2) к нулю
	ex	de, hl
	inc	de
	call	random
	add	hl, hl			; 2r
	ex	de, hl
	ld	hl, (sx_span)
	ex	de, hl
	call	lb_sub			; 2r − span
	ld	a, h
	or	a
	push	af
	call	m, lb_neg
	ld	a, h			; / 2
	or	a
	rra
	ld	h, a
	ld	a, l
	rra
	ld	l, a
	pop	af
	call	m, lb_neg
	ex	de, hl
	ld	hl, (sx_cx)
	add	hl, de
	ld	(lz_gx), hl
	; Y = cy − span + 2
	ld	hl, (sx_span)
	ex	de, hl
	ld	hl, (sx_cy)
	call	lb_sub
	inc	hl
	inc	hl
	ld	(lz_gy), hl
	call	lz_infield
	jp	nc, sx_xn
	ld	a, 1
	call	lz_put
sx_xn:
	ld	hl, (sx_c)
	dec	hl
	ld	a, h
	or	l
	jp	nz, sx_xc
	ld	a, (sx_rows)
	ld	b, a
	ld	a, (sx_row)
	cp	b
	jp	z, sx_xe
	inc	a
	jp	sx_xr
sx_xe:
	ld	a, (as_crumble)
	add	a, a
	call	rnd_lt_pct
	ret	nc
	jp	crumble

; --- CRI: «черви», выедающие землю ---
sx_cri:
	ld	a, (ex_hit)
	cp	4
	jp	c, sx_cg
	; попадание в танк: урон Random(оружие · 6) + 1 — со щита, остаток в здоровье, стрелку очки
	ld	a, (ex_weapon)
	ld	e, a
	add	a, a
	add	a, e
	add	a, a
	ld	e, a
	ld	d, 0
	call	random
	inc	hl
	ex	de, hl			; DE = урон
	ld	a, (ex_hit)
	sub	3
	ld	(sx_i), a
	push	de
	call	dt_ptr			; портит DE
	pop	de
	ld	(sx_p), hl
	ld	bc, PL_SHIELD
	add	hl, bc
	ld	a, (hl)
	sub	e
	ld	(hl), a
	ld	e, a
	inc	hl
	ld	a, (hl)
	sbc	a, d
	ld	(hl), a
	ld	d, a			; DE = младшее слово щита после вычитания
	inc	hl
	ld	a, (hl)
	sbc	a, 0
	ld	(hl), a
	inc	hl
	ld	a, (hl)
	sbc	a, 0
	ld	(hl), a
	ret	p			; щит выдержал
	xor	a			; щит = 0
	ld	(hl), a
	dec	hl
	ld	(hl), a
	dec	hl
	ld	(hl), a
	dec	hl
	ld	(hl), a
	ld	hl, (sx_p)		; men += младшее слово (отрицательного) щита, 16 бит
	ld	bc, PL_MEN
	add	hl, bc
	ld	a, (hl)
	add	a, e
	ld	(hl), a
	inc	hl
	ld	a, (hl)
	adc	a, d
	ld	(hl), a
	; стрелку (если это не сама жертва и стрелок есть) очки += |щит| · 10
	ld	a, (ex_shooter)
	or	a
	ret	z
	ld	b, a
	ld	a, (n_players)
	cp	b
	ret	c
	ld	a, (sx_i)
	cp	b
	ret	z
	ex	de, hl
	call	lb_neg			; |щит|
	ld	d, h
	ld	e, l
	add	hl, hl
	add	hl, hl
	add	hl, de
	add	hl, hl			; · 10
	ex	de, hl
	ld	a, (ex_shooter)
	push	de
	call	dt_ptr
	ld	bc, PL_SCORE
	add	hl, bc
	pop	de
	ld	a, (hl)
	add	a, e
	ld	(hl), a
	inc	hl
	ld	a, (hl)
	adc	a, d
	ld	(hl), a
	inc	hl
	ld	a, (hl)
	adc	a, 0
	ld	(hl), a
	inc	hl
	ld	a, (hl)
	adc	a, 0
	ld	(hl), a
	ret
sx_cg:
	cp	1
	ret	nz			; не земля
	ld	a, (ex_weapon)
	sub	6
	ld	e, a
	ld	d, 0
	ld	hl, sx_crad
	add	hl, de
	ld	a, (hl)
	ld	(sx_rad), a
	ld	a, (ex_weapon)		; чётные (6, 8, 10) ходят и по диагонали
	and	1
	ld	(sx_odd), a
	call	sx_xy
	; опуститься до точки, у которой сосед по стороне — земля
sx_cd:
	ld	hl, sx_dir4
	ld	b, 4
sx_cd1:
	ld	a, (sx_cx)
	add	a, (hl)
	ld	d, a
	inc	hl
	ld	a, (sx_cy)
	add	a, (hl)
	ld	e, a
	inc	hl
	push	hl
	push	bc
	call	getpixel
	pop	bc
	pop	hl
	cp	1
	jp	z, sx_c0
	dec	b
	jp	nz, sx_cd1
	ld	hl, sx_cy
	inc	(hl)
	jp	sx_cd
sx_c0:
	; точки 1..radius — в начало, остальные до 21 — пустые (x = 0)
	ld	hl, sx_px
	ld	b, 22
	xor	a
sx_c1:
	ld	(hl), a
	inc	hl
	dec	b
	jp	nz, sx_c1
	ld	a, (sx_rad)
	ld	b, a
	ld	hl, sx_px + 1
	ld	de, sx_py + 1
sx_c2:
	ld	a, (sx_cx)
	ld	(hl), a
	ld	a, (sx_cy)
	ld	(de), a
	inc	hl
	inc	de
	dec	b
	jp	nz, sx_c2
sx_sweep:
	ld	a, 1
sx_w1:
	ld	(sx_i), a
	call	sx_pt			; D = x, E = y точки i
	ld	a, d
	ld	(sx_x), a
	ld	a, e
	ld	(sx_y), a
	; направления с землёй
	xor	a
	ld	(sx_nd), a
	ld	a, 1
sx_w2:
	ld	(sx_d), a
	ld	b, a
	ld	a, (sx_odd)
	or	a
	jp	z, sx_w3		; чётное оружие — все восемь
	ld	a, b
	and	1
	jp	z, sx_w4		; нечётное оружие — без диагоналей (чётных направлений)
sx_w3:
	call	sx_step			; D, E = точка в направлении sx_d
	call	getpixel
	cp	1
	jp	nz, sx_w4
	ld	a, (sx_nd)
	ld	e, a
	ld	d, 0
	inc	a
	ld	(sx_nd), a
	ld	hl, sx_dirs
	add	hl, de
	ld	a, (sx_d)
	ld	(hl), a
sx_w4:
	ld	a, (sx_d)
	inc	a
	cp	9
	jp	nz, sx_w2
	ld	a, (sx_nd)
	or	a
	jp	nz, sx_w5
	ld	de, 0			; идти некуда — точка гаснет
	jp	sx_w6
sx_w5:
	ld	e, a
	ld	d, 0
	call	random
	ld	de, sx_dirs
	add	hl, de
	ld	a, (hl)
	ld	(sx_d), a
	call	sx_step
	push	de
	xor	a
	call	putpixel
	pop	de
sx_w6:
	call	sx_set
	ld	a, (sx_rad)
	ld	b, a
	ld	a, (sx_i)
	cp	b
	jp	z, sx_dead
	inc	a
	jp	sx_w1
	; погасшие точки встают на место первой живой; все погасли — конец
sx_dead:
	xor	a
	ld	(sx_nd), a
	ld	a, 1
sx_e1:
	ld	(sx_i), a
	call	sx_pt
	ld	a, d
	or	a
	jp	nz, sx_e4
	ld	hl, sx_nd
	inc	(hl)
	ld	c, 0			; j
sx_e2:
	inc	c
	ld	a, c
	cp	21
	jp	z, sx_e4		; не нашлось — остаётся погасшей
	ld	a, (sx_i)
	cp	c
	jp	z, sx_e2
	ld	b, 0
	ld	hl, sx_px
	add	hl, bc
	ld	a, (hl)
	or	a
	jp	z, sx_e2
	ld	d, a
	ld	hl, sx_py
	add	hl, bc
	ld	e, (hl)
	call	sx_set
sx_e4:
	ld	a, (sx_rad)
	ld	b, a
	ld	a, (sx_i)
	cp	b
	jp	z, sx_e5
	inc	a
	jp	sx_e1
sx_e5:
	ld	a, (sx_rad)
	ld	b, a
	ld	a, (sx_nd)
	cp	b
	ret	z
	jp	sx_sweep

; D, E = точка sx_i
sx_pt:
	ld	a, (sx_i)
	ld	c, a
	ld	b, 0
	ld	hl, sx_px
	add	hl, bc
	ld	d, (hl)
	ld	hl, sx_py
	add	hl, bc
	ld	e, (hl)
	ret
; точка sx_i = D, E
sx_set:
	ld	a, (sx_i)
	ld	c, a
	ld	b, 0
	ld	hl, sx_px
	add	hl, bc
	ld	(hl), d
	ld	hl, sx_py
	add	hl, bc
	ld	(hl), e
	ret
; D, E = (sx_x, sx_y) + шаг направления sx_d (1..8)
sx_step:
	ld	a, (sx_d)
	add	a, a
	ld	c, a
	ld	b, 0
	ld	hl, sx_dir8 - 2
	add	hl, bc
	ld	a, (sx_x)
	add	a, (hl)
	ld	d, a
	inc	hl
	ld	a, (sx_y)
	add	a, (hl)
	ld	e, a
	ret
; sx_cx, sx_cy = trunc(ex_x), trunc(ex_y)
sx_xy:
	ld	hl, ex_x
	call	lz_tr
	ld	(sx_cx), hl
	ld	hl, ex_y
	call	lz_tr
	ld	(sx_cy), hl
	ret
sx_dir8:
	db	0, -1,  1, -1,  1, 0,  1, 1,  0, 1,  -1, 1,  -1, 0,  -1, -1
sx_crad:
	db	4, 8, 8, 20, 20
special_end:

sx_n:		dw	0
sx_c:		dw	0
sx_cx:		dw	0
sx_cy:		dw	0
sx_span:	dw	0
sx_p:		dw	0
sx_rows:	db	0
sx_row:		db	0
sx_i:		db	0
sx_d:		db	0
sx_nd:		db	0
sx_x:		db	0
sx_y:		db	0
sx_rad:		db	0
sx_odd:		db	0
sx_dirs:	ds	8
sx_px:		ds	22
sx_py:		ds	22
