; Планировщик Windless Wit — planWitFix() эталона web/tankwars.js (PROFILE_V06C): выстрел без поправки на ветер.
;   plan_wit: вход A = место игрока 1..n. План — в поля PL_AI_* записи.
; Счёт: vx0 = ±r/50; tt = dx/vx0; vy0 = (dy − tt²/20)/tt; мощность = |trunc(hypot(vy0·50, vx0·50))|,
; угол = |atan(vy0·50 / vx0·50)|. Всё — Q16.16; tt² и деление на 20 идут в 64 битах.

plan_wit:
	ld	(wt_place), a
	call	dt_ptr
	ld	(wt_p), hl
	; цель: Random(n) + 1, пока не чужой живой
wt_pick:
	ld	a, (n_players)
	ld	e, a
	ld	d, 0
	call	random
	ld	a, l
	inc	a
	ld	(wt_t), a
	ld	b, a
	ld	a, (wt_place)
	cp	b
	jp	z, wt_pick
	ld	a, b
	call	dt_ptr
	ld	(wt_tp), hl
	ld	de, PL_ALIVE
	add	hl, de
	ld	a, (hl)
	or	a
	jp	z, wt_pick
	ld	hl, (wt_p)
	ld	de, PL_AI_TARGET
	add	hl, de
	ld	a, (wt_t)
	ld	(hl), a
	; dx = t.x − p.x, dy = t.y − p.y
	ld	hl, (wt_tp)
	ld	e, (hl)
	inc	hl
	ld	c, (hl)
	ld	hl, (wt_p)
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
	ld	h, a			; HL = dy, DE = dx
	or	a
	jp	p, wt_a1
	inc	hl			; dy < 0: + 4
	inc	hl
	inc	hl
	inc	hl
wt_a1:
	ld	(wt_dy), hl
	ex	de, hl
	ld	a, h
	or	a
	jp	m, wt_a3
	or	l
	jp	z, wt_a4
	dec	hl			; dx > 0: − 4
	dec	hl
	dec	hl
	dec	hl
	ld	a, h
	or	a
	jp	p, wt_a4
wt_a3:
	inc	hl			; dx < 0: + 4
	inc	hl
	inc	hl
	inc	hl
wt_a4:
	ld	(wt_dx), hl
	; vx0 = ±r / 50, r = Random(100) + 50
	ld	de, 100
	call	random
	ld	de, 50
	add	hl, de
	ld	(fx_a + 2), hl
	ld	hl, 0
	ld	(fx_a), hl
	ld	a, (wt_t)
	ld	b, a
	ld	a, (wt_place)
	cp	b
	call	nc, fx_neg_a		; цель слева — скорость отрицательная
	ld	de, 50
	call	fx_idiv
	ld	hl, wt_vx
	ld	de, fx_a
	ld	b, 4
	call	fx_copy
	; vy0 = 0, если dx == 0
	ld	hl, wt_vy
	ld	b, 4
	call	fx_zero
	ld	hl, (wt_dx)
	ld	a, h
	or	l
	jp	z, wt_v50
	; tt = dx / vx0
	ld	(fx_a + 2), hl
	ld	hl, 0
	ld	(fx_a), hl
	ld	hl, fx_b
	ld	de, wt_vx
	ld	b, 4
	call	fx_copy
	call	fx_div
	ld	hl, wt_tt
	ld	de, fx_a
	ld	b, 4
	call	fx_copy
	ld	hl, (fx_a)
	ld	a, h
	or	l
	ld	hl, (fx_a + 2)
	or	h
	or	l
	jp	z, wt_v50		; tt == 0
	; grav = (tt² + 10) / 20; tt² — Q16.16 с округлением из 64 бит
	call	fx_abs_a
	ld	hl, fx_b
	ld	de, fx_a
	ld	b, 4
	call	fx_copy
	call	fx_mulu
	ld	hl, fx_w + 1		; + 0x8000
	ld	a, (hl)
	add	a, 0x80
	ld	(hl), a
	jp	nc, wt_sq
wt_sqc:
	inc	hl
	inc	(hl)
	jp	z, wt_sqc
wt_sq:
	ld	hl, (fx_w + 2)		; >> 16
	ld	de, 10
	add	hl, de
	ld	(fx_w), hl
	ld	hl, (fx_w + 4)
	jp	nc, wt_sq2
	inc	hl
wt_sq2:
	ld	(fx_w + 2), hl
	ld	hl, 0
	ld	(fx_w + 4), hl
	ld	(fx_w + 6), hl
	ld	(fx_d + 2), hl
	ld	hl, 20
	ld	(fx_d), hl
	call	fx_divu			; fx_w = grav
	; vy0 = (dy − grav) / tt
	ld	hl, 0
	ld	(fx_a), hl
	ld	hl, (wt_dy)
	ld	(fx_a + 2), hl
	ld	hl, fx_a
	ld	de, fx_w
	ld	b, 4
	call	fx_subm
	ld	hl, fx_b
	ld	de, wt_tt
	ld	b, 4
	call	fx_copy
	call	fx_div
	ld	hl, wt_vy
	ld	de, fx_a
	ld	b, 4
	call	fx_copy
