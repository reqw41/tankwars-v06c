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
	xor	a
	ld	(fl_drawn), a
	ld	(fl_qx_ok), a
	ld	(fl_qy_ok), a
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
	; vx/10 пересчитывается, только когда vx менялась (ветер, отражение)
	ld	a, (fl_qx_ok)
	or	a
	jp	nz, fl_ax0
	ld	de, fl_vx
	call	fl_div10		; HL:DE = vx/10
	ld	(fl_qx + 2), hl
	ex	de, hl
	ld	(fl_qx), hl
	ld	a, 1
	ld	(fl_qx_ok), a
fl_ax0:
	ld	hl, (fl_qx)
	ex	de, hl
	ld	hl, (fl_x)
	add	hl, de
	ld	(fl_x), hl
	ld	hl, (fl_qx + 2)
	ex	de, hl
	ld	hl, (fl_x + 2)
	jp	nc, fl_ax
	inc	hl
fl_ax:
	add	hl, de
	ld	(fl_x + 2), hl
	; vy/10: между пересчётами ведётся приращением (тяжесть 655/656 = 65·10 + 5/6), остаток — в fl_ry
	ld	a, (fl_qy_ok)
	or	a
	jp	nz, fl_ay0
	ld	de, fl_vy
	call	fl_div10
	ld	(fl_qy + 2), hl
	ex	de, hl
	ld	(fl_qy), hl
	ld	a, b			; остаток·16 от (|vy| + 5)
	rrca
	rrca
	rrca
	rrca
	ld	(fl_ry), a
	ld	a, 1
	ld	(fl_qy_ok), a
fl_ay0:
	ld	hl, (fl_qy)
	ex	de, hl
	ld	hl, (fl_y)
	add	hl, de
	ld	(fl_y), hl
	ld	hl, (fl_qy + 2)
	ex	de, hl
	ld	hl, (fl_y + 2)
	jp	nc, fl_ay
	inc	hl
fl_ay:
	add	hl, de
	ld	(fl_y + 2), hl
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
	ld	a, (fl_vy + 3)
	ld	c, a			; знак vy до прибавки
	ld	a, e			; 655 -> 5, 656 -> 6: остаток прибавки по модулю 10
	sub	(655 & 255) - 5
	ld	b, a
	ld	hl, (fl_vy)
	add	hl, de
	ld	(fl_vy), hl
	jp	nc, fl_g2
	ld	hl, (fl_vy + 2)
	inc	hl
	ld	(fl_vy + 2), hl
fl_g2:
	ld	a, (fl_vy + 3)
	xor	c
	jp	p, fl_gq		; знак тот же — частное ведём приращением
	xor	a
	ld	(fl_qy_ok), a		; знак сменился — пересчитать делением
	jp	fl_gq3
fl_gq:
	ld	de, 65
	ld	a, c
	or	a
	ld	a, (fl_ry)
	jp	m, fl_gqn
	add	a, b			; vy >= 0: остаток растёт
	cp	10
	jp	c, fl_gq1
	sub	10
	inc	de
	jp	fl_gq1
fl_gqn:
	sub	b			; vy < 0: остаток убывает
	jp	nc, fl_gq1
	add	a, 10
	inc	de
fl_gq1:
	ld	(fl_ry), a
	ld	hl, (fl_qy)
	add	hl, de
	ld	(fl_qy), hl
	jp	nc, fl_gq3
	ld	hl, (fl_qy + 2)
	inc	hl
	ld	(fl_qy + 2), hl
fl_gq3:
	; ветер: при нулевом ветре vx не меняется
	ld	hl, (fl_wind)
	ld	a, h
	or	l
	jp	z, fl_wz
	xor	a
	ld	(fl_qx_ok), a
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
fl_wz:
	ld	a, (fl_guided)
	or	a
	call	nz, fl_guide

	; стереть мяч в предыдущей точке (он рисовался при том же условии, что раньше проверялось здесь)
	ld	a, (fl_drawn)
	cp	2			; 2 — мяч нарисован быстрым путём: вокруг было пусто
	jp	nz, fl_er
	ld	a, (fl_x + 3)
	ld	b, a
	ld	a, (fl_y + 3)
	or	b
	jp	nz, fl_er
	ld	a, (fl_ex)
	ld	b, a
	ld	a, (fl_x + 2)
	cp	b
	jp	nz, fl_er
	ld	a, (fl_ey)
	ld	b, a
	ld	a, (fl_y + 2)
	cp	b
	jp	z, fl_c1		; точка та же: на экране ничего не меняется, проверка дала бы то же
