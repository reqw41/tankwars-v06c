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
	ld	a, d
	or	a
	jp	nz, rnd_mod16
	; n < 256 (почти все вызовы): остаток в A, 16 шагов по 9 команд
	ld	c, e
	ld	b, 16
rnd_m8:
	add	hl, hl
	rla
	jp	c, rnd_m8s		; остаток >= 256 — вычитать точно
	cp	c
	jp	c, rnd_m8n
rnd_m8s:
	sub	c
rnd_m8n:
	dec	b
	jp	nz, rnd_m8
	ld	l, a
	ld	h, 0
	ret
rnd_mod16:
	ld	b, d
	ld	c, e			; BC = n
	jp	umod16

; rand_seed := (rand_seed * 0x08088405 + 1) & 0xffffffff
; 0x08088405 = биты 0, 2, 10, 15, 19, 27: s + (s<<2) + (s<<2)<<8 + (s<<7)<<8 + (s<<3)<<16 + (s<<3)<<24 + 1.
; Три сдвига влево на бит и один вправо вместо одиннадцати; сдвиги на 8, 16, 24 — смещением байтов.
lcg_next:
	ld	hl, (rand_seed)
	ex	de, hl
	ld	hl, (rand_seed + 2)	; HL:DE = s
	call	lcg_sh
	call	lcg_sh			; s << 2
	ld	(tmp32 + 2), hl
	ex	de, hl
	ld	(tmp32), hl
	ex	de, hl
	call	lcg_sh			; s << 3: нужно только младшее слово
	ex	de, hl
	ld	(lcg_a3), hl
	; lcg_v = младшие три байта (s << 7): сдвиг вправо на бит байтов s2, s1, s0
	ld	hl, rand_seed + 2
	ld	a, (hl)
	rra
	dec	hl
	ld	a, (hl)
	rra
	ld	(lcg_v + 2), a
	dec	hl
	ld	a, (hl)
	rra
	ld	(lcg_v + 1), a
	ld	a, 0
	rra
	ld	(lcg_v), a
	; s + (s << 2)
	ld	hl, (rand_seed)
	ex	de, hl
	ld	hl, (tmp32)
	add	hl, de
	ld	(rand_seed), hl
	ld	hl, (rand_seed + 2)
	ex	de, hl
	ld	hl, (tmp32 + 2)
	jp	nc, lcg_1
	inc	hl
lcg_1:
	add	hl, de
	ld	(rand_seed + 2), hl
	; + 1
	ld	hl, rand_seed
	inc	(hl)
	jp	nz, lcg_2
	inc	hl
	inc	(hl)
	jp	nz, lcg_2
	inc	hl
	inc	(hl)
	jp	nz, lcg_2
	inc	hl
	inc	(hl)
lcg_2:
	; со смещением на байт: (s << 2) и (s << 7)
	ld	hl, rand_seed + 1
	ld	de, tmp32
	call	lcg_add3
	ld	hl, rand_seed + 1
	ld	de, lcg_v
	call	lcg_add3
	; со смещением на два и три байта: (s << 3)
	ld	hl, (rand_seed + 2)
	ex	de, hl
	ld	hl, (lcg_a3)
	add	hl, de
	ld	(rand_seed + 2), hl
	ld	a, (lcg_a3)
	ld	hl, rand_seed + 3
	add	a, (hl)
	ld	(hl), a
	ret
; HL:DE <<= 1
lcg_sh:
	ex	de, hl
	add	hl, hl
	ex	de, hl
	ld	a, l
	rla
	ld	l, a
	ld	a, h
	rla
	ld	h, a
	ret
; три байта по адресу HL += три байта по адресу DE
lcg_add3:
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
lcg_a3:		dw	0
lcg_v:		ds	3
tmp32:		ds	4
umod_cnt:	db	0
