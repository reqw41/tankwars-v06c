; Планировщики компьютерных игроков, простая часть — planStupid(), planBirdy(), recordShot() эталона web/tankwars.js.
;   plan_stupid: вход A = место игрока 1..n, ap_rebound (0/1 — стены отражают). План — в поля PL_AI_* записи.
;   plan_birdy:  вход A = место игрока.
;   record_shot: вход A = место игрока, fl_x (4 байта Q16.16, flight.asm) — где кончился выстрел.
; Порядок и число вызовов random — точно как в эталоне: Random(3) в цикле, Random(90), Random(5000),
; и только при ap_rebound = 0 ещё Random(250). random, dt_ptr и fl_scmp портят DE — всё держу в ячейках ap_*.

plan_stupid:
	ld	(ap_place), a
	call	dt_ptr		; HL = запись игрока (портит DE)
	ld	(ap_pp), hl
	; 1. направление: r = Random(3), повторять пока r == 1; r = 0 -> 0xFF, r = 2 -> 1
ap_s_f:
	ld	de, 3
	call	random
	ld	a, l
	cp	1
	jp	z, ap_s_f
	or	a
	jp	nz, ap_s_f1
	ld	a, 0xFF
	jp	ap_s_fwc
ap_s_f1:
	ld	a, 1
ap_s_fwc:
	ld	e, PL_AI_FACING
	call	ap_wb
	; 2. firstWeapon: оружие = 11; для w = 1..4: если запас[w] > 0 (со знаком) — оружие = w
	ld	a, 11
	ld	(ap_wpn), a
	ld	a, 1
	ld	(ap_w), a
ap_s_w:
	ld	a, (ap_w)
	ld	e, a
	ld	d, 0
	ld	hl, (ap_pp)
	add	hl, de
	add	hl, de
	ld	de, PL_AMMO
	add	hl, de
	ld	e, (hl)
	inc	hl
	ld	d, (hl)		; DE = запас[w]
	; DE >= 1 ? (DE - 1 >= 0 со знаком)
	ld	a, e
	sub	1
	ld	a, d
	sbc	a, 0
	or	a
	jp	p, ap_s_wh
ap_s_wn:
	ld	a, (ap_w)
	inc	a
	ld	(ap_w), a
	cp	5
	jp	c, ap_s_w
	jp	ap_s_we
ap_s_wh:
	ld	a, (ap_w)
	ld	(ap_wpn), a	; оружие = w, но цикл продолжается: позже w перебивает
	jp	ap_s_wn
ap_s_we:
	ld	a, (ap_wpn)
	ld	e, PL_AI_WEAPON
	call	ap_wb
	; 3. план.угол = Random(90)
	ld	de, 90
	call	random
	ld	a, l
	ld	e, PL_AI_ANGLE
	call	ap_wb
	; 4. мощность = Random(5000) + 20
	ld	de, 5000
	call	random
	ld	de, 20
	add	hl, de
	ld	(ap_power), hl
	; 5. если стены НЕ отражают: направление по месту, мощность = Random(250) + 50
	ld	a, (ap_rebound)
	or	a
	jp	nz, ap_s_men
	; план.направление = (n_players / 2 < место) ? 0xFF : 1 (деление нацело)
	ld	a, (n_players)
	and	a
	rra			; A = n / 2 (n <= 4, старший бит нулевой)
	ld	e, a
	ld	a, (ap_place)
	cp	e
	jp	c, ap_s_fpos	; место < n/2 -> 1
	jp	z, ap_s_fpos	; равно -> 1
	ld	a, 0xFF		; место > n/2 -> 0xFF
	jp	ap_s_fw2
ap_s_fpos:
	ld	a, 1
ap_s_fw2:
	ld	e, PL_AI_FACING
	call	ap_wb
	ld	de, 250
	call	random
	ld	de, 50
	add	hl, de
	ld	(ap_power), hl
	; 6. если 10*men < мощность (со знаком): мощность = 10*men (как ac_power: десять сложений)
ap_s_men:
	ld	hl, (ap_pp)
	ld	de, PL_MEN
	add	hl, de
	ld	a, (hl)
	ld	e, a
	inc	hl
	ld	d, (hl)		; DE = men
	ld	hl, 0
	ld	c, 10
ap_s_m:
	add	hl, de		; add hl,de флаги не трогает
	dec	c
	jp	nz, ap_s_m
	ld	a, (ap_power)
	ld	e, a
	ld	a, (ap_power + 1)
	ld	d, a		; DE = мощность
	call	fl_scmp		; HL = 10*men против DE = мощность
	cp	0xFF
	jp	nz, ap_s_st
	ld	(ap_power), hl
	; 7. план.мощность = мощность; план готов
ap_s_st:
	ld	hl, (ap_power)
	ld	e, PL_AI_POWER
	call	ap_ww
	ld	a, 1
	ld	e, PL_AI_PLAN
	call	ap_wb
	ret

