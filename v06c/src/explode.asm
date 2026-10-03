; Обычный взрыв — explode() эталона web/tankwars.js (PROFILE_V06C): оружие 1, 2, 3, 4, 11; шар грязи 13..16 — dirtBall().
; Вход: ex_x, ex_y (Q16.16, точка остановки снаряда), ex_hit (цвет попадания), ex_shooter (место стрелка 1..n,
;       0 — «ничей» взрыв при гибели), ex_weapon; записи игроков — players, n_players.
; Что делает: огонь и воронка закрашенным кругом; прямое попадание в танк — 200; каждому живому игроку урон по
; расстоянию d до точки взрыва: если d <= 1.5r: + trunc(1.8r − d); если d < r: + 10 + 2·trunc(1.8r − d);
; если d < 0.7r: + 150. Урон снимается со щита, остаток — со здоровья, стрелку за остаток по 10 очков.

explode:
	ld	a, (ex_weapon)
	cp	13
	jp	c, ex_norm
	cp	17
	jp	nc, ex_norm
	; грязь 13..16 — dirtBall() эталона: круг земли того же радиуса, что у оружия 1..4, урона нет
	sub	13
	ld	e, a
	ld	d, 0
	ld	hl, ex_dirt
	add	hl, de
	ld	a, (hl)
	ld	(dk_r), a
	ld	hl, ex_x
	ld	de, -3
	call	ex_ctr
	ld	(dk_x), hl
	ld	hl, ex_y
	ld	de, -27
	call	ex_ctr
	ld	(dk_y), hl
	ld	a, 1
	ld	(dk_el), a
	ld	(dk_er), a
	ld	(dk_c), a
	jp	disc
ex_dirt:
	db	10, 15, 30, 60
ex_norm:
	ld	a, (ex_weapon)
	ld	hl, ex_rtab
	ld	c, 0
ex_find:
	ld	b, (hl)
	inc	hl
	cp	b
	jp	z, ex_found
	inc	hl
	inc	c
	ld	b, a
	ld	a, c
	cp	5
	ld	a, b
	jp	nz, ex_find
	ret				; не обычный взрыв
ex_found:
	ld	a, (hl)
	ld	(ex_r), a
	ld	l, c			; константы радиуса: 12 байт на радиус
	ld	h, 0
	add	hl, hl
	add	hl, hl
	ld	d, h
	ld	e, l
	add	hl, hl
	add	hl, de
	ld	de, ex_ktab
	add	hl, de
	ld	(ex_kp), hl
	; центр круга на экране: trunc(x − X0) + X0, trunc(y − Y0) + Y0
	ld	hl, ex_x
	ld	de, -3
	call	ex_ctr
	ld	(dk_x), hl
	ld	hl, ex_y
	ld	de, -27
	call	ex_ctr
	ld	(dk_y), hl
	ld	a, 1
	ld	(dk_el), a
	ld	(dk_er), a
	ld	a, (ex_r)
	ld	(dk_r), a
	ld	a, 3
	ld	(dk_c), a
	call	disc			; огонь
	xor	a
	ld	(dk_c), a
	call	disc			; воронка
	; прямое попадание
	ld	a, (ex_hit)
	cp	4
	jp	c, ex_all
	sub	3
	ld	(ex_vi), a
	call	ex_pptr
	ld	hl, 200
	ld	(ex_dmg), hl
	call	ex_apply
ex_all:
	ld	a, 1
ex_lp:
	ld	(ex_vi), a
	call	ex_pptr
	ld	a, PL_ALIVE
	call	ex_fld
	ld	a, (hl)
	or	a
	jp	z, ex_next
	; d = hypot(x − px, y − py)
	ld	hl, fx_a
	ld	de, ex_x
	ld	b, 4
	call	fx_copy
	ld	a, PL_X
	call	ex_fld
	ld	e, (hl)
	ld	hl, (fx_a + 2)
	call	ex_sube
	ld	(fx_a + 2), hl
	ld	hl, fx_b
	ld	de, ex_y
	ld	b, 4
	call	fx_copy
	ld	a, PL_Y
	call	ex_fld
	ld	e, (hl)
	ld	hl, (fx_b + 2)
	call	ex_sube
	ld	(fx_b + 2), hl
	call	fx_hypot
	ld	hl, ex_d
	ld	de, fx_a
	ld	b, 4
	call	fx_copy
	ld	hl, 0
	ld	(ex_dmg), hl
	; t = trunc(1.8r − d) — нужно в первых двух условиях
	ld	hl, (ex_kp)
	ld	de, 4
	add	hl, de
	ex	de, hl			; DE -> r18
	ld	hl, ex_t
	ld	b, 4
	call	fx_copy
	ld	hl, ex_t
	ld	de, ex_d
	ld	b, 4
	call	fx_subm			; ex_t = r18 − d (знак важен только при d <= 1.5r, там он >= 0)
	; условие 1: d <= 1.5r
	ld	hl, (ex_kp)
	call	ex_cmpd			; CF = 1, если константа < d
	jp	c, ex_c2
	ld	hl, (ex_t + 2)
	ld	(ex_dmg), hl
ex_c2:	; условие 2: d < r
	ld	hl, 0
	ld	(ex_c), hl
	ld	a, (ex_r)
	ld	l, a
	ld	h, 0
	ld	(ex_c + 2), hl
	ld	hl, ex_c
	call	ex_cmpd2		; CF = 1, если d < константа
	jp	nc, ex_c3
	ld	hl, (ex_t + 2)
	add	hl, hl
	ld	de, 10
	add	hl, de
	ex	de, hl
	ld	hl, (ex_dmg)
	add	hl, de
	ld	(ex_dmg), hl
