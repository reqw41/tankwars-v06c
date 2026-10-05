; Лазер — laserFix() эталона web/tankwars.js (PROFILE_V06C): луч цвета 3 идёт шагами по одной точке, роет землю,
; жжёт танки; в конце цвет 3 снимается со всего экрана.
;   laser: вход A = место стрелка; rs_rebound (стены отражают). Энергия — запас оружия 5.
; Порядок случайных чисел — как в эталоне: Random < 0.2 (потеря здоровья стрелка); на точке земли 15 пар Random(20);
; на танке без щита 15 искр — пары Random(40), пока точка не годится.

LZ_X0		equ	3
LZ_X1		equ	252
LZ_Y0		equ	27
LZ_Y1		equ	252
LZ_BEAM		equ	3

laser:
	ld	(lz_place), a
	call	cr_mark_all
	ld	a, (lz_place)
	call	dt_ptr
	ld	(lz_p), hl
	ld	de, PL_POWER
	add	hl, de
	ld	e, (hl)
	inc	hl
	ld	d, (hl)
	ld	a, d
	or	e
	ret	z			; мощность 0 — выстрела нет
	ex	de, hl
	ld	(lz_pw), hl
	; мощность не больше энергии; энергия −= мощность
	ld	hl, (lz_p)
	ld	de, PL_AMMO + 10
	add	hl, de
	ld	e, (hl)
	inc	hl
	ld	d, (hl)
	ld	hl, (lz_pw)
	call	fl_scmp
	cp	1
	jp	nz, lz_e1
	ex	de, hl
	ld	(lz_pw), hl		; мощность = энергия
	ex	de, hl
	ld	hl, (lz_p)
	ld	bc, PL_POWER
	add	hl, bc
	ld	(hl), e
	inc	hl
	ld	(hl), d
lz_e1:
	ld	hl, (lz_pw)
	ex	de, hl
	ld	hl, (lz_p)
	ld	bc, PL_AMMO + 10
	add	hl, bc
	ld	a, (hl)
	sub	e
	ld	(hl), a
	inc	hl
	ld	a, (hl)
	sbc	a, d
	ld	(hl), a
	; ствол цветом луча, корпус поверх
	ld	a, (lz_place)
	call	dt_tb
	call	tb_ends
	ld	a, LZ_BEAM
	ld	(ln_c), a
	call	line
	ld	hl, (lz_p)
	ld	d, (hl)
	inc	hl
	ld	e, (hl)
	ld	a, (lz_place)
	add	a, 3
	call	draw_tank
	; счётчик = 10 · мощность
	ld	hl, (lz_pw)
	add	hl, hl
	ld	d, h
	ld	e, l
	add	hl, hl
	add	hl, hl
	add	hl, de
	ld	(lz_cnt), hl
	; с вероятностью 0.2 стрелок теряет единицу здоровья
	call	rnd_hi
	ld	de, -13107
	add	hl, de
	jp	c, lz_m
	ld	hl, (lz_p)
	ld	de, PL_MEN
	add	hl, de
	call	tn_dec16
lz_m:
	; начало луча: X = x + 7·cos·facing, Y = y − 7·sin
	ld	hl, (lz_p)
	ld	de, PL_ANGLE
	add	hl, de
	ld	a, (hl)
	ld	(lz_ang), a
	inc	hl
	ld	a, (hl)
	ld	(lz_fc), a
	ld	a, (lz_ang)
	ld	l, a
	ld	h, 0
	call	fx_sincos
	ld	hl, lz_x
	ld	de, fx_cos
	call	lz_mul7
	ld	a, (lz_fc)
	or	a
	jp	p, lz_s1
	ld	hl, lz_x
	ld	b, 4
	call	fx_negm
lz_s1:
	ld	hl, (lz_p)
	ld	e, (hl)
	ld	d, 0
	ld	hl, (lz_x + 2)
	add	hl, de
	ld	(lz_x + 2), hl
	ld	hl, lz_y
	ld	de, fx_sin
	call	lz_mul7
	ld	hl, lz_y
	ld	b, 4
	call	fx_negm
	ld	hl, (lz_p)
	inc	hl
	ld	e, (hl)
	ld	d, 0
	ld	hl, (lz_y + 2)
	add	hl, de
	ld	(lz_y + 2), hl
	; шаг луча: (cos, −sin) угла с учётом направления
	ld	a, (lz_ang)
	ld	l, a
	ld	h, 0
	ld	a, (lz_fc)
	or	a
	jp	p, lz_s2
	ld	a, 180
	sub	l
	ld	l, a
