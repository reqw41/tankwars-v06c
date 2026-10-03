; Полёт снаряда — flightDrawFix() эталона web/tankwars.js (PROFILE_V06C, без наведения).
; Вход (ячейки): fl_angle (байт 0..90), fl_facing (1 / 0xFF), fl_power (слово), fl_tx, fl_ty (байты, танк),
;   fl_wind (слово со знаком), fl_rebound (0/1), fl_weapon (байт), fl_men (слово), fl_players (байт), fl_ball (0/1 — мяч виден).
; Выход: fl_stop (0 — предел шагов, 1 — земля, 2 — танк, 3 — вылет), fl_hit (цвет попадания), fl_x, fl_y (Q16.16).
; Экран меняется так же, как в эталоне: мяч-крестик цвета 3 рисуется и стирается.
;
; Шаг: x += vx/10, y += vy/10 (деление с округлением от нуля), vy += 0.01, vx += ветер/50000.
; Тяжесть и ветер идут аккумуляторами с остатком: 16384/25 = 655 и остаток 9; ветер·4096/3125 считается один раз
; на выстрел (частное fl_wq, остаток fl_wr), дальше только сложения.

FL_X0		equ	3
FL_X1		equ	252
FL_Y0		equ	27
FL_Y1		equ	252
FL_BALL		equ	3

flight:
	; --- дульная точка и скорость ---
	ld	a, (fl_angle)
	ld	l, a
	ld	h, 0
	call	fx_sincos
	ld	hl, fl_x		; x = cos·10·facing + tank_x
	ld	de, fx_cos
	call	fl_mul10
	ld	a, (fl_facing)
	or	a
	jp	p, fl_m1
	ld	hl, fl_x
	ld	b, 4
	call	fx_negm
fl_m1:
	ld	a, (fl_tx)
	ld	e, a
	ld	d, 0
	ld	hl, (fl_x + 2)
	add	hl, de
	ld	(fl_x + 2), hl
	ld	hl, fl_y		; y = tank_y − sin·10
	ld	de, fx_sin
	call	fl_mul10
	ld	hl, fl_y
	ld	b, 4
	call	fx_negm
	ld	a, (fl_ty)
	ld	e, a
	ld	d, 0
	ld	hl, (fl_y + 2)
	add	hl, de
	ld	(fl_y + 2), hl
	; speed = power / 50
	ld	hl, 0
	ld	(fx_a), hl
	ld	hl, (fl_power)
	ld	(fx_a + 2), hl
	ld	de, 50
	call	fx_idiv
	ld	hl, fl_t2		; сохранить speed
	ld	de, fx_a
	ld	b, 4
	call	fx_copy
	ld	hl, fx_b
	ld	de, fx_cos
	ld	b, 4
	call	fx_copy
	call	fx_mul			; vx = speed·cos
	ld	a, (fl_facing)
	or	a
	jp	p, fl_m2
	call	fx_neg_a
fl_m2:
	ld	hl, fl_vx
	ld	de, fx_a
	ld	b, 4
	call	fx_copy
	ld	hl, fx_a
	ld	de, fl_t2
	ld	b, 4
	call	fx_copy
	ld	hl, fx_b
	ld	de, fx_sin
	ld	b, 4
	call	fx_copy
	call	fx_mul			; vy = −speed·sin
	call	fx_neg_a
	ld	hl, fl_vy
	ld	de, fx_a
	ld	b, 4
	call	fx_copy
	; --- ветер: W = wind·4096 = fl_wq·3125 + fl_wr ---
	ld	hl, fx_w
	ld	b, 8
	call	fx_zero
	ld	hl, (fl_wind)
	ld	a, h
	or	a
	push	af
	jp	p, fl_w1
	ld	a, l
	cpl
	ld	l, a
	ld	a, h
	cpl
	ld	h, a
	inc	hl			; |wind|
fl_w1:
	ld	(fx_w + 1), hl		; |wind|·256
	or	a
	ld	b, 4			; ещё ·16