fl_er:
	ld	a, (fl_drawn)
	or	a
	jp	z, fl_e1
	xor	a
	ld	(fl_drawn), a
	ld	a, (fl_ex)
	ld	d, a
	ld	a, (fl_ey)
	ld	e, a
	call	fl_fastq
	jp	nc, fl_e0
	xor	a
	call	fl_cross
	jp	fl_e1
fl_e0:
	call	fl_mark
	xor	a
	call	draw_cross
fl_e1:
	xor	a
	ld	(fl_stop), a
	ld	(fl_hit), a
	; быстрый путь: точка внутри поля с запасом (x 4..251, y 30..251) и все пять точек ромба пусты
	ld	a, (fl_x + 3)
	ld	b, a
	ld	a, (fl_y + 3)
	or	b
	jp	nz, fl_slow
	ld	a, (fl_x + 2)
	ld	d, a
	ld	a, (fl_y + 2)
	ld	e, a
	cp	FL_Y0 + 3
	jp	c, fl_slow
	call	fl_fastq
	jp	nc, fl_slow
	call	fl_air
	jp	nz, fl_dmd		; что-то есть — разбор по точкам
	ld	a, (fl_ball)
	or	a
	jp	z, fl_c1
	ld	a, (fl_x + 2)
	ld	d, a
	ld	(fl_ex), a
	ld	a, (fl_y + 2)
	ld	e, a
	ld	(fl_ey), a
	ld	a, 2
	ld	(fl_drawn), a
	ld	a, FL_BALL
	call	fl_cross
	jp	fl_c1
fl_slow:
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
fl_dmd:
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
	ld	(fl_guided), a		; после отскока наведение выключено
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
	xor	a
	ld	(fl_qy_ok), a
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
	xor	a
	ld	(fl_qx_ok), a
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
	xor	a
	ld	(fl_qx_ok), a
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
	xor	a
	ld	(fl_qy_ok), a
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
	xor	a
	ld	(fl_qy_ok), a
	jp	fl_chk
fl_nr:					; стены обычные: снаряд, уносимый ветром, считается улетевшим
	ld	a, (fl_guided)		; с наведением этого правила нет
	or	a
	jp	nz, fl_chk
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
	jp	c, fl_bnd
	ld	a, (fl_guided)		; наведённый снаряд далеко за полем (x < −64 или x > 320) — улетел
	or	a
	jp	z, fl_cont
	ld	hl, fl_x
	ld	de, -64
	call	fl_lt
	jp	c, fl_bnd
	ld	hl, fl_x
	ld	de, 320
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
	call	fl_mark
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
	ld	(fl_ex), a
	ld	a, (fl_y + 2)
	ld	e, a
	ld	(fl_ey), a
	ld	a, 1
	ld	(fl_drawn), a
	call	fl_mark
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

; мяч рисуется или стирается не в чистом воздухе (D = x): пометить столбцы для осыпания. DE цел.
fl_mark:
	push	de
	ld	a, d
	ld	b, 2
	call	cr_mark_x
	pop	de
	ret
; Наведение — guideFix() эталона. fl_guided: бит 0 — Herb's Guide, бит 1 — Vick's Guide; цель — (fl_gtx, fl_gty).
; Vick: по x ближе 2 точек к цели — vx = 0, снаряд идёт к цели по вертикали шагом 0.5.
; Herb: по y ближе 2 точек — vy = 0, vx растёт в 1.01 раза в сторону цели.
fl_guide:
	ld	hl, fl_x
	ld	de, fl_tdx
	ld	a, (fl_gtx)
	call	fl_gsub
	ld	hl, fl_y
	ld	de, fl_tdy
	ld	a, (fl_gty)
	call	fl_gsub
	ld	a, (fl_guided)
	and	2
	jp	z, fl_gh
	ld	hl, fl_tdx
	call	fl_le2
	jp	nc, fl_gh
	ld	hl, 0
	ld	(fl_vx), hl
	ld	(fl_vx + 2), hl
	xor	a
	ld	(fl_qx_ok), a
	; y += 0.5 при tdy > 0, иначе −0.5
	ld	hl, fl_tdy
	call	fl_nz
	ld	de, -1
	jp	z, fl_gv1
	ld	a, (fl_tdy + 3)
	or	a
	jp	m, fl_gv1
	ld	de, 0
