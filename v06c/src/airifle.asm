; Трасса по экрану и планировщик Rifleman — planRiflemanFix(), bigWeapon() эталона web/tankwars.js (PROFILE_V06C).
;   ai_trace:   вход tr_x0, tr_y0 (слова со знаком), tr_ex, tr_ey (слова со знаком), tr_mode:
;               0 — X = x0 + trunc(sx·s), Y = y0 + trunc(sy·s)          (Rifleman);
;               1 — X = trunc(x0 + sx·s), Y = trunc(y0 + sy·s)          (Twanger, второй отрезок);
;               2 — X = trunc(x0 + sx·s), Y = trunc(y0 − sy·s)          (Twanger, первый отрезок).
;               sx = ex/dist, sy = ey/dist, s = 1..trunc(dist). Выход HL = число точек земли (цвет 1) на пути;
;               точки вне экрана землёй не считаются.
;   plan_rifle: вход A = место игрока 1..n, ap_rebound (0/1).
;   ai_big_weapon: вход aib_p (запись), aib_dx, aib_dy, aib_sc (слова со знаком), aib_w — оружие (меняется).

ai_trace:
	ld	hl, 0
	ld	(tr_cnt), hl
	ld	(fx_a), hl
	ld	(fx_b), hl
	ld	hl, (tr_ex)
	ld	(fx_a + 2), hl
	ld	hl, (tr_ey)
	ld	(fx_b + 2), hl
	call	fx_hypot
	ld	hl, tr_dist
	ld	de, fx_a
	ld	b, 4
	call	fx_copy
	ld	hl, (fx_a + 2)		; n = trunc(dist), dist >= 0
	ld	(tr_n), hl
	ld	a, h
	or	l
	ld	hl, (fx_a)
	or	h
	or	l
	jp	z, tr_ret		; dist == 0
	ld	hl, (tr_ex)
	ld	de, tr_sx
	call	tr_unit
	ld	hl, (tr_ey)
	ld	de, tr_sy
	call	tr_unit
	ld	a, (tr_mode)
	cp	2
	jp	nz, tr_go
	ld	hl, tr_sy
	ld	b, 4
	call	fx_negm
tr_go:
	ld	hl, tr_ax
	ld	b, 8
	call	fx_zero			; tr_ax, tr_ay
tr_step:
	ld	hl, (tr_n)
	ld	a, h
	or	l
	jp	z, tr_ret
	dec	hl
	ld	(tr_n), hl
	ld	hl, tr_ax
	ld	de, tr_sx
	ld	b, 4
	call	fx_addm
	ld	hl, tr_ay
	ld	de, tr_sy
	ld	b, 4
	call	fx_addm
	ld	hl, (tr_x0)
	ex	de, hl
	ld	hl, tr_ax
	call	tr_coord
	ld	a, h
	or	a
	jp	nz, tr_step		; X вне 0..255
	ld	a, l
	ld	(tr_x), a
	ld	hl, (tr_y0)
	ex	de, hl
	ld	hl, tr_ay
	call	tr_coord
	ld	a, h
	or	a
	jp	nz, tr_step
	ld	e, l
	ld	a, (tr_x)
	ld	d, a
	call	getpixel
	cp	1
	jp	nz, tr_step
	ld	hl, (tr_cnt)
	inc	hl
	ld	(tr_cnt), hl
	jp	tr_step
tr_ret:
	ld	hl, (tr_cnt)
	ret
; (DE) = HL / tr_dist, HL — целое со знаком
tr_unit:
	ld	(fx_a + 2), hl
	ld	hl, 0
	ld	(fx_a), hl
	push	de
	ld	hl, fx_b
	ld	de, tr_dist
	ld	b, 4
	call	fx_copy
	call	fx_div
	pop	hl
	ld	de, fx_a
	ld	b, 4
	jp	fx_copy
; координата шага: HL = адрес аккумулятора Q16.16, DE = начало. Выход HL = координата (слово со знаком).
tr_coord:
	ld	c, (hl)
	inc	hl
	ld	a, (hl)
	or	c
	ld	c, a			; C != 0 — есть дробная часть
	inc	hl
	ld	a, (hl)
	inc	hl
	ld	h, (hl)
	ld	l, a			; HL = целая часть аккумулятора
	ld	b, h			; знак аккумулятора
	add	hl, de			; + начало
	ld	a, (tr_mode)
	or	a
	jp	z, tr_c0
	ld	b, h			; режимы 1, 2: знак суммы
tr_c0:
	ld	a, b
	or	a
	ret	p
	ld	a, c
	or	a
	ret	z
	inc	hl			; отрицательное с дробью: усечение к нулю
	ret

