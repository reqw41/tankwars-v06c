; Планировщик Twanger — planTwangerFix(), twangTraceFix() эталона web/tankwars.js (PROFILE_V06C): выстрел от потолка.
;   plan_twang: вход A = место игрока 1..n. План — в поля PL_AI_* записи. Экран не меняется.
; Трасса к цели k: от танка вверх до потолка (строка TW_CEIL) под углом deg, затем от потолка к цели; точка земли на
; первом отрезке стоит 3 очка, на втором — 1. Использует ai_trace, ai_big_weapon и ячейки rf_* (airifle.asm).

TW_CEIL		equ	24		; Y0 − 3

plan_twang:
	ld	(rf_place), a
	call	dt_ptr
	ld	(rf_p), hl
	ld	(aib_p), hl
	; очки целей: −1 (сам или мёртв), иначе 1000 − штраф трассы
	ld	a, 1
tw_k1:
	ld	(rf_i), a
	ld	hl, -1
	ld	(rf_s), hl
	ld	b, a
	ld	a, (rf_place)
	cp	b
	jp	z, tw_s1
	ld	a, b
	call	dt_ptr
	ld	de, PL_ALIVE
	add	hl, de
	ld	a, (hl)
	or	a
	jp	z, tw_s1
	ld	a, (rf_i)
	call	tw_trace
	ld	(rf_s), hl
tw_s1:
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
	jp	z, tw_rank
	inc	a
	jp	tw_k1
	; ранги: каждый новый максимум очков получает следующий номер, равный максимуму — текущий
tw_rank:
	ld	hl, 0
	ld	(rf_tmp), hl		; лучший
	ld	a, 1
	ld	(tw_cnt), a
	ld	a, 1
tw_r1:
	ld	(rf_i), a
	call	rf_slot
	ld	e, (hl)
	inc	hl
	ld	d, (hl)
	ex	de, hl
	ld	(rf_s), hl
	ex	de, hl
	ld	hl, (rf_tmp)
	ex	de, hl
	ld	hl, (rf_s)
	call	fl_scmp			; очки ? лучший
	ld	c, 0
	cp	0xFF
	jp	z, tw_r2
	or	a
	jp	z, tw_r3
	ld	hl, (rf_s)		; больше: новый максимум
	ld	(rf_tmp), hl
	ld	hl, tw_cnt
	inc	(hl)
tw_r3:
	ld	a, (tw_cnt)
	ld	c, a
tw_r2:
	ld	a, (rf_i)
	ld	e, a
	ld	d, 0
	ld	hl, tw_rk - 1
	add	hl, de
	ld	(hl), c
	ld	a, (n_players)
	ld	b, a
	ld	a, (rf_i)
	cp	b
	jp	z, tw_top
	inc	a
	jp	tw_r1
	; top = наибольший ранг
tw_top:
	ld	hl, tw_rk
	ld	a, (n_players)
	ld	b, a
	ld	c, 0
tw_t1:
	ld	a, (hl)
	cp	c
	jp	c, tw_t2
	ld	c, a
tw_t2:
	inc	hl
	dec	b
	jp	nz, tw_t1
	ld	a, c
	ld	(tw_cnt), a		; top
	; из целей высшего ранга — ближайшая: очки 1000 − trunc(расстояние)
	ld	hl, 0
	ld	(rf_tmp), hl
	xor	a
	ld	(rf_t), a
	ld	a, 1
tw_n1:
	ld	(rf_i), a
	ld	e, a
	ld	d, 0
	ld	hl, tw_rk - 1
	add	hl, de
	ld	a, (hl)
	or	a
	jp	z, tw_n2
	ld	b, a
	ld	a, (tw_cnt)
	cp	b
	jp	nz, tw_n2		; ранг ниже высшего
	ld	a, (rf_i)
	call	dt_ptr
	ld	(rf_tp), hl
	call	rf_delta
	ld	hl, 0
	ld	(fx_a), hl
	ld	(fx_b), hl
	ld	hl, (tr_ex)
	ld	(fx_a + 2), hl
	ld	hl, (tr_ey)
	ld	(fx_b + 2), hl
	call	fx_hypot
	ld	hl, (fx_a + 2)
	ex	de, hl
	ld	hl, 1000
	call	lb_sub
	ld	(rf_s), hl
	ex	de, hl
	ld	hl, (rf_tmp)
	ex	de, hl
	call	fl_scmp
	cp	1
	jp	nz, tw_n2
	ld	hl, (rf_s)
	ld	(rf_tmp), hl
	ld	a, (rf_i)
	ld	(rf_t), a
tw_n2:
	ld	a, (n_players)
	ld	b, a
	ld	a, (rf_i)
	cp	b
	jp	z, tw_aim
	inc	a
	jp	tw_n1
tw_aim:
	ld	hl, (rf_p)
	ld	de, PL_AI_TARGET
	add	hl, de
	ld	a, (rf_t)
	ld	(hl), a
	call	tw_trace		; очки цели заново; угол — tw_deg
	ld	(aib_sc), hl
	ld	de, 51
	call	random
	ld	de, 950
	add	hl, de
	ld	(rf_pw), hl
	ld	a, 1
	ld	(aib_w), a
	ld	hl, (tw_dx)
	ld	(aib_dx), hl
	ld	hl, (tw_dy)
	ld	(aib_dy), hl
	call	ai_big_weapon
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
	ld	a, (tw_deg)
	ld	(hl), a
	inc	hl
	ld	a, (tw_f)
	ld	(hl), a
	inc	hl
	ld	a, (aib_w)
	ld	(hl), a
	ret

