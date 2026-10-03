; Компьютерный игрок в цикле хода — computerStep(), plan(), aiType(), pickStrategy() эталона web/tankwars.js.
;   computer_step: вход A = место игрока, ap_rebound (стены отражают). Выход A = код действия.
;   pick_strategy: вход A = место игрока. PL_STRAT = Random(4) + 1 с отбором по типу игрока.
; Тип игрока — по имени (PL_NAME, регистр букв не важен): M — Mr. Stupid, B — Birdy Bonker, R — Rifleman,
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
	and	0xDF
	ld	b, 1
	cp	'M'
	jp	z, cst_r
	inc	b
	cp	'B'
	jp	z, cst_r
	inc	b
	cp	'R'
	jp	z, cst_r
	ld	b, 6
	cp	'W'
	jp	z, cst_r
	inc	b
	cp	'T'
	jp	z, cst_r
	ld	b, 0
	cp	'L'
	jp	nz, cst_r
	inc	hl
	inc	hl
	inc	hl
	ld	a, (hl)
	and	0xDF
	ld	b, 4
	cp	'B'
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