plan_rifle:
	ld	(rf_place), a
	call	dt_ptr
	ld	(rf_p), hl
	ld	(aib_p), hl
	ld	a, 1
	call	aib_ammo
	call	rf_pos
	ld	a, 1
	jp	nz, rf_w0
	ld	a, 11
rf_w0:
	ld	(aib_w), a
	; очки целей: 1000 (цель не ниже), 100 (ниже), 0 (сам или мёртв) минус точки земли на прямой
	ld	a, 1
rf_k:
	ld	(rf_i), a
	ld	hl, 0
	ld	(rf_s), hl
	ld	b, a
	ld	a, (rf_place)
	cp	b
	jp	z, rf_sc
	ld	a, b
	call	dt_ptr
	ld	(rf_tp), hl
	ld	de, PL_ALIVE
	add	hl, de
	ld	a, (hl)
	or	a
	jp	z, rf_sc
	call	rf_delta		; tr_ex = t.x − p.x, tr_ey = t.y − p.y
	ld	hl, (tr_ey)
	ld	a, h
	or	a
	ld	de, 1000
	jp	m, rf_s1		; t.y < p.y
	or	l
	jp	z, rf_s1		; t.y == p.y
	ld	de, 100
rf_s1:
	ex	de, hl
	ld	(rf_s), hl
	ld	hl, (rf_p)
	ld	e, (hl)
	inc	hl
	ld	l, (hl)
	ld	h, 0
	ld	(tr_y0), hl
	ld	l, e
	ld	(tr_x0), hl
	xor	a
	ld	(tr_mode), a
	call	ai_trace
	ex	de, hl
	ld	hl, (rf_s)
	ld	a, l
	sub	e
	ld	l, a
	ld	a, h
	sbc	a, d
	ld	h, a
	ld	(rf_s), hl
rf_sc:
	ld	a, (rf_i)
	call	rf_slot
	ex	de, hl
	ld	hl, (rf_s)
	ex	de, hl
	ld	(hl), e
	inc	hl
	ld	(hl), d
	ld	a, (n_players)
	ld	b, a
	ld	a, (rf_i)
	cp	b
	jp	z, rf_best
	inc	a
	jp	rf_k
	; цель — первый с наибольшими очками
rf_best:
	ld	hl, -32767
	ld	(rf_s), hl
	xor	a
	ld	(rf_t), a
	ld	a, 1
rf_b:
	ld	(rf_i), a
	call	rf_slot
	ld	e, (hl)
	inc	hl
	ld	d, (hl)
	ex	de, hl
	ld	(rf_tmp), hl
	ex	de, hl
	ld	hl, (rf_s)
	ex	de, hl
	ld	hl, (rf_tmp)
	call	fl_scmp			; очки ? лучший
	cp	1
	jp	nz, rf_bn
	ld	hl, (rf_tmp)
	ld	(rf_s), hl
	ld	a, (rf_i)
	ld	(rf_t), a
rf_bn:
	ld	a, (n_players)
	ld	b, a
	ld	a, (rf_i)
	cp	b
	jp	z, rf_aim
	inc	a
	jp	rf_b
rf_aim:
	ld	hl, (rf_p)
	ld	de, PL_AI_TARGET
	add	hl, de
	ld	a, (rf_t)
	ld	(hl), a
	call	dt_ptr
	ld	(rf_tp), hl
	call	rf_delta
	; dx = (t.x − p.x) или 1; dy = (p.y − t.y + 4) или 1
	ld	hl, (tr_ex)
	call	lb_nz1
	ld	(aib_dx), hl
	ld	hl, (tr_ey)
	call	lb_neg
	ld	de, 4
	add	hl, de
	call	lb_nz1
	ld	(aib_dy), hl
	ld	hl, (rf_s)
	ld	(aib_sc), hl
	call	ai_big_weapon
	; мощность 1000, угол = |atan(dy / dx)|
	ld	hl, 1000
	ld	(rf_pw), hl
	ld	hl, 0
	ld	(fx_a), hl
	ld	(fx_b), hl
	ld	hl, (aib_dy)
	ld	(fx_a + 2), hl
	ld	hl, (aib_dx)
	ld	(fx_b + 2), hl
	call	fx_div
	call	fx_atan
	or	a
	jp	p, rf_an
	cpl
	inc	a
rf_an:
	ld	(rf_ang), a
	; цель ниже ствола (dy < 0): навесом
	ld	a, (aib_dy + 1)
	or	a
	jp	p, rf_st
	ld	a, 1
	ld	(aib_w), a
	ld	a, (ap_rebound)
	or	a
	jp	z, rf_lob
	ld	de, 70
	call	random
	ld	a, l
	add	a, 10
	ld	(rf_ang), a
	jp	rf_st
rf_lob:
	ld	de, 100
	call	random
	ld	de, 200
	add	hl, de
	ld	(rf_pw), hl
	ld	a, 45
	ld	(rf_ang), a
