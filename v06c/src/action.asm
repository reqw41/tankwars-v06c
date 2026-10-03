; Действия хода — applyCode(), autoSwitchWeapon(), needsWeaponSwitch() эталона web/tankwars.js (PROFILE_V06C).
; Игрок — запись в players с местом ac_place (1..n).
;   apply_code:   вход A = код действия 1..10, ac_place.
;   auto_switch:  вход ac_place. Если у текущего оружия запас ровно 0 — перейти к следующему с запасом > 0.
;   needs_switch: вход ac_place. Выход CF = 1, если оружие надо менять (запас <= 0, или лазер с запасом <= 100).
; Стиль — round.asm/place.asm. Все подпрограммы портят AF, BC, DE, HL: значения держу в ячейках после action_end.

apply_code:
	ld	(ac_code), a
	call	ac_find
	ld	a, (ac_code)
	cp	1
	jp	z, ac_angle
	cp	2
	jp	z, ac_angle
	cp	3
	jp	z, ac_power
	cp	4
	jp	z, ac_power
	cp	6
	jp	z, ac_turn
	cp	7
	jp	z, ac_sw78
	cp	8
	jp	z, ac_sw78
	cp	9
	jp	z, ac_herb
	cp	10
	jp	z, ac_vick
	ret

; код 1 или 2: угол. Стереть ствол со СТАРЫМ углом, затем новый угол 0..90 и, если надо, новый facing.
ac_angle:
	call	ac_erase
	ld	hl, (ac_pp)
	ld	de, PL_ANGLE
	add	hl, de
	ld	a, (ac_code)
	cp	1
	ld	a, (hl)
	jp	nz, ac_an_d
	inc	hl
	ld	c, (hl)	; facing 1 или 0xFF (-1)
	dec	hl
	add	a, c		; angle + facing (по модулю 256)
	jp	ac_an_fix
ac_an_d:
	inc	hl
	ld	c, (hl)
	dec	hl
	sub	c		; angle - facing
ac_an_fix:
	; A = угол со знаком (-1..91). Сначала знак, потом «> 90»: 0xFF без этого ушло бы в «> 90».
	or	a
	jp	p, ac_an_hi
	ld	c, a
	call	ac_flip		; facing = -facing
	ld	a, c
	cpl
	inc	a		; angle = -angle
	jp	ac_an_st
ac_an_hi:
	cp	91
	jp	c, ac_an_st	; 0..90 — как есть
	ld	c, a
	call	ac_flip		; facing = -facing
	ld	a, 180
	sub	c		; angle = 180 - angle
ac_an_st:
	ld	hl, (ac_pp)
	ld	de, PL_ANGLE
	add	hl, de
	ld	(hl), a
	call	ac_fill
	jp	draw_tank_barrel

; код 3 или 4: мощность power = power ± 1, потом три отсечки со знаком.
ac_power:
	ld	hl, (ac_pp)
	ld	de, PL_POWER
	add	hl, de
	ld	a, (hl)
	ld	e, a
	inc	hl
	ld	d, (hl)		; DE = power
	ld	a, (ac_code)
	cp	4
	jp	nz, ac_pw_d
	inc	de
	jp	ac_pw_lim
ac_pw_d:
	dec	de
ac_pw_lim:
	ld	b, d
	ld	c, e		; BC = power (DE и HL дальше свободны)
	; предел 10*men: DE = men, HL = 0, десять сложений (men бывает <= 0 — доп. отсечка ниже)
	ld	hl, (ac_pp)
	ld	de, PL_MEN
	add	hl, de
	ld	a, (hl)
	ld	e, a
	inc	hl
	ld	d, (hl)
	ld	hl, 0
	ld	a, 10
ac_pw_m:
	add	hl, de
	dec	a
	jp	nz, ac_pw_m
	; если power >= 10*men: power = 10*men (сравнение со знаком: BC - HL)
	ld	a, c
	sub	l
	ld	a, b
	sbc	a, h
	jp	p, ac_pw_setl
	jp	ac_pw_nz
ac_pw_setl:
	ld	b, h
	ld	c, l
ac_pw_nz:
	ld	a, b
	or	a
	jp	p, ac_pw_las
	ld	bc, 0		; power < 0 -> 0
