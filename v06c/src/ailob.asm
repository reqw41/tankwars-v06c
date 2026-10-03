; Планировщик Lobber — planLobber() эталона web/tankwars.js (PROFILE_V06C).
;   plan_lobber: вход A = место игрока 1..n. План — в поля PL_AI_* записи; история — PL_AI_S1 (последний выстрел:
;   мощность, x) и PL_AI_S2 (предпоследний), их пишет record_shot (aiplan.asm).
; Поправка мощности: adj = trunc(miss · (dp / dx)), dp / dx — Q16.16 с округлением (fx_div), произведение — 48 бит,
; усечение к нулю; дальше adj mod 32767 со знаком делимого.

plan_lobber:
	ld	(lb_place), a
	call	dt_ptr
	ld	(lb_p), hl
	; оружие: запас[1] >= 1 ? 1 : 11
	ld	a, 1
	call	lb_have
	ld	a, 1
	jp	nz, lb_w0
	ld	a, 11
lb_w0:
	ld	(lb_w), a
	; направление плана: не ±1 -> 1
	ld	hl, (lb_p)
	ld	de, PL_AI_FACING
	add	hl, de
	ld	a, (hl)
	cp	0xFF
	jp	z, lb_f0
	ld	a, 1
lb_f0:
	ld	(lb_f), a
	ld	(lb_d), a
	ld	hl, (lb_p)
	ld	de, PL_AI_N
	add	hl, de
	ld	a, (hl)
	ld	(lb_n), a
	; Random < 0.5 берётся всегда; при n == 1 обход целей в другую сторону
	call	rnd_hi
	ld	a, h
	or	a
	jp	m, lb_d0
	ld	a, (lb_n)
	cp	1
	jp	nz, lb_d0
	ld	a, (lb_d)
	cpl
	inc	a
	ld	(lb_d), a
lb_d0:
	ld	a, (lb_place)
	ld	(lb_t), a
	ld	a, (lb_n)
	cp	3
	jp	nc, lb_near
	; n < 3: следующий живой по кругу в сторону d
lb_walk:
	ld	a, (lb_d)
	ld	b, a
	ld	a, (lb_t)
	add	a, b
	jp	z, lb_wlo		; стало 0 -> N
	ld	b, a
	ld	a, (n_players)
	cp	b
	ld	a, b
	jp	nc, lb_wok		; target <= N
	ld	a, 1
	jp	lb_wok
lb_wlo:
	ld	a, (n_players)
lb_wok:
	ld	(lb_t), a
	ld	b, a
	ld	a, (lb_place)
	cp	b
	jp	z, lb_walk
	ld	a, b
	call	lb_alive
	jp	z, lb_walk
	jp	lb_tgt
	; n >= 3: живой, ближайший к месту падения последнего выстрела
lb_near:
	ld	hl, 0x7FFF
	ld	(lb_best), hl
	ld	hl, (lb_p)
	ld	de, PL_AI_S1 + 2
	add	hl, de
	ld	e, (hl)
	inc	hl
	ld	d, (hl)
	ex	de, hl
	ld	(lb_sx), hl
	ld	a, 1
lb_nl:
	ld	(lb_k), a
	ld	b, a
	ld	a, (lb_place)
	cp	b
	jp	z, lb_nn
	ld	a, b
	call	dt_ptr
	ld	e, (hl)			; x игрока k
	ld	d, 0
	ld	hl, (lb_sx)
	call	lb_sub			; HL = sx - x
	call	lb_abs
	ld	(lb_m), hl
	ex	de, hl
	ld	hl, (lb_best)
	ex	de, hl
	call	fl_scmp			; |sx - x| ? best
	cp	0xFF
	jp	nz, lb_nn
	ld	a, (lb_k)
	call	lb_alive
	jp	z, lb_nn
	ld	a, (lb_k)
	ld	(lb_t), a
	ld	hl, (lb_m)
	ld	(lb_best), hl
lb_nn:
	ld	a, (n_players)
	ld	b, a
	ld	a, (lb_k)
	cp	b
	jp	z, lb_tgt
	inc	a
	jp	lb_nl