ex_c3:	; условие 3: d < 0.7r
	ld	hl, (ex_kp)
	ld	de, 8
	add	hl, de
	call	ex_cmpd2
	jp	nc, ex_do
	ld	hl, (ex_dmg)
	ld	de, 150
	add	hl, de
	ld	(ex_dmg), hl
ex_do:
	call	ex_apply
ex_next:
	ld	a, (n_players)
	ld	b, a
	ld	a, (ex_vi)
	cp	b
	ret	z
	inc	a
	jp	ex_lp

; HL -> значение Q16.16, DE = −смещение поля: HL = trunc(v − смещение) + смещение (слово со знаком)
ex_ctr:
	push	de
	push	de
	ld	de, fx_a
	ex	de, hl
	ld	b, 4
	call	fx_copy
	pop	de
	ld	hl, (fx_a + 2)
	add	hl, de
	ld	(fx_a + 2), hl
	call	fx_trunc
	pop	de
	ld	a, e			; вернуть смещение: HL − DE
	cpl
	ld	e, a
	ld	a, d
	cpl
	ld	d, a
	inc	de
	add	hl, de
	ret
; HL = HL − E (E — байт без знака)
ex_sube:
	ld	a, l
	sub	e
	ld	l, a
	ret	nc
	dec	h
	ret
; ex_pp = адрес записи игрока с местом (ex_vi)
ex_pptr:
	ld	hl, players
	ld	de, PL_SIZE
	ld	a, (ex_vi)
ex_pp1:
	dec	a
	jp	z, ex_pp2
	add	hl, de
	jp	ex_pp1
ex_pp2:
	ld	(ex_pp), hl
	ret
; HL = ex_pp + A
ex_fld:
	ld	hl, (ex_pp)
	ld	e, a
	ld	d, 0
	add	hl, de
	ret
; CF = 1, если константа (HL -> 4 байта) < ex_d. Оба неотрицательные.
ex_cmpd:
	ex	de, hl
	ld	hl, ex_c
	ld	b, 4
	call	fx_copy
	ld	hl, ex_c
	ld	de, ex_d
	ld	b, 4
	jp	fx_subm			; константа − d: заём, если константа < d
; CF = 1, если ex_d < константа (HL -> 4 байта)
ex_cmpd2:
	push	hl
	ld	hl, ex_c2v
	ld	de, ex_d
	ld	b, 4
	call	fx_copy
	pop	de
	ld	hl, ex_c2v
	ld	b, 4
	jp	fx_subm			; d − константа: заём, если d < константа

; урон ex_dmg игроку ex_pp (место ex_vi)
ex_apply:
	ld	a, PL_SHIELD
	call	ex_fld
	ld	(ex_sp), hl
	ld	a, (ex_dmg)
	ld	c, a
	ld	a, (hl)
	sub	c
	ld	(hl), a
	inc	hl
	ld	a, (ex_dmg + 1)
	ld	c, a
	ld	a, (hl)
	sbc	a, c
	ld	(hl), a
	inc	hl
	ld	a, (hl)
	sbc	a, 0
	ld	(hl), a
	inc	hl
	ld	a, (hl)
	sbc	a, 0
	ld	(hl), a
	ret	p			; щит выдержал
	; neg = −щит (слово), щит = 0
	ld	hl, (ex_sp)
	ld	a, (hl)
	cpl
	ld	e, a
	inc	hl
	ld	a, (hl)
	cpl
	ld	d, a
	inc	de
	ex	de, hl
	ld	(ex_neg), hl
	ld	hl, (ex_sp)
	ld	b, 4
	call	fx_zero
	; men −= neg
	ld	a, PL_MEN
	call	ex_fld
	ld	a, (ex_neg)
	ld	c, a
	ld	a, (hl)
	sub	c
	ld	(hl), a
	inc	hl
	ld	a, (ex_neg + 1)
	ld	c, a
	ld	a, (hl)
	sbc	a, c
	ld	(hl), a
	; очки стрелку: + neg·10, если стрелок есть и это не сам пострадавший
	ld	a, (ex_shooter)
	or	a
	ret	z
	ld	b, a
	ld	a, (n_players)
	cp	b
	ret	c
	ld	a, (ex_vi)
	cp	b
	ret	z
	ld	hl, (ex_neg)		; neg·10 (до 16 бит: neg < 1000)
	add	hl, hl
	ld	d, h
	ld	e, l
	add	hl, hl
	add	hl, hl
	add	hl, de
	ex	de, hl			; DE = neg·10
	ld	hl, players + PL_SCORE
	ld	a, (ex_shooter)
ex_sc1:
	dec	a
	jp	z, ex_sc2
	ld	bc, PL_SIZE
	add	hl, bc
	jp	ex_sc1
ex_sc2:
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

; оружие -> радиус
ex_rtab:
	db	1, 10,  2, 15,  3, 30,  4, 60,  11, 2
; на радиус: 1.5r, 1.8r, 0.7r в Q16.16 (множители 98304, 117965, 45875 из web/fixmath.js)
ex_ktab:
	dd	10 * 98304, 10 * 117965, 10 * 45875
	dd	15 * 98304, 15 * 117965, 15 * 45875
	dd	30 * 98304, 30 * 117965, 30 * 45875
	dd	60 * 98304, 60 * 117965, 60 * 45875
	dd	2 * 98304, 2 * 117965, 2 * 45875
explode_end:

ex_x:		ds	4
ex_y:		ds	4
ex_hit:		db	0
ex_shooter:	db	0
ex_weapon:	db	0
ex_r:		db	0
ex_vi:		db	0
ex_kp:		dw	0
ex_pp:		dw	0
ex_sp:		dw	0
ex_dmg:		dw	0
ex_neg:		dw	0
ex_d:		ds	4
ex_t:		ds	4
ex_c:		ds	4
ex_c2v:		ds	4