lz_s2:
	call	fx_sincos
	ld	hl, lz_dx
	ld	de, fx_cos
	ld	b, 4
	call	fx_copy
	ld	hl, lz_dy
	ld	de, fx_sin
	ld	b, 4
	call	fx_copy
	ld	hl, lz_dy
	ld	b, 4
	call	fx_negm

lz_loop:
	xor	a
	ld	(lz_done), a
	ld	hl, lz_x
	ld	de, lz_dx
	ld	b, 4
	call	fx_addm
	ld	hl, lz_y
	ld	de, lz_dy
	ld	b, 4
	call	fx_addm
	call	lz_cnt10
	ld	hl, lz_x
	call	lz_tr
	ld	(lz_gx), hl
	ld	hl, lz_y
	call	lz_tr
	ld	(lz_gy), hl
	call	lz_get
	ld	(lz_c), a
	cp	1
	jp	nz, lz_tank
	; --- земля: 15 случайных точек позади луча стираются ---
	ld	a, 15
lz_dig:
	ld	(lz_k), a
	ld	de, 20
	call	random
	ld	a, l
	ld	de, lz_dx
	ld	hl, lz_x
	call	lz_back
	ld	(lz_gx), hl
	ld	de, 20
	call	random
	ld	a, l
	ld	de, lz_dy
	ld	hl, lz_y
	call	lz_back
	ld	(lz_gy), hl
	call	lz_get
	cp	3
	jp	nc, lz_dn		; танк или луч — не трогать
	call	lz_infield
	jp	nc, lz_dn
	xor	a
	call	lz_put
lz_dn:
	ld	a, (lz_k)
	dec	a
	jp	nz, lz_dig
	jp	lz_edge
	; --- танк: живой игрок цвета c ---
lz_tank:
	cp	4
	jp	c, lz_edge
	sub	3			; место жертвы
	ld	b, a
	ld	a, (n_players)
	cp	b
	jp	c, lz_edge		; такого игрока нет
	ld	a, b
	call	dt_ptr
	ld	(lz_v), hl
	ld	de, PL_MEN
	add	hl, de
	ld	e, (hl)
	inc	hl
	ld	d, (hl)
	call	rf_pos
	jp	z, lz_edge		; men <= 0
	call	lz_cnt10
	; щит > 0 — без искр
	ld	hl, (lz_v)
	ld	de, PL_SHIELD
	add	hl, de
	call	lz_pos32
	jp	nz, lz_dmg
	xor	a
lz_sp:
	ld	(lz_k), a
lz_sp1:
	ld	hl, lz_x
	call	lz_spark
	ld	(lz_gx), hl
	ld	hl, lz_y
	call	lz_spark
	ld	(lz_gy), hl
	call	lz_get
	ld	b, a
	ld	a, (lz_c)
	cp	b
	jp	z, lz_sp2		; свой цвет жертвы
	ld	a, b
	cp	3
	jp	nc, lz_sp1		; чужой танк или луч — другая точка
lz_sp2:
	ld	a, (lz_k)		; запомнить точку
	add	a, a
	add	a, a
	ld	e, a
	ld	d, 0
	ld	hl, lz_pts
	add	hl, de
	ld	a, (lz_gx)
	ld	(hl), a
	inc	hl
	ld	a, (lz_gx + 1)
	ld	(hl), a
	inc	hl
	ld	a, (lz_gy)
	ld	(hl), a
	inc	hl
	ld	a, (lz_gy + 1)
	ld	(hl), a
	call	lz_infield
	jp	nc, lz_sp3
	ld	a, (lz_c)
	call	lz_put
lz_sp3:
	ld	a, (lz_k)
	inc	a
	cp	15
	jp	nz, lz_sp
	; искры гаснут
	xor	a
lz_so:
	ld	(lz_k), a
	add	a, a
	add	a, a
	ld	e, a
	ld	d, 0
	ld	hl, lz_pts
	add	hl, de
	ld	e, (hl)
	inc	hl
	ld	d, (hl)
	inc	hl
	ld	a, (hl)
	inc	hl
	ld	h, (hl)
	ld	l, a
	ld	(lz_gy), hl
	ex	de, hl
	ld	(lz_gx), hl
	call	lz_infield
	jp	nc, lz_so1
	xor	a
	call	lz_put