fl_w2:
	push	bc
	or	a
	ld	hl, fx_w
	ld	b, 4
	call	fx_shl
	pop	bc
	dec	b
	jp	nz, fl_w2
	ld	hl, 3125
	ld	(fx_d), hl
	ld	hl, 0
	ld	(fx_d + 2), hl
	call	fx_divu
	ld	hl, fl_wq
	ld	de, fx_w
	ld	b, 4
	call	fx_copy
	ld	hl, (fx_rm)
	ld	(fl_wr), hl
	pop	af
	jp	p, fl_w3
	ld	hl, fl_wq		; отрицательный ветер: частное и остаток со знаком
	ld	b, 4
	call	fx_negm
	ld	hl, fl_wr
	ld	b, 2
	call	fx_negm
fl_w3:
	; --- начальное состояние ---
	ld	hl, 0
	ld	(fl_wrem), hl
	xor	a
	ld	(fl_grem), a
	ld	(fl_hit), a
	ld	a, (fl_players)
	ld	(fl_sub), a
	ld	hl, 0
	ld	(fl_px), hl
	ld	(fl_py), hl
	ld	hl, -99
	ld	(fl_px + 2), hl
	ld	(fl_py + 2), hl
	ld	hl, (fl_men)		; fuse = 1000 − 2·men
	add	hl, hl
	ld	a, l
	cpl
	ld	l, a
	ld	a, h
	cpl
	ld	h, a
	inc	hl
	ld	de, 1000
	add	hl, de
	ld	(fl_fuse), hl
	ld	hl, 199999 & 0xFFFF	; 200000 проходов цикла
	ld	(fl_cnt), hl
	ld	a, 199999 >> 16
	ld	(fl_cnt + 2), a

fl_loop:
	ld	a, (fl_sub)		; подшаг 0..10
	inc	a
	cp	11
	jp	c, fl_s1
	xor	a
fl_s1:
	ld	(fl_sub), a
	; x += vx/10; y += vy/10
	ld	de, fl_vx
	call	fl_div10
	ld	hl, fl_x
	ld	de, fl_t
	ld	b, 4
	call	fx_addm
	ld	de, fl_vy
	call	fl_div10
	ld	hl, fl_y
	ld	de, fl_t
	ld	b, 4
	call	fx_addm
	; vy += 655 или 656
	ld	a, (fl_grem)
	add	a, 9
	ld	de, 655
	cp	25
	jp	c, fl_g1
	sub	25
	inc	de
fl_g1:
	ld	(fl_grem), a
	ld	hl, (fl_vy)
	add	hl, de
	ld	(fl_vy), hl
	jp	nc, fl_g2
	ld	hl, (fl_vy + 2)
	inc	hl
	ld	(fl_vy + 2), hl
fl_g2:
	; vx += fl_wq + поправка от остатка
	ld	hl, fl_vx
	ld	de, fl_wq
	ld	b, 4
	call	fx_addm
	ld	hl, (fl_wrem)
	ex	de, hl
	ld	hl, (fl_wr)
	add	hl, de			; r = wrem + wr, |r| < 6250
	ld	a, h
	or	a
	jp	m, fl_wn
	ld	de, -3125
	ex	de, hl
	add	hl, de			; r − 3125
	ld	a, h
	or	a
	jp	m, fl_wk		; r < 3125: оставить (в DE)
	ex	de, hl
	ld	hl, fl_vx		; vx += 1
fl_wi:
	inc	(hl)
	jp	nz, fl_wk
	inc	hl
	jp	fl_wi
fl_wn:					; r < 0
	ld	de, 3125
	ex	de, hl
	add	hl, de			; HL = r + 3125, DE = r
	ld	a, h
	or	a
	jp	m, fl_wn2		; r < −3125
	or	l
	jp	nz, fl_wk		; −3125 < r < 0: частное не меняется, остаток r (в DE)
fl_wn2:					; r <= −3125: частное −1, остаток r + 3125
	ex	de, hl
	ld	hl, fl_vx
	call	fl_dec32
fl_wk:
	ex	de, hl
	ld	(fl_wrem), hl

	; стереть мяч в предыдущей точке
	ld	a, (fl_ball)
	or	a
	jp	z, fl_e1
	ld	hl, fl_px
	ld	de, FL_X1
	call	fl_lt
	jp	nc, fl_e1
	ld	hl, fl_py
	ld	de, FL_Y0
	call	fl_gt
	jp	nc, fl_e1
	ld	hl, fl_px
	ld	de, FL_X0
	call	fl_gt
	jp	nc, fl_e1
	ld	a, (fl_px + 2)
	ld	d, a
	ld	a, (fl_py + 2)
	ld	e, a
	xor	a
	call	draw_cross