ac_pw_las:
	; если weapon == 5 и power > запас[5]: power = запас[5]
	ld	hl, (ac_pp)
	ld	de, PL_WEAPON
	add	hl, de
	ld	a, (hl)
	cp	5
	jp	nz, ac_pw_st
	ld	a, 5
	call	ac_ammo		; BC (power) цел
	ld	e, (hl)
	inc	hl
	ld	d, (hl)		; DE = запас[5]
	ld	a, c
	sub	e
	ld	a, b
	sbc	a, d
	jp	p, ac_pw_sete	; power >= запас[5] -> power = запас[5]
	jp	ac_pw_st		; power < запас[5] — оставляем
ac_pw_sete:
	ld	b, d
	ld	c, e
ac_pw_st:
	ld	hl, (ac_pp)
	ld	de, PL_POWER
	add	hl, de
	ld	a, c
	ld	(hl), a
	inc	hl
	ld	a, b
	ld	(hl), a
	ret

; код 6: разворот — стереть старым facing, развернуть, нарисовать новым.
ac_turn:
	call	ac_erase
	call	ac_flip
	call	ac_fill
	jp	draw_tank_barrel

; код 7 или 8: смена оружия, не больше 40 шагов.
ac_sw78:
	ld	b, 40
ac_sw78_lp:
	ld	hl, (ac_pp)
	ld	de, PL_WEAPON
	add	hl, de
	ld	c, (hl)		; C = weapon
	ld	a, (ac_code)
	cp	8
	ld	a, c
	jp	nz, ac_sw78_m
	inc	a
	jp	ac_sw78_wr
ac_sw78_m:
	dec	a
ac_sw78_wr:
	; сначала знак (после dec 0 получился 0xFF -> 17), потом «> 17 -> 0»
	or	a
	jp	p, ac_sw78_hi
	ld	a, 17
	jp	ac_sw78_st
ac_sw78_hi:
	cp	18
	jp	c, ac_sw78_st
	ld	a, 0
ac_sw78_st:
	ld	(hl), a		; записать новый weapon
	ld	c, a			; C = новый weapon (проверка «== 5» — про него)
	call	ac_ammo		; A = weapon сохранён, HL = адрес запаса
	ld	e, (hl)
	inc	hl
	ld	d, (hl)		; DE = запас[weapon]
	; закончить, если запас > 0 и НЕ (weapon == 5 и запас < 100)
	ld	a, d
	or	a
	jp	m, ac_sw78_next
	ld	a, d
	or	e
	jp	z, ac_sw78_next
	ld	a, c
	cp	5
	jp	nz, ac_sw78_done
	ld	a, e
	sub	100
	ld	a, d
	sbc	a, 0
	jp	p, ac_sw78_done	; запас >= 100 — годится
ac_sw78_next:
	dec	b
	jp	nz, ac_sw78_lp
	ret
ac_sw78_done:
	ret

; код 9: если herb > 0 — guided XOR 1.
ac_herb:
	ld	hl, (ac_pp)
	ld	de, PL_HERB
	add	hl, de
	ld	e, (hl)
	inc	hl
	ld	d, (hl)
	ld	a, d
	or	e
	jp	z, ac_herb_r	; herb == 0 — ничего
	or	a
	ret	m			; herb < 0 — ничего
ac_herb_x:
	ld	hl, (ac_pp)
	ld	de, PL_GUIDED
	add	hl, de
	ld	a, (hl)
	xor	1
	ld	(hl), a
ac_herb_r:
	ret

; код 10: если vick > 0 — guided XOR 2.
ac_vick:
	ld	hl, (ac_pp)
	ld	de, PL_VICK
	add	hl, de
	ld	e, (hl)
	inc	hl
	ld	d, (hl)
	ld	a, d
	or	e
	jp	z, ac_vick_r
	or	a
	ret	m
ac_vick_x:
	ld	hl, (ac_pp)
	ld	de, PL_GUIDED
	add	hl, de
	ld	a, (hl)
	xor	2
	ld	(hl), a
ac_vick_r:
	ret