fl_gv1:
	ld	hl, (fl_y)		; ± 0x8000 в младшем слове
	ld	a, h
	add	a, 0x80
	ld	h, a
	ld	(fl_y), hl
	ld	hl, (fl_y + 2)
	jp	nc, fl_gv2
	inc	hl
fl_gv2:
	add	hl, de			; +0.5: +0x8000 и перенос; −0.5: +0x8000 − 0x10000
	ld	(fl_y + 2), hl
fl_gh:
	ld	a, (fl_guided)
	and	1
	ret	z
	ld	hl, fl_tdy
	call	fl_le2
	ret	nc
	ld	hl, 0
	ld	(fl_vy), hl
	ld	(fl_vy + 2), hl
	xor	a
	ld	(fl_qy_ok), a
	ld	(fl_qx_ok), a
	; разгон только пока |vx| < 64
	ld	hl, (fl_vx + 2)
	ld	a, h
	or	a
	jp	p, fl_gh0
	ld	a, (fl_vx)
	ld	b, a
	ld	a, (fl_vx + 1)
	or	b
	jp	z, fl_ghn		; отрицательное без дроби: |vx| = −целая часть
	inc	hl			; с дробью: |vx| < −(целая часть) ... сравнение по целой части + 1
fl_ghn:
	call	lb_neg
fl_gh0:
	ld	de, 64
	call	lb_ge
	ret	nc			; |vx| >= 64
	ld	hl, fx_a
	ld	de, fl_tdx
	ld	b, 4
	call	fx_copy
	ld	hl, fx_b
	ld	de, fl_vx
	ld	b, 4
	call	fx_copy
	call	fx_mul			; знак tdx · vx
	ld	a, (fx_a + 3)
	push	af
	ld	hl, fx_a
	ld	de, fl_vx
	ld	b, 4
	call	fx_copy
	ld	hl, 66191 & 0xFFFF	; 1.01
	ld	(fx_b), hl
	ld	hl, 66191 >> 16
	ld	(fx_b + 2), hl
	pop	af
	or	a
	jp	p, fl_gh1
	ld	hl, fx_b
	ld	b, 4
	call	fx_negm
fl_gh1:
	call	fx_mul
	ld	hl, fl_vx
	ld	de, fx_a
	ld	b, 4
	jp	fx_copy
; (DE) = A·65536 − (HL), 4 байта
fl_gsub:
	ld	c, a
	xor	a
	sub	(hl)
	ld	(de), a
	inc	hl
	inc	de
	ld	a, 0
	sbc	a, (hl)
	ld	(de), a
	inc	hl
	inc	de
	ld	a, c
	sbc	a, (hl)
	ld	(de), a
	inc	hl
	inc	de
	ld	a, 0
	sbc	a, (hl)
	ld	(de), a
	ret
; CF = 1, если |значение Q16.16 по адресу HL| <= 2.0
fl_le2:
	ld	de, fx_a
	ex	de, hl
	ld	b, 4
	call	fx_copy
	call	fx_abs_a
	ld	a, (fx_a + 3)
	or	a
	ret	nz			; CF = 0
	ld	a, (fx_a + 2)
	cp	2
	ret	c
	jp	nz, fl_le2n
	ld	hl, (fx_a)
	ld	a, h
	or	l
	jp	nz, fl_le2n
	scf
	ret
fl_le2n:
	or	a
	ret