; трасса к игроку A: выход HL = 1000 − 3·(земля на подъёме) − (земля на спуске); tw_deg, tw_f, tw_dx, tw_dy
tw_trace:
	ld	(tw_k), a
	call	dt_ptr
	ld	(rf_tp), hl
	call	rf_delta		; tr_ex = t.x − p.x, tr_ey = t.y − p.y
	ld	hl, (tr_ex)
	ld	(tw_dx), hl
	ld	hl, (tr_ey)
	call	lb_neg
	ld	(tw_dy), hl
	; направление: цель слева — −1
	ld	a, (rf_place)
	ld	b, a
	ld	a, (tw_k)
	cp	b
	ld	a, 0xFF
	jp	c, tw_f1
	ld	a, 1
tw_f1:
	ld	(tw_f), a
	; deg = |atan((p.y + t.y − 2·потолок) / dx)|, при dx == 0 — 0
	xor	a
	ld	(tw_deg), a
	ld	hl, (tw_dx)
	ld	a, h
	or	l
	jp	z, tw_ox0
	ld	(fx_b + 2), hl
	ld	hl, 0
	ld	(fx_a), hl
	ld	(fx_b), hl
	ld	hl, (rf_tp)
	inc	hl
	ld	e, (hl)
	ld	hl, (rf_p)
	inc	hl
	ld	l, (hl)
	ld	h, 0
	ld	d, 0
	add	hl, de
	ld	de, -2 * TW_CEIL
	add	hl, de
	ld	(fx_a + 2), hl
	call	fx_div
	call	fx_atan
	or	a
	jp	p, tw_d1
	cpl
	inc	a
tw_d1:
	ld	(tw_deg), a
tw_ox0:
	; up = p.y − потолок; ox = trunc(±up / tan(deg)), при deg == 0 — 0
	ld	hl, (rf_p)
	inc	hl
	ld	l, (hl)
	ld	h, 0
	ld	de, -TW_CEIL
	add	hl, de
	ld	(tw_up), hl
	ld	hl, 0
	ld	(tw_ox), hl
	ld	a, (tw_deg)
	or	a
	jp	z, tw_seg
	ld	l, a
	ld	h, 0
	call	fx_sincos
	ld	hl, fx_a
	ld	de, fx_sin
	ld	b, 4
	call	fx_copy
	ld	hl, fx_b
	ld	de, fx_cos
	ld	b, 4
	call	fx_copy
	call	fx_div			; tan
	ld	hl, fx_b
	ld	de, fx_a
	ld	b, 4
	call	fx_copy
	ld	hl, (fx_b)
	ld	a, h
	or	l
	ld	hl, (fx_b + 2)
	or	h
	or	l
	jp	z, tw_seg		; tan == 0
	ld	hl, 0
	ld	(fx_a), hl
	ld	hl, (tw_up)
	ld	(fx_a + 2), hl
	ld	a, (tw_f)
	or	a
	call	m, fx_neg_a
	call	fx_div
	call	fx_trunc
	ld	(tw_ox), hl
tw_seg:
	; подъём: от танка на (ox, −up)
	ld	hl, (rf_p)
	ld	e, (hl)
	inc	hl
	ld	l, (hl)
	ld	h, 0
	ld	(tr_y0), hl
	ld	l, e
	ld	(tr_x0), hl
	ld	hl, (tw_ox)
	ld	(tr_ex), hl
	ld	hl, (tw_up)
	ld	(tr_ey), hl
	ld	a, 2
	ld	(tr_mode), a
	call	ai_trace
	ld	d, h
	ld	e, l
	add	hl, hl
	add	hl, de
	ld	(tw_pen), hl		; 3 · земля
	; спуск: от (p.x + ox, потолок) к цели
	ld	hl, (rf_p)
	ld	e, (hl)
	ld	d, 0
	ld	hl, (tw_ox)
	add	hl, de
	ld	(tr_x0), hl
	ex	de, hl			; DE = lx
	ld	hl, (rf_tp)
	ld	c, (hl)
	inc	hl
	ld	l, (hl)
	ld	h, 0
	ld	a, l
	sub	TW_CEIL
	ld	l, a
	ld	a, h
	sbc	a, 0
	ld	h, a
	ld	(tr_ey), hl		; t.y − потолок
	ld	l, c
	ld	h, 0
	call	lb_sub			; t.x − lx
	ld	(tr_ex), hl
	ld	hl, TW_CEIL
	ld	(tr_y0), hl
	ld	a, 1
	ld	(tr_mode), a
	call	ai_trace
	ex	de, hl
	ld	hl, (tw_pen)
	add	hl, de
	ex	de, hl
	ld	hl, 1000
	jp	lb_sub
aitwang_end:

tw_k:		db	0
tw_f:		db	0
tw_deg:		db	0
tw_cnt:		db	0
tw_rk:		ds	4
tw_dx:		dw	0
tw_dy:		dw	0
tw_up:		dw	0
tw_ox:		dw	0
tw_pen:		dw	0
