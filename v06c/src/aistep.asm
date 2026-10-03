; Шаг компьютерного игрока и служебное для цикла раунда — chooseCode(), turnBegin(), nextAlive() эталона и
; определение конца раунда. Игрок — запись в players (player.inc).
;   choose_code:  вход A = место игрока; выход A = код действия 1..8 (план — в полях PL_AI_*).
;   turn_begin:   вход A = место игрока: счётчик истории PL_AI_N += 1.
;   next_alive:   вход A = текущее место (0..n); выход A = следующее живое место по кругу.
;   round_winner: выход CF = 1, если раунд окончен (живых не больше одного); тогда A = место победителя или 0.
; Стиль — action.asm. Все подпрограммы портят AF, BC, DE, HL: значения держу в ячейках после aistep_end.

choose_code:
	ld	(ai_place), a
	call	ai_find		; ai_pp = запись игрока
	; pw = PL_POWER, hp = PL_AI_POWER — дальше работаю с ячейками, в конце запишу обратно
	ld	hl, (ai_pp)
	ld	de, PL_POWER
	add	hl, de
	ld	a, (hl)
	ld	(ai_pw), a
	inc	hl
	ld	a, (hl)
	ld	(ai_pw + 1), a
	ld	hl, (ai_pp)
	ld	de, PL_AI_POWER
	add	hl, de
	ld	a, (hl)
	ld	(ai_hp), a
	inc	hl
	ld	a, (hl)
	ld	(ai_hp + 1), a
	; 1. пока запас[план.оружие] < 1: план.оружие -= 1, ушедший в минус -> 12
ai_c_w:
	ld	hl, (ai_pp)
	ld	de, PL_AI_WEAPON
	add	hl, de
	ld	a, (hl)
	call	ai_ammo		; HL = адрес слова запаса, A = план.оружие
	ld	e, (hl)
	inc	hl
	ld	d, (hl)		; DE = запас[план.оружие]
	; DE < 1 ? (DE - 1 < 0 со знаком)
	ld	a, e
	sub	1
	ld	a, d
	sbc	a, 0
	or	a
	jp	p, ai_c_1	; запас >= 1 — хватит
	ld	hl, (ai_pp)
	ld	de, PL_AI_WEAPON
	add	hl, de
	ld	a, (hl)
	dec	a
	or	a
	jp	p, ai_c_wok
	ld	a, 12		; стало -1 -> 12
ai_c_wok:
	ld	(hl), a
	jp	ai_c_w
	; 2. если 10*men < план.мощность: план.мощность = 10*men (со знаком)
ai_c_1:
	ld	hl, (ai_pp)
	ld	de, PL_MEN
	add	hl, de
	ld	a, (hl)
	ld	e, a
	inc	hl
	ld	d, (hl)		; DE = men
	ld	hl, 0
	ld	c, 10
ai_c_m:
	add	hl, de		; add hl,de флаги не трогает
	dec	c
	jp	nz, ai_c_m
	ld	(ai_m10), hl	; 10*men
	ld	a, (ai_hp)
	ld	e, a
	ld	a, (ai_hp + 1)
	ld	d, a		; HL = 10*men, DE = hp
	call	fl_scmp		; A = 0xFF если 10*men < hp
	cp	0xFF
	jp	nz, ai_c_2
	ld	hl, (ai_m10)
	ld	(ai_hp), hl
	; 3. если план.оружие == 5 и запас[5] < план.мощность: план.мощность = запас[5]
ai_c_2:
	ld	hl, (ai_pp)
	ld	de, PL_AI_WEAPON
	add	hl, de
	ld	a, (hl)
	cp	5
	jp	nz, ai_c_3
	ld	a, 5
	call	ai_ammo
	ld	e, (hl)
	inc	hl
	ld	d, (hl)		; DE = запас[5]
	ld	a, (ai_hp)
	ld	l, a
	ld	a, (ai_hp + 1)
	ld	h, a		; HL = hp
	call	fl_scmp		; HL=hp против DE=запас[5]
	cp	1		; hp > запас[5]
	jp	nz, ai_c_3
	ld	a, e
	ld	(ai_hp), a
	ld	a, d
	ld	(ai_hp + 1), a
	; 4. если план.мощность < 0: 0
ai_c_3:
	ld	a, (ai_hp + 1)
	or	a
	jp	p, ai_c_4
	ld	hl, 0
	ld	(ai_hp), hl
	; 5. код: каждая следующая проверка перебивает предыдущую
ai_c_4:
	ld	a, 5
	ld	(ai_code), a
	; t = 0 при facing = 1, t = -1 (0xFF) при facing = -1
	ld	hl, (ai_pp)
	ld	de, PL_FACING
	add	hl, de
	ld	a, (hl)
	cp	1
	ld	a, 0
	jp	z, ai_c_t
	ld	a, 0xFF
