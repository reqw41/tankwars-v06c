; Random(n): Turbo Pascal 6, seed = seed·08088405h + 1, результат — старшие 16 бит mod n.
; Вход: DE = n. Выход: HL = Random. Портит AF, BC.

random:
	push	de
	call	lcg_next
	pop	de
	ld	hl, (rand_seed + 2)	; hi 16
	ld	a, d
	or	e
	jp	nz, rnd_mod
	ld	hl, 0
	ret
; rnd_hi: шаг генератора, HL = старшие 16 бит нового RandSeed (0..65535). Для порогов «Random < p»:
; сравнить HL с порогом (0.2 → 13107, 0.1 → 6554, 0.05 → 3277, 0.5 → 32768), см. web/fixmath.js TH. Портит AF, BC, DE.
rnd_hi:
	call	lcg_next
	ld	hl, (rand_seed + 2)
	ret
rnd_mod:
	ld	b, d
	ld	c, e			; BC = n
	call	umod16
	ret

; rand_seed := (rand_seed * 0x08088405 + 1) & 0xffffffff
; 0x08088405 = биты 0,2,10,15,19,27
lcg_next:
	ld	hl, acc
	xor	a
	ld	(hl), a
	inc	hl
	ld	(hl), a
	inc	hl
	ld	(hl), a
	inc	hl
	ld	(hl), a
	ld	b, 0
	call	acc_add_shl
	ld	b, 2
	call	acc_add_shl
	ld	b, 10
	call	acc_add_shl
	ld	b, 15
	call	acc_add_shl
	ld	b, 19
	call	acc_add_shl
	ld	b, 27
	call	acc_add_shl
	ld	hl, acc
	ld	a, (hl)
	add	a, 1
	ld	(hl), a
	inc	hl
	ld	a, (hl)
	adc	a, 0
	ld	(hl), a
	inc	hl
	ld	a, (hl)
	adc	a, 0
	ld	(hl), a
	inc	hl
	ld	a, (hl)
	adc	a, 0
	ld	(hl), a
	ld	hl, acc
	ld	de, rand_seed
	ld	b, 4
lcg_store:
	ld	a, (hl)
	ld	(de), a
	inc	hl
	inc	de
	dec	b
	jp	nz, lcg_store
	ret

; acc += rand_seed << B
acc_add_shl:
	push	bc
	ld	hl, rand_seed
	ld	de, tmp32
	ld	b, 4
acc_cp:
	ld	a, (hl)
	ld	(de), a
	inc	hl
	inc	de
	dec	b
	jp	nz, acc_cp
	pop	bc
	ld	a, b
	or	a
	jp	z, acc_add
acc_sh:
	or	a
	ld	hl, tmp32
	ld	a, (hl)
	rla
	ld	(hl), a
	inc	hl
	ld	a, (hl)
	rla
	ld	(hl), a
	inc	hl
	ld	a, (hl)
	rla
	ld	(hl), a
	inc	hl
	ld	a, (hl)
	rla
	ld	(hl), a
	dec	b
	jp	nz, acc_sh
acc_add:
	ld	hl, acc
	ld	de, tmp32
	ld	a, (de)
	add	a, (hl)
	ld	(hl), a
	inc	hl
	inc	de
	ld	a, (de)
	adc	a, (hl)
	ld	(hl), a
	inc	hl
	inc	de
	ld	a, (de)
	adc	a, (hl)
	ld	(hl), a
	inc	hl
	inc	de
	ld	a, (de)
	adc	a, (hl)
	ld	(hl), a
	ret

; HL = HL % BC (беззнаковое). Остаток — 32 бита, чтобы сдвиг не обрезал.
; Если BC=0, HL=0. Портит AF, DE.
umod16:
	ld	a, b
	or	c
	jp	nz, umod_go
	ld	hl, 0
	ret
umod_go:
	xor	a
	ld	(rem32), a
	ld	(rem32 + 1), a
	ld	(rem32 + 2), a
	ld	(rem32 + 3), a
	ld	a, 16
	ld	(umod_cnt), a
umod_bit:
	add	hl, hl
	push	hl
	ld	hl, rem32
	ld	a, (hl)
	rla
	ld	(hl), a
	inc	hl
	ld	a, (hl)
	rla
	ld	(hl), a
	inc	hl
	ld	a, (hl)
	rla
	ld	(hl), a
	inc	hl
	ld	a, (hl)
	rla
	ld	(hl), a
	pop	hl
	ld	a, (rem32 + 2)
	ld	d, a
	ld	a, (rem32 + 3)
	or	d
	jp	nz, umod_sub
	ld	a, (rem32 + 1)
	cp	b
	jp	c, umod_next
	jp	nz, umod_sub
	ld	a, (rem32)
	cp	c
	jp	c, umod_next
umod_sub:
	ld	a, (rem32)
	sub	c
	ld	(rem32), a
	ld	a, (rem32 + 1)
	sbc	a, b
	ld	(rem32 + 1), a
	ld	a, (rem32 + 2)
	sbc	a, 0
	ld	(rem32 + 2), a
	ld	a, (rem32 + 3)
	sbc	a, 0
	ld	(rem32 + 3), a
umod_next:
	ld	a, (umod_cnt)
	dec	a
	ld	(umod_cnt), a
	jp	nz, umod_bit
	ld	hl, (rem32)
	ret

random_end:

rand_seed:	ds	4
acc:		ds	4
tmp32:		ds	4
rem32:		ds	4
umod_cnt:	db	0