wt_v50:
	; vy50 = vy0 · 50, vx50 = vx0 · 50
	ld	hl, wt_vy
	call	wt_mul50
	ld	hl, wt_vx
	call	wt_mul50
	; мощность = |trunc(hypot(vy50, vx50))|
	ld	hl, fx_a
	ld	de, wt_vy
	ld	b, 4
	call	fx_copy
	ld	hl, fx_b
	ld	de, wt_vx
	ld	b, 4
	call	fx_copy
	call	fx_hypot
	call	fx_trunc
	ld	(wt_pw), hl
	; угол = |atan(vy50 / vx50)| (vx50 не ноль: r >= 50)
	ld	hl, fx_a
	ld	de, wt_vy
	ld	b, 4
	call	fx_copy
	ld	hl, fx_b
	ld	de, wt_vx
	ld	b, 4
	call	fx_copy
	call	fx_div
	call	fx_atan
	or	a
	jp	p, wt_an
	cpl
	inc	a
wt_an:
	ld	hl, (wt_p)
	ld	de, PL_AI_ANGLE
	add	hl, de
	ld	(hl), a
	inc	hl			; PL_AI_FACING = цель справа ? 1 : -1
	ld	a, (wt_t)
	ld	b, a
	ld	a, (wt_place)
	cp	b
	ld	a, 1
	jp	c, wt_fc
	ld	a, 0xFF
wt_fc:
	ld	(hl), a
	; мощность не больше 10·men (со знаком)
	ld	hl, (wt_pw)
	ex	de, hl
	ld	hl, (wt_p)
	call	ai_cap_power
	ld	hl, (wt_p)
	call	ai_first_weapon
	ld	hl, (wt_p)
	ld	de, PL_AI_PLAN
	add	hl, de
	ld	(hl), 1
	ret

; число Q16.16 по адресу HL умножить на 50 (на месте)
wt_mul50:
	ld	(wt_ptr), hl
	ex	de, hl
	ld	hl, fx_a
	ld	b, 4
	call	fx_copy
	call	fx_abs_a
	ld	hl, 50
	ld	(fx_b), hl
	ld	hl, 0
	ld	(fx_b + 2), hl
	ld	a, (fx_sg)
	push	af
	call	fx_mulu
	pop	af
	ld	(fx_sg), a
	ld	hl, fx_a
	ld	de, fx_w
	ld	b, 4
	call	fx_copy
	call	fx_sign
	ld	hl, (wt_ptr)
	ld	de, fx_a
	ld	b, 4
	jp	fx_copy

; --- общее для планировщиков ---
; ai_cap_power: HL = запись игрока, DE = мощность. PL_AI_POWER = min(мощность, 10·men) со знаком.
ai_cap_power:
	ld	(aic_p), hl
	ex	de, hl
	ld	(aic_pw), hl
	ex	de, hl
	ld	de, PL_MEN
	add	hl, de
	ld	e, (hl)
	inc	hl
	ld	d, (hl)
	ld	hl, 0
	ld	a, 10
aic_m:
	add	hl, de
	dec	a
	jp	nz, aic_m		; HL = 10·men
	ex	de, hl
	ld	hl, (aic_pw)
	ex	de, hl			; HL = 10·men, DE = мощность
	call	fl_scmp
	cp	0xFF
	jp	z, aic_st		; 10·men < мощность
	ld	hl, (aic_pw)
aic_st:
	ex	de, hl
	ld	hl, (aic_p)
	ld	bc, PL_AI_POWER
	add	hl, bc
	ld	(hl), e
	inc	hl
	ld	(hl), d
	ret
; ai_first_weapon: HL = запись игрока. PL_AI_WEAPON = последнее из оружий 1..4 с запасом > 0, иначе 11.
ai_first_weapon:
	ld	(aic_p), hl
	ld	de, PL_AMMO + 2
	add	hl, de
	ld	c, 11
	ld	b, 1
aif_l:
	ld	e, (hl)
	inc	hl
	ld	a, (hl)
	inc	hl
	or	a
	jp	m, aif_n
	or	e
	jp	z, aif_n
	ld	c, b
aif_n:
	inc	b
	ld	a, b
	cp	5
	jp	nz, aif_l
	ld	hl, (aic_p)
	ld	de, PL_AI_WEAPON
	add	hl, de
	ld	(hl), c
	ret
aiwit_end:

wt_place:	db	0
wt_t:		db	0
wt_p:		dw	0
wt_tp:		dw	0
wt_dx:		dw	0
wt_dy:		dw	0
wt_pw:		dw	0
wt_ptr:		dw	0
wt_vx:		ds	4
wt_vy:		ds	4
wt_tt:		ds	4
aic_p:		dw	0
aic_pw:		dw	0