; auto_switch: если запас текущего оружия != 0 — выйти; иначе не больше 40 шагов к следующему с запасом > 0.
auto_switch:
	call	ac_find
	ld	hl, (ac_pp)
	ld	de, PL_WEAPON
	add	hl, de
	ld	a, (hl)
	call	ac_ammo
	ld	a, (hl)
	inc	hl
	or	(hl)
	ret	nz		; запас != 0
	ld	b, 40
ac_as_lp:
	ld	hl, (ac_pp)
	ld	de, PL_WEAPON
	add	hl, de
	ld	a, (hl)
	cp	17
	jp	c, ac_as_inc
	ld	a, 0
	jp	ac_as_st
ac_as_inc:
	inc	a
ac_as_st:
	ld	(hl), a
	call	ac_ammo
	ld	e, (hl)
	inc	hl
	ld	d, (hl)		; DE = запас[weapon]
	ld	a, d
	or	a
	jp	m, ac_as_next
	ld	a, d
	or	e
	jp	nz, ac_as_done
ac_as_next:
	dec	b
	jp	nz, ac_as_lp
	ret
ac_as_done:
	ret

; needs_switch: CF = 1, если запас[weapon] <= 0 или (weapon == 5 и запас[5] <= 100).
needs_switch:
	call	ac_find
	ld	hl, (ac_pp)
	ld	de, PL_WEAPON
	add	hl, de
	ld	a, (hl)
	call	ac_ammo
	ld	e, (hl)
	inc	hl
	ld	d, (hl)		; DE = запас[weapon]
	ld	a, d
	or	a
	jp	m, ac_nd_yes
	ld	a, d
	or	e
	jp	z, ac_nd_yes
	ld	hl, (ac_pp)
	ld	de, PL_WEAPON
	add	hl, de
	ld	a, (hl)
	cp	5
	jp	nz, ac_nd_no
	ld	a, 5
	call	ac_ammo
	ld	e, (hl)
	inc	hl
	ld	d, (hl)		; DE = запас[5]
	; DE <= 100?
	ld	a, e
	sub	100
	ld	a, d
	sbc	a, 0
	jp	m, ac_nd_yes
ac_nd_no:
	or	a
	ret
ac_nd_yes:
	scf
	ret

; --- вспомогательные ---

; адрес записи игрока: players + (ac_place - 1) * PL_SIZE; в HL и в ac_pp
ac_find:
	ld	hl, players
	ld	(ac_pp), hl
	ld	a, (ac_place)
	dec	a
	ret	z
	ld	c, a
ac_find_l:
	ld	de, PL_SIZE
	add	hl, de
	dec	c
	jp	nz, ac_find_l
	ld	(ac_pp), hl
	ret

; HL = адрес слова запаса оружия A у записи из ac_pp; A сохраняет
ac_ammo:
	ld	e, a
	ld	d, 0
	ld	hl, (ac_pp)
	add	hl, de
	add	hl, de
	ld	de, PL_AMMO
	add	hl, de
	ret

; заполнить ячейки tb_* значениями из записи (угол/направление — какие сейчас в записи)
ac_fill:
	ld	hl, (ac_pp)
	ld	a, (hl)		; PL_X
	ld	(tb_x), a
	inc	hl
	ld	a, (hl)		; PL_Y
	ld	(tb_y), a
	ld	a, (ac_place)
	ld	(tb_idx), a
	ld	a, 1
	ld	(tb_alive), a
	ld	hl, (ac_pp)
	ld	de, PL_ANGLE
	add	hl, de
	ld	a, (hl)
	ld	(tb_angle), a
	xor	a
	ld	(tb_angle + 1), a
	inc	hl
	ld	a, (hl)		; PL_FACING
	ld	(tb_facing), a
	ret

; стереть ствол: линия цвета 0 по текущим tb_* (вызывать ДО изменения угла/facing)
ac_erase:
	call	ac_fill
	call	tb_ends
	xor	a
	ld	(ln_c), a
	jp	line

; facing = -facing в записи (1 <-> 0xFF)
ac_flip:
	ld	hl, (ac_pp)
	ld	de, PL_FACING
	add	hl, de
	ld	a, (hl)
	ld	e, a
	ld	a, 0
	sub	e
	ld	(hl), a
	ret

action_end:

ac_place:	db	0
ac_code:	db	0
ac_pp:		dw	0