lb_tgt:
	ld	hl, (lb_p)
	ld	de, PL_AI_TARGET
	add	hl, de
	ld	a, (lb_t)
	ld	(hl), a
	; цель по другую сторону от прежнего направления — пристрелка заново (n = 1)
	ld	b, a			; B = target
	ld	a, (lb_place)
	cp	b
	jp	z, lb_side		; target == место: ни одно условие не выполняется
	ld	a, (lb_f)
	jp	c, lb_s_gt		; место < target
	cp	1			; target < место: сброс при направлении 1
	jp	z, lb_reset
	jp	lb_side
lb_s_gt:
	cp	0xFF			; target > место: сброс при направлении -1
	jp	nz, lb_side
lb_reset:
	ld	a, 1
	ld	(lb_n), a
	ld	hl, (lb_p)
	ld	de, PL_AI_N
	add	hl, de
	ld	(hl), 1
lb_side:
	; направление = target > место ? 1 : -1
	ld	a, (lb_t)
	ld	b, a
	ld	a, (lb_place)
	cp	b
	ld	a, 1
	jp	c, lb_fs
	ld	a, 0xFF
lb_fs:
	ld	hl, (lb_p)
	ld	de, PL_AI_FACING
	add	hl, de
	ld	(hl), a
	ld	a, (lb_n)
	cp	1
	jp	z, lb_first
	cp	2
	jp	z, lb_second
	jp	lb_fit
lb_first:
	ld	hl, 100
	jp	lb_try
lb_second:
	ld	hl, 200
lb_try:
	ld	(lb_pw), hl
	ld	de, 100
	call	random
	ex	de, hl
	ld	hl, (lb_pw)
	add	hl, de
	ld	(lb_pw), hl
	ld	hl, (lb_p)
	ld	de, PL_AI_ANGLE
	add	hl, de
	ld	(hl), 75
	jp	lb_store

	; --- третий и следующие выстрелы: поправка мощности по двум последним ---
lb_fit:
	ld	hl, (lb_p)
	ld	de, PL_AI_S1
	add	hl, de
	ld	de, lb_s
	ld	b, 8
lb_cp:
	ld	a, (hl)
	ld	(de), a
	inc	hl
	inc	de
	dec	b
	jp	nz, lb_cp		; lb_s: sj.power, sj.x, si.power, si.x
	; dx = (sj.x - si.x) или 1
	ld	hl, (lb_s + 6)
	ex	de, hl
	ld	hl, (lb_s + 2)
	call	lb_sub
	call	lb_nz1
	ld	(lb_dx), hl
	; dp = (sj.power - si.power) или 1
	ld	hl, (lb_s + 4)
	ex	de, hl
	ld	hl, (lb_s)
	call	lb_sub
	call	lb_nz1
	ld	(lb_dp), hl
	; miss = x цели - si.x
	ld	a, (lb_t)
	call	dt_ptr
	ld	l, (hl)
	ld	h, 0
	ex	de, hl
	ld	hl, (lb_s + 6)
	ex	de, hl
	call	lb_sub
	ld	(lb_miss), hl
	; ratio = dp / dx (Q16.16)
	ld	hl, 0
	ld	(fx_a), hl
	ld	(fx_b), hl
	ld	hl, (lb_dp)
	ld	(fx_a + 2), hl
	ld	hl, (lb_dx)
	ld	(fx_b + 2), hl
	call	fx_div
	call	fx_abs_a		; fx_a = |ratio|, fx_sg = знак
	ld	a, (fx_sg)
	ld	(lb_sg), a
	; |miss| -> fx_b, знак — в lb_sg
	ld	hl, (lb_miss)
	ld	a, h
	or	a
	jp	p, lb_mp
	ld	a, (lb_sg)
	xor	1
	ld	(lb_sg), a