ai_c_t:
	ld	(ai_t), a
	; угол (байты 0..90, сравнение без знака)
	ld	hl, (ai_pp)
	ld	de, PL_ANGLE
	add	hl, de
	ld	a, (hl)		; angle
	ld	hl, (ai_pp)
	ld	de, PL_AI_ANGLE
	add	hl, de
	cp	(hl)
	jp	c, ai_c_angl
	jp	z, ai_c_pwcmp
	; angle > план.угол: код = t + 2 (2 при facing=1, 1 при facing=-1)
	ld	a, (ai_t)
	or	a
	jp	z, ai_c_ang2
	ld	a, 1
	jp	ai_c_angst
ai_c_ang2:
	ld	a, 2
	jp	ai_c_angst
ai_c_angl:
	; angle < план.угол: код = 1 - t (1 при facing=1, 2 при facing=-1)
	ld	a, (ai_t)
	or	a
	jp	z, ai_c_ang1
	ld	a, 2
	jp	ai_c_angst
ai_c_ang1:
	ld	a, 1
ai_c_angst:
	ld	(ai_code), a
	; мощность со знаком: pw > hp -> 3, pw < hp -> 4
ai_c_pwcmp:
	ld	hl, (ai_pw)
	ex	de, hl
	ld	a, (ai_hp)
	ld	l, a
	ld	a, (ai_hp + 1)
	ld	h, a
	ex	de, hl		; HL = pw, DE = hp
	call	fl_scmp
	cp	1
	jp	nz, ai_c_p4
	ld	a, 3
	ld	(ai_code), a
	jp	ai_c_f2
ai_c_p4:
	cp	0xFF
	jp	nz, ai_c_f2
	ld	a, 4
	ld	(ai_code), a
	; facing != план.направление -> 6
ai_c_f2:
	ld	hl, (ai_pp)
	ld	de, PL_FACING
	add	hl, de
	ld	a, (hl)
	ld	hl, (ai_pp)
	ld	de, PL_AI_FACING
	add	hl, de
	cp	(hl)
	jp	z, ai_c_w2
	ld	a, 6
	ld	(ai_code), a
	; weapon != план.оружие -> 8
ai_c_w2:
	ld	hl, (ai_pp)
	ld	de, PL_WEAPON
	add	hl, de
	ld	a, (hl)
	ld	hl, (ai_pp)
	ld	de, PL_AI_WEAPON
	add	hl, de
	cp	(hl)
	jp	z, ai_c_adj
	ld	a, 8
	ld	(ai_code), a
	; 6. подтяжка мощности: код 3 — минус 90/9, код 4 — плюс 90/9 (второй раз уже с новым power)
ai_c_adj:
	ld	a, (ai_code)
	cp	3
	jp	nz, ai_c_c4
	call	ai_diff		; HL = pw - hp
	ld	de, 100
	call	fl_scmp
	cp	0xFF		; diff >= 100 ?
	jp	z, ai_c_3b
	call	ai_pwdec90
ai_c_3b:
	call	ai_diff
	ld	de, 10
	call	fl_scmp
	cp	0xFF		; diff >= 10 ?
	jp	z, ai_c_fin
	call	ai_pwdec9
	jp	ai_c_fin
ai_c_c4:
	cp	4
	jp	nz, ai_c_fin
	call	ai_diff4	; HL = hp - pw
	ld	de, 100
	call	fl_scmp
	cp	0xFF
	jp	z, ai_c_4b
	call	ai_pwinc90
ai_c_4b:
	call	ai_diff4
	ld	de, 10
	call	fl_scmp
	cp	0xFF
	jp	z, ai_c_fin
	call	ai_pwinc9
	; 7. код 5: план больше не готов
ai_c_fin:
	ld	a, (ai_code)
	cp	5
	jp	nz, ai_c_st
	ld	hl, (ai_pp)
	ld	de, PL_AI_PLAN
	add	hl, de
	ld	(hl), 0
	; 8. запись изменённых power и план.мощность (план.оружие уже в записи)
ai_c_st:
	ld	hl, (ai_pp)
	ld	de, PL_POWER
	add	hl, de
	ld	a, (ai_pw)
	ld	(hl), a
	inc	hl
	ld	a, (ai_pw + 1)
	ld	(hl), a
	ld	hl, (ai_pp)
	ld	de, PL_AI_POWER
	add	hl, de
	ld	a, (ai_hp)
	ld	(hl), a
	inc	hl
	ld	a, (ai_hp + 1)
	ld	(hl), a
	ld	a, (ai_code)
	ret

; turn_begin: PL_AI_N += 1 (байт)
turn_begin:
	ld	(ai_place), a
	call	ai_find
	ld	hl, (ai_pp)
	ld	de, PL_AI_N
	add	hl, de
	ld	a, (hl)
	inc	a
	ld	(hl), a
	ret

; next_alive: cur = cur + 1 (cur > n -> 1), пока игрок на месте cur не жив
next_alive:
	ld	(ai_cur), a
