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
; 0x08088405 = биты 0, 2, 10, 15, 19, 27. Сдвигаемая копия семени tmp32 двигается нарастающим итогом:
; +2 бита, +байт, +5 бит, +4 бита, +байт — всего 11 сдвигов по биту вместо 73.
lcg_next:
	ld	hl, (rand_seed)
	ld	(tmp32), hl
	ld	(acc), hl		; бит 0
	ld	hl, (rand_seed + 2)
	ld	(tmp32 + 2), hl
	ld	(acc + 2), hl
	ld	b, 2
	call	acc_sh_add		; бит 2
	call	tmp_byte
	call	acc_add			; бит 10
	ld	b, 5
	call	acc_sh_add		; бит 15
	ld	b, 4
	call	acc_sh_add		; бит 19
	call	tmp_byte
	call	acc_add			; бит 27
	ld	hl, acc			; + 1
lcg_inc:
	inc	(hl)
	jp	nz, lcg_done
	inc	hl
	ld	a, l
	cp	(acc + 4) & 255
	jp	nz, lcg_inc
lcg_done:
	ld	hl, (acc)
	ld	(rand_seed), hl
	ld	hl, (acc + 2)
	ld	(rand_seed + 2), hl
	ret

; tmp32 <<= 8
tmp_byte:
	ld	hl, (tmp32 + 1)
	ld	(tmp32 + 2), hl
	ld	a, (tmp32)
	ld	(tmp32 + 1), a
	xor	a
	ld	(tmp32), a
	ret

; tmp32 <<= B, затем acc += tmp32
acc_sh_add:
	ld	hl, (tmp32)
	ex	de, hl
	ld	hl, (tmp32 + 2)		; HL:DE = tmp32
acc_sh:
	ex	de, hl
	add	hl, hl			; младшее слово
	ex	de, hl
	ld	a, l
	rla
	ld	l, a
	ld	a, h
	rla
	ld	h, a			; старшее слово с переносом
	dec	b
	jp	nz, acc_sh
	ld	(tmp32 + 2), hl
	ex	de, hl
	ld	(tmp32), hl
acc_add:
	ld	hl, (acc)
	ex	de, hl
	ld	hl, (tmp32)
	add	hl, de
	ld	(acc), hl
	ld	hl, (acc + 2)
	ex	de, hl
	ld	hl, (tmp32 + 2)
	jp	nc, acc_add_h
	inc	hl
acc_add_h:
	add	hl, de
	ld	(acc + 2), hl
	ret

; HL = HL % BC (беззнаковое). Если BC = 0, HL = 0. Портит AF, DE.
; Остаток держится в DE; 17-й бит после сдвига — в переносе.
umod16:
	ld	a, b
	or	c
	jp	nz, umod_go
	ld	hl, 0
	ret
umod_go:
	ld	de, 0
	ld	a, 16
	ld	(umod_cnt), a
umod_bit:
	add	hl, hl
	ld	a, e
	rla
	ld	e, a
	ld	a, d
	rla
	ld	d, a
	jp	c, umod_sub		; остаток >= 65536 — вычитать точно
	ld	a, e
	sub	c
	ld	a, d
	sbc	a, b
	jp	c, umod_next		; остаток < n
umod_sub:
	ld	a, e
	sub	c
	ld	e, a
	ld	a, d
	sbc	a, b
	ld	d, a
umod_next:
	ld	a, (umod_cnt)
	dec	a
	ld	(umod_cnt), a
	jp	nz, umod_bit
	ex	de, hl
	ret

random_end:

rand_seed:	ds	4
acc:		ds	4
tmp32:		ds	4
umod_cnt:	db	0