; HL:DE = (DE)/10 с округлением от нуля; (DE) — 32 бита со знаком. Деление — по полубайтам через таблицу fl_d10.
fl_div10:
	ex	de, hl
	ld	e, (hl)
	inc	hl
	ld	d, (hl)
	inc	hl
	ld	a, (hl)
	inc	hl
	ld	h, (hl)
	ld	l, a			; HL:DE = значение
	ld	a, h
	or	a
	push	af
	call	m, fl_neg32
	ld	a, e			; + 5
	add	a, 5
	ld	e, a
	jp	nc, fl_dv1
	inc	d
	jp	nz, fl_dv1
	inc	hl
fl_dv1:
	ld	b, 0			; остаток·16
	ld	a, h
	or	a
	call	nz, fl_dvb		; старший байт почти всегда ноль
	ld	h, a
	ld	a, l
	call	fl_dvb
	ld	l, a
	ld	a, d
	call	fl_dvb
	ld	d, a
	ld	a, e
	call	fl_dvb
	ld	e, a
	pop	af
	ret	p
fl_neg32:
	ld	a, e
	cpl
	ld	e, a
	ld	a, d
	cpl
	ld	d, a
	ld	a, l
	cpl
	ld	l, a
	ld	a, h
	cpl
	ld	h, a
	inc	de
	ld	a, d
	or	e
	ret	nz
	inc	hl
	ret
; байт A с остатком B (остаток·16) разделить на 10: A = частное, B = новый остаток·16. HL, DE целы.
fl_dvb:
	push	hl
	ld	c, a
	rrca
	rrca
	rrca
	rrca
	and	0x0F
	or	b
	ld	l, a
	ld	h, fl_d10 >> 8
	ld	a, (hl)
	ld	b, a
	and	0xF0
	ld	l, a
	ld	a, c
	and	0x0F
	or	l
	ld	l, a
	ld	a, b
	and	0x0F
	rlca
	rlca
	rlca
	rlca
	ld	c, a
	ld	a, (hl)
	ld	b, a
	and	0x0F
	or	c
	ld	c, a
	ld	a, b
	and	0xF0
	ld	b, a
	ld	a, c
	pop	hl
	ret

; CF = 1, если точка (D, E) внутри поля с запасом на крестик: x 4..251, y 28..251
fl_fastq:
	ld	a, d
	sub	4
	cp	248
	ret	nc
	ld	a, e
	sub	28
	cp	224
	ret
; адрес и маска точки (D, E): HL — байт в плоскости A000, C — маска. DE цел.
fl_addr:
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
	add	a, fl_masks & 255
	ld	c, a
	ld	b, fl_masks >> 8
	ld	a, (bc)
	ld	c, a
	ret
; ZF = 1, если пять точек ромба вокруг (D, E) — цвета 0. Точка должна проходить fl_fastq.
fl_air:
	call	fl_addr
	call	fl_get3
	ret	nz
	inc	l			; y − 1
	call	fl_get3
	ret	nz
	dec	l
	dec	l			; y + 1
	call	fl_get3
	ret	nz
	inc	l
	call	fl_left
	call	fl_get3
	ret	nz
	call	fl_right
	call	fl_right
; A = точка (HL, маска C) в трёх плоскостях: 0 — цвет 0. HL цел.
fl_get3:
	ld	a, (hl)
	ld	b, a
	ld	a, h
	add	a, 0x20
	ld	h, a
	ld	a, (hl)
	or	b
	ld	b, a
	ld	a, h
	add	a, 0x20
	ld	h, a
	ld	a, (hl)
	or	b
	and	c
	ld	b, a
	ld	a, h
	sub	0x40
	ld	h, a
	ld	a, b
	or	a
	ret
; сосед слева / справа: маска и, если надо, столбец байтов
fl_left:
	ld	a, c
	rlca
	ld	c, a
	ret	nc
	dec	h
	ret
fl_right:
	ld	a, c
	rrca
	ld	c, a
	ret	nc
	inc	h
	ret
; крестик из пяти точек вокруг (D, E) цветом A (0 или FL_BALL). Точка должна проходить fl_fastq.
fl_cross:
	ld	(fl_cc), a
	call	fl_addr
	call	fl_plot
	inc	l
	call	fl_plot
	dec	l
	dec	l
	call	fl_plot
	inc	l
	call	fl_left
	call	fl_plot
	call	fl_right
	call	fl_right
