; После выстрела — начало afterShot() эталона web/tankwars.js (PROFILE_V06C): перерисовка танков, осыпание, падение.
; Вход: n_players, players; as_crumble (байт, процент осыпания 0..100), as_fall (0/1 — танки падают),
;       as_rebound (0/1 — стены отражают); RandSeed в rand_seed.
; ЗАГЛУШКА: задача Q5 (docs/tasks/Q5-after.md). Готовая часть — rnd_le_pct.

; Готово (не менять): CF = 1, если Random·100 <= A (A — процент 0..100). Один шаг генератора. Портит всё.
; Это FX.rndLeRatio(rng, A, 100) эталона: hi·100 <= A·65536, hi — старшие 16 бит RandSeed.
rnd_le_pct:
	ld	(as_pct), a
	call	rnd_hi
	ex	de, hl			; DE = hi
	ld	hl, 0
	ld	c, 0			; C:HL = hi·100 (24 бита)
	ld	b, 100
as_m1:
	add	hl, de
	jp	nc, as_m2
	inc	c
as_m2:
	dec	b
	jp	nz, as_m1
	ld	a, (as_pct)
	cp	c
	jp	c, as_no		; процент < старшего байта
	jp	nz, as_yes		; процент > старшего байта
	ld	a, h
	or	l
	jp	z, as_yes
as_no:
	or	a
	ret
as_yes:
	scf
	ret

after_shot:
	ret
after_end:

as_crumble:	db	0
as_fall:	db	0
as_rebound:	db	0
as_pct:		db	0