fl_e1:
	ld	hl, fl_px
	ld	de, fl_x
	ld	b, 4
	call	fx_copy
	ld	hl, fl_py
	ld	de, fl_y
	ld	b, 4
	call	fx_copy
	xor	a
	ld	(fl_stop), a
	ld	(fl_hit), a
	; в полосе поля?
	ld	hl, fl_y
	ld	de, FL_Y1
	call	fl_lt
	jp	nc, fl_out
	ld	hl, fl_x
	ld	de, FL_X1
	call	fl_lt
	jp	nc, fl_out
	ld	hl, fl_y
	ld	de, FL_Y0 + 2
	call	fl_gt
	jp	nc, fl_out
	ld	hl, fl_x
	ld	de, FL_X0
	call	fl_gt
	jp	nc, fl_out
	; ромб из пяти точек
	xor	a
	ld	(fl_done), a
	ld	hl, fl_diamond
	ld	a, 5
fl_d1:
	ld	(fl_i), a
	ld	a, (fl_x + 2)
	add	a, (hl)
	ld	d, a
	inc	hl
	ld	a, (fl_y + 2)
	add	a, (hl)
	ld	e, a
	inc	hl
	ld	(fl_dp), hl
	call	getpixel
	ld	c, a
	cp	1
	jp	z, fl_d_ground
	cp	4
	jp	c, fl_d_next		; 0, 2, 3 — не цель
	; танк
	ld	(fl_hit), a
	ld	a, 1
	ld	(fl_done), a
	ld	a, (fl_weapon)		; грязь 12..16 отскакивает от танка
	cp	12
	jp	c, fl_d_next
	cp	17
	jp	nc, fl_d_next
	xor	a
	ld	(fl_done), a
	ld	hl, fx_a
	ld	de, fl_vy
	ld	b, 4
	call	fx_copy
	call	fx_neg_a
	ld	hl, 78643 & 0xFFFF	; 1.2
	ld	(fx_b), hl
	ld	hl, 78643 >> 16
	ld	(fx_b + 2), hl
	call	fx_mul
	ld	hl, fl_vy
	ld	de, fx_a
	ld	b, 4
	call	fx_copy
	jp	fl_d_next
fl_d_ground:
	ld	(fl_hit), a
	; done = (sub == 10) или (power < fuse); при power == fuse — done = 0
	ld	hl, (fl_fuse)
	ex	de, hl
	ld	hl, (fl_power)
	call	fl_scmp			; A: 0 равно, 1 больше, 0xFF меньше (power ? fuse)
	or	a
	jp	z, fl_d_g0
	cp	0xFF
	jp	z, fl_d_g1
	ld	a, (fl_sub)
	cp	10
	jp	nz, fl_d_next
fl_d_g1:
	ld	a, 1
	ld	(fl_done), a
	jp	fl_d_next
fl_d_g0:
	xor	a
	ld	(fl_done), a
fl_d_next:
	ld	hl, (fl_dp)
	ld	a, (fl_i)
	dec	a
	jp	nz, fl_d1
	ld	a, (fl_done)
	or	a
	jp	z, fl_chk
	ld	a, (fl_hit)
	cp	4
	ld	a, 1
	jp	c, fl_d_st
	inc	a
fl_d_st:
	ld	(fl_stop), a
	jp	fl_chk

fl_out:					; вне полосы
	ld	a, (fl_rebound)
	or	a
	jp	z, fl_nr
	; отражающие стены
	ld	a, (fl_vx + 3)
	or	a
	jp	p, fl_r1
	ld	hl, fl_x
	ld	de, FL_X0 - 1
	call	fl_lt
	jp	nc, fl_r2
	ld	hl, fl_vx
	ld	b, 4
	call	fx_negm
	jp	fl_r2
fl_r1:
	ld	hl, fl_vx
	call	fl_nz
	jp	z, fl_r2
	ld	hl, fl_x
	ld	de, FL_X1 + 1
	call	fl_gt
	jp	nc, fl_r2
	ld	hl, fl_vx
	ld	b, 4
	call	fx_negm
fl_r2:
	ld	a, (fl_vy + 3)
	or	a
	jp	p, fl_r3
	ld	hl, fl_y
	ld	de, FL_Y0 - 1
	call	fl_lt
	jp	nc, fl_chk
	ld	hl, fl_vy
	ld	b, 4
	call	fx_negm
	jp	fl_chk