rf_st:
	ld	hl, (rf_p)
	ld	de, PL_AI_PLAN
	add	hl, de
	ld	(hl), 1
	inc	hl
	ld	a, (rf_pw)
	ld	(hl), a
	inc	hl
	ld	a, (rf_pw + 1)
	ld	(hl), a
	inc	hl
	ld	a, (rf_ang)
	ld	(hl), a
	inc	hl
	ld	a, (rf_t)		; направление: цель слева — −1
	ld	b, a
	ld	a, (rf_place)
	ld	c, a
	ld	a, b
	cp	c
	ld	a, 0xFF
	jp	c, rf_fc
	ld	a, 1
rf_fc:
	ld	(hl), a
	inc	hl
	ld	a, (aib_w)
	ld	(hl), a
	ret

; tr_ex = t.x − p.x, tr_ey = t.y − p.y (rf_tp, rf_p)
rf_delta:
	ld	hl, (rf_tp)
	ld	e, (hl)
	inc	hl
	ld	c, (hl)
	ld	hl, (rf_p)
	ld	a, e
	sub	(hl)
	ld	e, a
	sbc	a, a
	ld	d, a
	inc	hl
	ld	a, c
	sub	(hl)
	ld	l, a
	sbc	a, a
	ld	h, a
	ld	(tr_ey), hl
	ex	de, hl
	ld	(tr_ex), hl
	ret
; HL = адрес очков игрока A (1..4)
rf_slot:
	add	a, a
	ld	e, a
	ld	d, 0
	ld	hl, rf_score - 2
	add	hl, de
	ret
; ZF = 0, если DE > 0 (слово со знаком)
rf_pos:
	ld	a, d
	or	a
	jp	m, rf_p0
	or	e
	ret
rf_p0:
	xor	a
	ret

; DE = запас оружия A у игрока aib_p
aib_ammo:
	add	a, a
	add	a, PL_AMMO
	ld	e, a
	ld	d, 0
	ld	hl, (aib_p)
	add	hl, de
	ld	e, (hl)
	inc	hl
	ld	d, (hl)
	ret
ai_big_weapon:
	; очки > 990: чем дальше цель, тем крупнее оружие (если есть запас)
	ld	hl, (aib_sc)
	ld	de, 991
	call	fl_scmp
	cp	0xFF
	jp	z, aib_las
	ld	hl, 0
	ld	(fx_a), hl
	ld	(fx_b), hl
	ld	hl, (aib_dx)
	ld	(fx_a + 2), hl
	ld	hl, (aib_dy)
	ld	(fx_b + 2), hl
	call	fx_hypot
	ld	hl, aib_tab
aib_l:
	ld	a, (hl)
	or	a
	ret	z			; очки > 990 — лазер не берётся
	ld	(aib_cur), a
	inc	hl
	ld	c, (hl)			; радиус
	inc	hl
	ld	(aib_ptr), hl
	; dist > r: целая часть больше, либо равна и есть дробь
	ld	a, (fx_a + 3)
	or	a
	jp	nz, aib_far
	ld	a, (fx_a + 2)
	cp	c
	jp	c, aib_n
	jp	nz, aib_far
	ld	hl, (fx_a)
	ld	a, h
	or	l
	jp	z, aib_n
aib_far:
	ld	a, (aib_cur)
	call	aib_ammo
	call	rf_pos
	jp	z, aib_n
	ld	a, (aib_cur)
	ld	(aib_w), a
aib_n:
	ld	hl, (aib_ptr)
	jp	aib_l
aib_las:
	; очки <= 990 и энергии лазера больше 100 — лазер
	ld	a, 5
	call	aib_ammo
	ld	hl, 100
	call	fl_scmp			; 100 ? запас
	cp	0xFF
	ret	nz
	ld	a, 5
	ld	(aib_w), a
	ret
aib_tab:
	db	2, 15, 3, 30, 4, 60, 0
airifle_end:

tr_x0:		dw	0
tr_y0:		dw	0
tr_ex:		dw	0
tr_ey:		dw	0
tr_mode:	db	0
tr_cnt:		dw	0
tr_n:		dw	0
tr_x:		db	0
tr_dist:	ds	4
tr_sx:		ds	4
tr_sy:		ds	4
tr_ax:		ds	4
tr_ay:		ds	4
rf_place:	db	0
rf_i:		db	0
rf_t:		db	0
rf_ang:		db	0
rf_p:		dw	0
rf_tp:		dw	0
rf_s:		dw	0
rf_tmp:		dw	0
rf_pw:		dw	0
rf_score:	ds	8
aib_p:		dw	0
aib_dx:		dw	0
aib_dy:		dw	0
aib_sc:		dw	0
aib_ptr:	dw	0
aib_w:		db	0
aib_cur:	db	0