lz_so1:
	ld	a, (lz_k)
	inc	a
	cp	15
	jp	nz, lz_so
lz_dmg:
	; щит −= 3; ушёл в минус — остаток в здоровье, щит = 0
	ld	hl, (lz_v)
	ld	de, PL_SHIELD
	add	hl, de
	ld	a, (hl)
	sub	3
	ld	(hl), a
	ld	c, a			; младший байт разности
	inc	hl
	ld	a, (hl)
	sbc	a, 0
	ld	(hl), a
	inc	hl
	ld	a, (hl)
	sbc	a, 0
	ld	(hl), a
	inc	hl
	ld	a, (hl)
	sbc	a, 0
	ld	(hl), a
	jp	p, lz_bk
	xor	a			; щит = 0
	ld	(hl), a
	dec	hl
	ld	(hl), a
	dec	hl
	ld	(hl), a
	dec	hl
	ld	(hl), a
	ld	hl, (lz_v)		; men += (отрицательный остаток): расширить знак C
	ld	de, PL_MEN
	add	hl, de
	ld	a, (hl)
	add	a, c
	ld	(hl), a
	inc	hl
	ld	a, (hl)
	adc	a, 0xFF
	ld	(hl), a
lz_bk:
	; луч отходит на шаг назад
	ld	hl, lz_x
	ld	de, lz_dx
	ld	b, 4
	call	fx_subm
	ld	hl, lz_y
	ld	de, lz_dy
	ld	b, 4
	call	fx_subm
lz_edge:
	; счётчик кончился
	ld	hl, (lz_cnt)
	ld	a, h
	or	a
	jp	m, lz_stop
	or	l
	jp	nz, lz_wall
lz_stop:
	ld	a, 1
	ld	(lz_done), a
lz_wall:
	; края поля: отражение или конец
	ld	a, (lz_dx + 3)
	or	a
	jp	p, lz_w2
	ld	hl, lz_x		; dx < 0: X <= X0
	ld	de, LZ_X0
	call	fl_gt
	jp	c, lz_w3
	ld	hl, lz_dx
	jp	lz_hit
lz_w2:
	ld	hl, lz_dx
	call	lz_zero
	jp	z, lz_w3
	ld	hl, lz_x		; dx > 0: X >= X1
	ld	de, LZ_X1
	call	fl_lt
	jp	c, lz_w3
	ld	hl, lz_dx
lz_hit:
	call	lz_bounce
lz_w3:
	ld	a, (lz_dy + 3)
	or	a
	jp	p, lz_w4
	ld	hl, lz_y		; dy < 0: Y <= Y0
	ld	de, LZ_Y0
	call	fl_gt
	jp	c, lz_w5
	ld	hl, lz_dy
	jp	lz_hit2
lz_w4:
	ld	hl, lz_dy
	call	lz_zero
	jp	z, lz_w5
	ld	hl, lz_y		; dy > 0: Y >= Y1
	ld	de, LZ_Y1
	call	fl_lt
	jp	c, lz_w5
	ld	hl, lz_dy
lz_hit2:
	call	lz_bounce
lz_w5:
	ld	a, (lz_done)
	or	a
	jp	nz, lz_end
	ld	hl, lz_x
	call	lz_tr
	ld	(lz_gx), hl
	ld	hl, lz_y
	call	lz_tr
	ld	(lz_gy), hl
	ld	a, LZ_BEAM
	call	lz_put
	jp	lz_loop
lz_end:
	ld	a, LZ_BEAM
	jp	replace_color

; край: при отражающих стенах шаг (HL) меняет знак, иначе луч кончается
lz_bounce:
	ld	a, (rs_rebound)
	or	a
	jp	z, lz_b0
	ld	b, 4
	jp	fx_negm
lz_b0:
	ld	a, 1
	ld	(lz_done), a
	ret
; счётчик −= 10
lz_cnt10:
	ld	hl, (lz_cnt)
	ld	de, -10
	add	hl, de
	ld	(lz_cnt), hl
	ret
; (HL) = (DE) · 7, Q16.16
lz_mul7:
	ld	(lz_ptr), hl
	ex	de, hl
	ld	(lz_ptr2), hl
	ld	hl, (lz_ptr)
	ld	b, 4
	call	fx_zero
	ld	a, 7