; plan_birdy: вход A = место. Случайные числа не берутся.
plan_birdy:
	ld	(ap_place), a
	call	dt_ptr
	ld	(ap_pp), hl
	ld	a, 1
	ld	e, PL_AI_WEAPON
	call	ap_wb
	ld	a, 1
	ld	e, PL_AI_FACING
	call	ap_wb
	ld	a, 90
	ld	e, PL_AI_ANGLE
	call	ap_wb
	ld	hl, 300
	ld	(ap_power), hl
	; если 10*men < 300 (со знаком): мощность = 10*men
	ld	hl, (ap_pp)
	ld	de, PL_MEN
	add	hl, de
	ld	a, (hl)
	ld	e, a
	inc	hl
	ld	d, (hl)		; DE = men
	ld	hl, 0
	ld	c, 10
ap_b_m:
	add	hl, de
	dec	c
	jp	nz, ap_b_m
	ld	a, (ap_power)
	ld	e, a
	ld	a, (ap_power + 1)
	ld	d, a		; DE = мощность
	call	fl_scmp
	cp	0xFF
	jp	nz, ap_b_st
	ld	(ap_power), hl
ap_b_st:
	ld	hl, (ap_power)
	ld	e, PL_AI_POWER
	call	ap_ww
	ld	a, 1
	ld	e, PL_AI_PLAN
	call	ap_wb
	ret

; record_shot: вход A = место; X = целая часть fl_x с усечением к нулю; S2 := старый S1; S1 := (PL_POWER, X).
record_shot:
	ld	(ap_place), a
	call	dt_ptr
	ld	(ap_pp), hl
	ld	hl, fl_x
	ld	a, (hl)
	inc	hl
	or	(hl)		; дробное слово fl_x (младшие 2 байта) равно нулю?
	ld	(ap_tmp), a
	ld	hl, (fl_x + 2)	; X = целая часть, слово со знаком
	ld	a, h
	or	a
	jp	p, ap_r_1	; X >= 0 — усечение не нужно
	ld	a, (ap_tmp)
	or	a
	jp	z, ap_r_1	; X < 0 и дробь нулевая — X уже целое
	inc	hl		; усечение к нулю: X + 1
ap_r_1:
	ld	(ap_x), hl
	; копировать 4 байта S1 в S2
	ld	e, PL_AI_S1
	call	ap_rd4
	ld	e, PL_AI_S2
	call	ap_wr4
	; S1 := мощность = PL_POWER, x = X
	ld	hl, (ap_pp)
	ld	de, PL_POWER
	add	hl, de
	ld	a, (hl)
	ld	(ap_v), a
	inc	hl
	ld	a, (hl)
	ld	(ap_v + 1), a
	ld	hl, (ap_x)
	ld	a, l
	ld	(ap_v + 2), a
	ld	a, h
	ld	(ap_v + 3), a
	ld	e, PL_AI_S1
	call	ap_wr4
	ret

; --- вспомогательные ---

; записать A в байт записи ap_pp со смещением E (D игнорируется)
ap_wb:
	push	af
	ld	d, 0
	ld	hl, (ap_pp)
	add	hl, de
	pop	af
	ld	(hl), a
	ret

; записать HL (слово) в запись ap_pp со смещением E (D игнорируется)
ap_ww:
	push	hl
	ld	d, 0
	ld	hl, (ap_pp)
	add	hl, de
	pop	de
	ld	(hl), e
	inc	hl
	ld	(hl), d
	ret

; прочитать 4 байта записи ap_pp со смещения E в ap_v (D игнорируется)
ap_rd4:
	ld	d, 0
	ld	hl, (ap_pp)
	add	hl, de
	ld	a, (hl)
	ld	(ap_v), a
	inc	hl
	ld	a, (hl)
	ld	(ap_v + 1), a
	inc	hl
	ld	a, (hl)
	ld	(ap_v + 2), a
	inc	hl
	ld	a, (hl)
	ld	(ap_v + 3), a
	ret

; записать ap_v (4 байта) в запись ap_pp со смещения E (D игнорируется)
ap_wr4:
	ld	d, 0
	ld	hl, (ap_pp)
	add	hl, de
	ld	a, (ap_v)
	ld	(hl), a
	inc	hl
	ld	a, (ap_v + 1)
	ld	(hl), a
	inc	hl
	ld	a, (ap_v + 2)
	ld	(hl), a
	inc	hl
	ld	a, (ap_v + 3)
	ld	(hl), a
	ret

aiplan_end:

ap_rebound:	db	0
ap_place:	db	0
ap_tmp:		db	0
ap_w:		db	0
ap_wpn:		db	0
ap_pp:		dw	0
ap_power:	dw	0
ap_x:		dw	0
ap_v:		db	0,0,0,0
