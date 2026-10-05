; Компьютерный игрок в цикле хода — computerStep(), plan(), aiType(), pickStrategy() эталона web/tankwars.js.
;   computer_step: вход A = место игрока, ap_rebound (стены отражают). Выход A = код действия.
;   pick_strategy: вход A = место игрока. PL_STRAT = Random(4) + 1 с отбором по типу игрока.
; Тип игрока — по первой букве русского имени (PL_NAME, коды CP866; имена — s_ainames в strings_game.inc):
; W — Windless Wit, T — Twanger, L — Lobber («LOB» и буква B) или Lob & Shoot.

computer_step:
	ld	(cs_place), a
	ld	(ac_place), a
	call	needs_switch
	ld	a, 8
	ret	c
	ld	a, (cs_place)
	call	dt_ptr
	ld	de, PL_AI_PLAN
	add	hl, de
	ld	a, (hl)
	or	a
	call	z, ai_plan
	ld	a, (cs_place)
	jp	choose_code

ai_plan:
	call	cs_type
	ld	c, a
	ld	a, (ap_rebound)
	ld	b, a
	ld	a, c
	cp	5			; Lob & Shoot: стены отражают — Rifleman, иначе Lobber
	jp	nz, aip_1
	ld	c, 3
	ld	a, b
	or	a
	jp	nz, aip_2
	ld	c, 4
	jp	aip_2
aip_1:
	cp	7			; Twanger без отражающих стен — Rifleman
	jp	nz, aip_2
	ld	a, b
	or	a
	jp	nz, aip_2
	ld	c, 3
aip_2:
	ld	a, c
	dec	a
	ld	hl, plan_stupid
	jp	z, aip_go
	dec	a
	ld	hl, plan_birdy
	jp	z, aip_go
	dec	a
	ld	hl, plan_rifle
	jp	z, aip_go
	dec	a
	ld	hl, plan_lobber
	jp	z, aip_go
	sub	2
	ld	hl, plan_wit
	jp	z, aip_go
	ld	hl, plan_twang
aip_go:
	ld	a, (cs_place)
	jp	(hl)

; A = тип игрока cs_place: 1 Mr. Stupid, 2 Birdy, 3 Rifleman, 4 Lobber, 5 Lob & Shoot, 6 Windless Wit, 7 Twanger, 0 — прочие
cs_type:
	ld	a, (cs_place)
	call	dt_ptr
	ld	de, PL_NAME
	add	hl, de
	ld	a, (hl)
	ld	b, 1
	cp	0x83			; Г — Г-Н ТУПИЦА
	jp	z, cst_r
	inc	b
	cp	0x81			; Б — БЕРДИ БОНКЕР
	jp	z, cst_r
	inc	b
	cp	0x91			; С — СТРЕЛОК
	jp	z, cst_r
	ld	b, 6
	cp	0x93			; У — УМНИК В ШТИЛЬ
	jp	z, cst_r
	inc	b
	cp	0x90			; Р — РИКОШЕТЧИК
	jp	z, cst_r
	ld	b, 0
	cp	0x8D			; Н — НАВЕСНИК или НАВЕС+ВЫСТРЕЛ: шестой знак Н или «+»
	jp	nz, cst_r
	ld	de, 5
	add	hl, de
	ld	a, (hl)
	ld	b, 4
	cp	0x8D
	jp	z, cst_r
	inc	b
cst_r:
	ld	a, b
	ret

; стратегия закупки: Random(4) + 1; Mr. Stupid, Lobber и Windless Wit третью не берут
pick_strategy:
	ld	(cs_place), a
pks_l:
	ld	de, 4
	call	random
	ld	a, l
	inc	a
	ld	(cs_s), a
	cp	3
	jp	nz, pks_ok
	call	cs_type
	cp	1
	jp	z, pks_l
	cp	4
	jp	z, pks_l
	cp	6
	jp	z, pks_l
pks_ok:
	ld	a, (cs_place)
	call	dt_ptr
	ld	de, PL_STRAT
	add	hl, de
	ld	a, (cs_s)
	ld	(hl), a
	ret
aimain_end:

cs_place:	db	0
cs_s:		db	0