fl_plot:
	ld	a, (fl_cc)
	or	a
	jp	z, fl_pl0
	ld	a, (hl)			; цвет 3: плоскости A000 и C000 — 1, E000 — 0
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
	ld	a, h
	sub	0x40
	ld	h, a
	ret
fl_pl0:
	ld	a, c
	cpl
	ld	b, a
	and	(hl)
	ld	(hl), a
	ld	a, h
	add	a, 0x20
	ld	h, a
	ld	a, (hl)
	and	b
	ld	(hl), a
	ld	a, h
	add	a, 0x20
	ld	h, a
	ld	a, (hl)
	and	b
	ld	(hl), a
	ld	a, h
	sub	0x40
	ld	h, a
	ret

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
fl_guided:	db	0			; наведение: бит 0 — Herb, бит 1 — Vick; 0 — нет
fl_gtx:		db	0			; цель наведения
fl_gty:		db	0
fl_tdx:		ds	4
fl_tdy:		ds	4
fl_stop:	db	0
fl_hit:		db	0
fl_x:		ds	4
fl_y:		ds	4
fl_vx:		ds	4
fl_vy:		ds	4
fl_qx_ok:	db	0			; fl_qx = vx/10 верно
fl_qy_ok:	db	0
fl_ry:		db	0			; остаток (|vy| + 5) mod 10
fl_qx:		ds	4
fl_qy:		ds	4
fl_drawn:	db	0			; мяч нарисован в (fl_ex, fl_ey)
fl_ex:		db	0
fl_ey:		db	0
fl_cc:		db	0
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
; таблицы на границе страницы: индекс — младший байт адреса
	align	256
fl_d10:					; [остаток·16 + полубайт] = (новый остаток)·16 + частное
	db	0x00, 0x10, 0x20, 0x30, 0x40, 0x50, 0x60, 0x70, 0x80, 0x90, 0x01, 0x11, 0x21, 0x31, 0x41, 0x51
	db	0x61, 0x71, 0x81, 0x91, 0x02, 0x12, 0x22, 0x32, 0x42, 0x52, 0x62, 0x72, 0x82, 0x92, 0x03, 0x13
	db	0x23, 0x33, 0x43, 0x53, 0x63, 0x73, 0x83, 0x93, 0x04, 0x14, 0x24, 0x34, 0x44, 0x54, 0x64, 0x74
	db	0x84, 0x94, 0x05, 0x15, 0x25, 0x35, 0x45, 0x55, 0x65, 0x75, 0x85, 0x95, 0x06, 0x16, 0x26, 0x36
	db	0x46, 0x56, 0x66, 0x76, 0x86, 0x96, 0x07, 0x17, 0x27, 0x37, 0x47, 0x57, 0x67, 0x77, 0x87, 0x97
	db	0x08, 0x18, 0x28, 0x38, 0x48, 0x58, 0x68, 0x78, 0x88, 0x98, 0x09, 0x19, 0x29, 0x39, 0x49, 0x59
	db	0x69, 0x79, 0x89, 0x99, 0x0A, 0x1A, 0x2A, 0x3A, 0x4A, 0x5A, 0x6A, 0x7A, 0x8A, 0x9A, 0x0B, 0x1B
	db	0x2B, 0x3B, 0x4B, 0x5B, 0x6B, 0x7B, 0x8B, 0x9B, 0x0C, 0x1C, 0x2C, 0x3C, 0x4C, 0x5C, 0x6C, 0x7C
	db	0x8C, 0x9C, 0x0D, 0x1D, 0x2D, 0x3D, 0x4D, 0x5D, 0x6D, 0x7D, 0x8D, 0x9D, 0x0E, 0x1E, 0x2E, 0x3E
	db	0x4E, 0x5E, 0x6E, 0x7E, 0x8E, 0x9E, 0x0F, 0x1F, 0x2F, 0x3F, 0x4F, 0x5F, 0x6F, 0x7F, 0x8F, 0x9F
fl_masks:
	db	0x80, 0x40, 0x20, 0x10, 0x08, 0x04, 0x02, 0x01