lz_m7:
	push	af
	ld	hl, (lz_ptr2)
	ex	de, hl
	ld	hl, (lz_ptr)
	ld	b, 4
	call	fx_addm
	pop	af
	dec	a
	jp	nz, lz_m7
	ret
; HL = trunc((HL) − (DE)·A), A = 0..39: точка позади луча
lz_back:
	ld	(lz_ptr), hl
	ex	de, hl
	ld	(lz_ptr2), hl
	push	af
	ld	hl, lz_t
	ex	de, hl
	ld	hl, (lz_ptr)
	ex	de, hl
	ld	b, 4
	call	fx_copy
	pop	af
lz_bk1:
	or	a
	jp	z, lz_bk2
	push	af
	ld	hl, (lz_ptr2)
	ex	de, hl
	ld	hl, lz_t
	ld	b, 4
	call	fx_subm
	pop	af
	dec	a
	jp	lz_bk1
lz_bk2:
	ld	hl, lz_t
	jp	lz_tr
; HL = trunc((HL) − Random(40) + 20): искра у танка
lz_spark:
	ld	de, lz_t
	ex	de, hl
	ld	b, 4
	call	fx_copy
	ld	de, 40
	call	random
	ld	a, 20
	sub	l
	ld	e, a
	sbc	a, a
	ld	d, a			; DE = 20 − Random(40)
	ld	hl, (lz_t + 2)
	add	hl, de
	ld	(lz_t + 2), hl
	ld	hl, lz_t
; HL = trunc Q16.16 по адресу HL, усечение к нулю
lz_tr:
	ld	a, (hl)
	inc	hl
	or	(hl)
	ld	c, a
	inc	hl
	ld	a, (hl)
	inc	hl
	ld	h, (hl)
	ld	l, a
	ld	a, h
	or	a
	ret	p
	ld	a, c
	or	a
	ret	z
	inc	hl
	ret
; A = цвет точки (lz_gx, lz_gy); вне экрана — 0
lz_get:
	ld	a, (lz_gx + 1)
	ld	b, a
	ld	a, (lz_gy + 1)
	or	b
	ld	a, 0
	ret	nz
	ld	a, (lz_gx)
	ld	d, a
	ld	a, (lz_gy)
	ld	e, a
	jp	getpixel
; точка (lz_gx, lz_gy) цветом A; вне экрана — ничего
lz_put:
	ld	c, a
	ld	a, (lz_gx + 1)
	ld	b, a
	ld	a, (lz_gy + 1)
	or	b
	ret	nz
	ld	a, (lz_gx)
	ld	d, a
	ld	a, (lz_gy)
	ld	e, a
	ld	a, c
	jp	putpixel
; CF = 1, если (lz_gx, lz_gy) в поле
lz_infield:
	ld	a, (lz_gx + 1)
	ld	b, a
	ld	a, (lz_gy + 1)
	or	b
	ret	nz			; CF = 0 после or
	ld	a, (lz_gx)
	cp	LZ_X0
	ccf
	ret	nc
	cp	LZ_X1 + 1
	ret	nc
	ld	a, (lz_gy)
	cp	LZ_Y0
	ccf
	ret	nc
	cp	LZ_Y1 + 1
	ret
; ZF = 1, если Q16.16 по адресу HL равно нулю
lz_zero:
	ld	a, (hl)
	inc	hl
	or	(hl)
	inc	hl
	or	(hl)
	inc	hl
	or	(hl)
	ret
; ZF = 0, если 32-битное со знаком по адресу HL больше нуля
lz_pos32:
	ld	a, (hl)
	inc	hl
	or	(hl)
	inc	hl
	or	(hl)
	ld	c, a
	inc	hl
	ld	a, (hl)
	or	a
	jp	m, lz_p0
	or	c
	ret
lz_p0:
	xor	a
	ret
laser_end:

lz_place:	db	0
lz_ang:		db	0
lz_fc:		db	0
lz_c:		db	0
lz_k:		db	0
lz_done:	db	0
lz_p:		dw	0
lz_v:		dw	0
lz_pw:		dw	0
lz_cnt:		dw	0
lz_gx:		dw	0
lz_gy:		dw	0
lz_ptr:		dw	0
lz_ptr2:	dw	0
lz_x:		ds	4
lz_y:		ds	4
lz_dx:		ds	4
lz_dy:		ds	4
lz_t:		ds	4
lz_pts:		ds	60