lb_mp:
	call	lb_abs
	ld	(lb_m), hl		; |miss|
	ld	(fx_b), hl
	ld	hl, 0
	ld	(fx_b + 2), hl
	call	fx_mulu			; fx_w = |miss| · |ratio|, 48 бит
	; t = fx_w >> 16 (32 бита); t mod 32767
	ld	hl, (fx_w + 2)
	ld	(fx_w), hl
	ld	hl, (fx_w + 4)
	ld	(fx_w + 2), hl
	ld	hl, 0
	ld	(fx_w + 4), hl
	ld	(fx_w + 6), hl
	ld	(fx_d + 2), hl
	ld	hl, 0x7FFF
	ld	(fx_d), hl
	call	fx_divu
	ld	hl, (fx_rm)
	ld	a, (lb_sg)
	or	a
	call	nz, lb_neg
	; мощность = si.power + adj (16 бит); отрицательная -> -мощность·2 (16 бит)
	ex	de, hl
	ld	hl, (lb_s + 4)
	add	hl, de
	ld	a, h
	or	a
	jp	p, lb_pp
	call	lb_neg
	add	hl, hl
lb_pp:
	ld	(lb_pw), hl
	; оружие по промаху: > 5 — 2, > 15 — 3, > 30 — 4
	ld	hl, (lb_m)
	ld	de, 6
	call	lb_ge
	jp	c, lb_wn
	ld	a, 2
	ld	(lb_w), a
	ld	hl, (lb_m)
	ld	de, 16
	call	lb_ge
	jp	c, lb_wn
	ld	a, 3
	ld	(lb_w), a
	ld	hl, (lb_m)
	ld	de, 31
	call	lb_ge
	jp	c, lb_wn
	ld	a, 4
	ld	(lb_w), a
lb_wn:
	; нет запаса — оружие слабее: 4 -> 3 -> 2 -> 1 -> 11 -> 0
	ld	a, (lb_w)
	or	a
	jp	z, lb_store
	call	lb_have
	jp	nz, lb_store
	ld	a, (lb_w)
	cp	11
	jp	z, lb_w11
	dec	a
	jp	nz, lb_wset
	ld	a, 11			; 1 -> 11
	jp	lb_wset
lb_w11:
	xor	a			; 11 -> 0
lb_wset:
	ld	(lb_w), a
	jp	lb_wn

lb_store:
	ld	hl, (lb_p)
	ld	de, PL_AI_PLAN
	add	hl, de
	ld	(hl), 1
	inc	hl
	ld	a, (lb_pw)
	ld	(hl), a
	inc	hl
	ld	a, (lb_pw + 1)
	ld	(hl), a
	ld	hl, (lb_p)
	ld	de, PL_AI_WEAPON
	add	hl, de
	ld	a, (lb_w)
	ld	(hl), a
	ret

; ZF = 0, если у игрока lb_p запас оружия A >= 1 (слово со знаком)
lb_have:
	add	a, a
	add	a, PL_AMMO
	ld	e, a
	ld	d, 0
	ld	hl, (lb_p)
	add	hl, de
	ld	e, (hl)
	inc	hl
	ld	a, (hl)
	or	a
	jp	m, lb_h0
	or	e
	ret
lb_h0:
	xor	a
	ret
; ZF = 0, если игрок на месте A жив
lb_alive:
	call	dt_ptr
	ld	de, PL_ALIVE
	add	hl, de
	ld	a, (hl)
	or	a
	ret
; HL = HL - DE
lb_sub:
	ld	a, l
	sub	e
	ld	l, a
	ld	a, h
	sbc	a, d
	ld	h, a
	ret
; HL = |HL|
lb_abs:
	ld	a, h
	or	a
	ret	p
; HL = -HL
lb_neg:
	ld	a, l
	cpl
	ld	l, a
	ld	a, h
	cpl
	ld	h, a
	inc	hl
	ret
; HL = 0 -> 1
lb_nz1:
	ld	a, h
	or	l
	ret	nz
	inc	hl
	ret
; CF = 1, если HL < DE (беззнаковые)
lb_ge:
	ld	a, l
	sub	e
	ld	a, h
	sbc	a, d
	ret
ailob_end:

lb_place:	db	0
lb_p:		dw	0
lb_w:		db	0
lb_f:		db	0
lb_d:		db	0
lb_n:		db	0
lb_t:		db	0
lb_k:		db	0
lb_sg:		db	0
lb_best:	dw	0
lb_sx:		dw	0
lb_m:		dw	0
lb_pw:		dw	0
lb_dx:		dw	0
lb_dp:		dw	0
lb_miss:	dw	0
lb_s:		ds	8