fl_r3:
	ld	hl, fl_vy
	call	fl_nz
	jp	z, fl_chk
	ld	hl, fl_y
	ld	de, FL_Y1 + 1
	call	fl_gt
	jp	nc, fl_chk
	ld	hl, fl_vy
	ld	b, 4
	call	fx_negm
	jp	fl_chk
fl_nr:					; стены обычные: снаряд, уносимый ветром, считается улетевшим
	ld	hl, (fl_wind)
	ld	a, h
	or	l
	jp	z, fl_chk
	ld	a, h
	or	a
	jp	m, fl_nr2
	ld	hl, fl_vx		; ветер > 0: vx > 1 и x > X1 + 1
	ld	de, 1
	call	fl_gt
	jp	nc, fl_chk
	ld	hl, fl_x
	ld	de, FL_X1 + 1
	call	fl_gt
	jp	nc, fl_chk
	jp	fl_snap
fl_nr2:
	ld	hl, fl_vx		; ветер < 0: vx < 1 и x < X0 − 1
	ld	de, 1
	call	fl_lt
	jp	nc, fl_chk
	ld	hl, fl_x
	ld	de, FL_X0 - 1
	call	fl_lt
	jp	nc, fl_chk
fl_snap:
	ld	hl, 0
	ld	(fl_y), hl
	ld	hl, FL_Y1 + 11
	ld	(fl_y + 2), hl
fl_chk:
	ld	a, (fl_stop)
	or	a
	jp	nz, fl_fin
	ld	hl, fl_y		; y < −5000 или y > Y1 + 4 — вылет
	ld	de, -5000
	call	fl_lt
	jp	c, fl_bnd
	ld	hl, fl_y
	ld	de, FL_Y1 + 4
	call	fl_gt
	jp	nc, fl_cont
fl_bnd:
	ld	a, 3
	ld	(fl_stop), a
fl_fin:
	; стереть мяч в точке остановки, если она на экране
	ld	hl, fl_y
	ld	de, 0
	call	fl_gt
	ret	nc
	ld	hl, fl_y
	ld	de, 256
	call	fl_lt
	ret	nc
	ld	hl, fl_x
	ld	de, 0
	call	fl_gt
	ret	nc
	ld	hl, fl_x
	ld	de, 256
	call	fl_lt
	ret	nc
	ld	a, (fl_x + 2)
	ld	d, a
	ld	a, (fl_y + 2)
	ld	e, a
	xor	a
	jp	draw_cross
fl_cont:
	ld	a, (fl_ball)
	or	a
	jp	z, fl_c1
	ld	hl, fl_x
	ld	de, FL_X1
	call	fl_lt
	jp	nc, fl_c1
	ld	hl, fl_y
	ld	de, FL_Y0
	call	fl_gt
	jp	nc, fl_c1
	ld	hl, fl_x
	ld	de, FL_X0
	call	fl_gt
	jp	nc, fl_c1
	ld	a, (fl_x + 2)
	ld	d, a
	ld	a, (fl_y + 2)
	ld	e, a
	ld	a, FL_BALL
	call	draw_cross
fl_c1:
	ld	hl, (fl_cnt)		; счётчик шагов (200000)
	ld	a, h
	or	l
	dec	hl
	ld	(fl_cnt), hl
	jp	nz, fl_loop
	ld	a, (fl_cnt + 2)
	or	a
	jp	z, fl_max
	dec	a
	ld	(fl_cnt + 2), a
	jp	fl_loop
fl_max:
	xor	a
	ld	(fl_stop), a
	ld	(fl_hit), a
	ret

fl_diamond:
	db	-1, 0,  0, -1,  0, 0,  0, 1,  1, 0

; (HL) = (DE)·10, 4 байта
fl_mul10:
	push	hl
	ld	b, 4
	call	fx_copy			; (HL) = v
	pop	hl
	push	hl
	or	a
	ld	b, 4
	call	fx_shl			; 2v
	pop	hl
	push	hl
	ld	de, fl_t
	ex	de, hl
	ld	b, 4
	call	fx_copy			; fl_t = 2v
	pop	hl
	push	hl
	or	a
	ld	b, 4
	call	fx_shl			; 4v
	pop	hl
	push	hl
	or	a
	ld	b, 4
	call	fx_shl			; 8v
	pop	hl
	ld	de, fl_t
	ld	b, 4
	jp	fx_addm			; 8v + 2v