ai_na_lp:
	ld	a, (ai_cur)
	inc	a
	ld	c, a
	ld	a, (n_players)
	cp	c
	ld	a, c
	jp	c, ai_na_w	; cur + 1 > n -> 1
	jp	ai_na_c
ai_na_w:
	ld	a, 1
ai_na_c:
	ld	(ai_cur), a
	call	ai_rec
	ld	de, PL_ALIVE
	add	hl, de
	ld	a, (hl)
	or	a
	jp	z, ai_na_lp
	ld	a, (ai_cur)
	ret

; round_winner: считать живых; CF = 1 если живых не больше одного, A = место единственного или 0
round_winner:
	xor	a
	ld	(ai_cnt), a
	ld	(ai_win), a
	ld	a, (n_players)
	ld	(ai_i), a
ai_rw_lp:
	ld	a, (ai_i)
	or	a
	jp	z, ai_rw_end
	call	ai_rec
	ld	de, PL_ALIVE
	add	hl, de
	ld	a, (hl)
	or	a
	jp	z, ai_rw_next
	ld	hl, ai_cnt
	ld	a, (hl)
	inc	a
	ld	(hl), a
	ld	a, (ai_i)
	ld	(ai_win), a
ai_rw_next:
	ld	hl, ai_i
	ld	a, (hl)
	dec	a
	ld	(hl), a
	jp	ai_rw_lp
ai_rw_end:
	ld	a, (ai_cnt)
	cp	2
	ld	a, (ai_win)	; ld флаги не трогает: при CF = 1 в A уже место победителя (или 0)
	ret	c
	or	a			; живых >= 2: ai_win != 0, CF = 0
	ret

; --- вспомогательные ---

; адрес записи игрока ai_place: players + (ai_place - 1) * PL_SIZE -> HL и ai_pp
ai_find:
	ld	hl, players
	ld	(ai_pp), hl
	ld	a, (ai_place)
	dec	a
	ret	z
	ld	c, a
ai_find_l:
	ld	de, PL_SIZE
	add	hl, de
	dec	c
	jp	nz, ai_find_l
	ld	(ai_pp), hl
	ret

; HL = адрес слова запаса оружия A у записи ai_pp; A сохраняет
ai_ammo:
	ld	e, a
	ld	d, 0
	ld	hl, (ai_pp)
	add	hl, de
	add	hl, de
	ld	de, PL_AMMO
	add	hl, de
	ret

; HL = запись игрока на месте A (A = 1..n)
ai_rec:
	ld	hl, players
	dec	a
	ret	z
	ld	e, a
	ld	d, 0
ai_rec_l:
	ld	bc, PL_SIZE
	add	hl, bc
	dec	de		; add hl,bc флаги не трогает
	ld	a, d
	or	e
	jp	nz, ai_rec_l
	ret

; HL = ai_pw - ai_hp (слово со знаком). Портит AF, DE
ai_diff:
	ld	a, (ai_pw)
	ld	l, a
	ld	a, (ai_pw + 1)
	ld	h, a
	ld	a, (ai_hp)
	ld	e, a
	ld	a, (ai_hp + 1)
	ld	d, a
	ld	a, l
	sub	e
	ld	l, a
	ld	a, h
	sbc	a, d
	ld	h, a
	ret

; HL = ai_hp - ai_pw (слово со знаком). Портит AF, DE
ai_diff4:
	ld	a, (ai_hp)
	ld	l, a
	ld	a, (ai_hp + 1)
	ld	h, a
	ld	a, (ai_pw)
	ld	e, a
	ld	a, (ai_pw + 1)
	ld	d, a
	ld	a, l
	sub	e
	ld	l, a
	ld	a, h
	sbc	a, d
	ld	h, a
	ret

; ai_pw -= 90 / -= 9 / += 90 / += 9 (число 0..1000, переполнения нет)
ai_pwdec90:
	ld	hl, (ai_pw)
	ld	de, 90
	sub	a
	ld	a, l
	sbc	a, e
	ld	l, a
	ld	a, h
	sbc	a, d
	ld	h, a
	ld	(ai_pw), hl
	ret
ai_pwdec9:
	ld	hl, (ai_pw)
	ld	de, 9
	sub	a
	ld	a, l
	sbc	a, e
	ld	l, a
	ld	a, h
	sbc	a, d
	ld	h, a
	ld	(ai_pw), hl
	ret
ai_pwinc90:
	ld	hl, (ai_pw)
	ld	de, 90
	add	hl, de
	ld	(ai_pw), hl
	ret
ai_pwinc9:
	ld	hl, (ai_pw)
	ld	de, 9
	add	hl, de
	ld	(ai_pw), hl
	ret

aistep_end:

ai_place:	db	0
ai_cur:		db	0
ai_i:		db	0
ai_cnt:		db	0
ai_win:		db	0
ai_code:	db	0
ai_t:		db	0
ai_pp:		dw	0
ai_pw:		dw	0
ai_hp:		dw	0
ai_m10:		dw	0