; fl_t = (DE)/10 с округлением от нуля; (DE) — 32 бита со знаком
fl_div10:
	ld	hl, fl_t
	ld	b, 4
	call	fx_copy
	ld	a, (fl_t + 3)
	or	a
	push	af
	jp	p, fl_dv1
	ld	hl, fl_t
	ld	b, 4
	call	fx_negm
fl_dv1:
	ld	hl, fl_t		; + 5
	ld	a, (hl)
	add	a, 5
	ld	(hl), a
	jp	nc, fl_dv3
fl_dv2:
	inc	hl
	inc	(hl)
	jp	z, fl_dv2
fl_dv3:
	ld	hl, fl_t + 3		; деление столбиком по байтам, остаток в E
	ld	e, 0
	ld	d, 4
fl_dv4:
	ld	c, (hl)
	ld	b, 8
fl_dv5:
	ld	a, c
	add	a, a
	ld	c, a
	ld	a, e
	rla
	cp	10
	jp	c, fl_dv6
	sub	10
	inc	c
fl_dv6:
	ld	e, a
	dec	b
	jp	nz, fl_dv5
	ld	(hl), c
	dec	hl
	dec	d
	jp	nz, fl_dv4
	pop	af
	ret	p
	ld	hl, fl_t
	ld	b, 4
	jp	fx_negm

; 32-битное значение по адресу HL уменьшить на 1
fl_dec32:
	ld	a, (hl)
	sub	1
	ld	(hl), a
	ret	nc
	inc	hl
	jp	fl_dec32

; ZF = 1, если 32-битное значение по адресу HL равно нулю
fl_nz:
	ld	a, (hl)
	inc	hl
	or	(hl)
	inc	hl
	or	(hl)
	inc	hl
	or	(hl)
	ret

; знаковое сравнение слов: HL ? DE -> A = 0 (равно), 1 (больше), 0xFF (меньше)
fl_scmp:
	ld	a, h
	xor	0x80
	ld	b, a
	ld	a, d
	xor	0x80
	cp	b
	jp	c, fl_sc_gt		; D' < H' : HL больше
	jp	nz, fl_sc_lt
	ld	a, e
	cp	l
	jp	c, fl_sc_gt
	jp	nz, fl_sc_lt
	xor	a
	ret
fl_sc_gt:
	ld	a, 1
	ret
fl_sc_lt:
	ld	a, 0xFF
	ret

; CF = 1, если значение Q16.16 по адресу HL меньше целого DE
fl_lt:
	inc	hl
	inc	hl
	ld	a, (hl)
	inc	hl
	ld	h, (hl)
	ld	l, a
	call	fl_scmp
	cp	0xFF
	scf
	ret	z
	or	a
	ret
; CF = 1, если значение Q16.16 по адресу HL больше целого DE
fl_gt:
	ld	c, (hl)
	inc	hl
	ld	a, (hl)
	or	c
	ld	c, a			; C != 0, если есть дробная часть
	inc	hl
	ld	a, (hl)
	inc	hl
	ld	h, (hl)
	ld	l, a
	push	bc
	call	fl_scmp
	pop	bc
	cp	1
	scf
	ret	z
	or	a
	ret	nz			; меньше
	ld	a, c			; целые части равны: больше, если дробная часть не ноль
	or	a
	ret	z			; CF = 0
	scf
	ret
flight_end:

fl_angle:	db	0
fl_facing:	db	0
fl_power:	dw	0
fl_tx:		db	0
fl_ty:		db	0
fl_wind:	dw	0
fl_rebound:	db	0
fl_weapon:	db	0
fl_men:		dw	0
fl_players:	db	0
fl_ball:	db	0
fl_stop:	db	0
fl_hit:		db	0
fl_x:		ds	4
fl_y:		ds	4
fl_vx:		ds	4
fl_vy:		ds	4
fl_px:		ds	4
fl_py:		ds	4
fl_t:		ds	4
fl_t2:		ds	4
fl_wq:		ds	4
fl_wr:		dw	0
fl_wrem:	dw	0
fl_grem:	db	0
fl_sub:		db	0
fl_fuse:	dw	0
fl_done:	db	0
fl_i:		db	0
fl_dp:		dw	0
fl_cnt:		ds	3
