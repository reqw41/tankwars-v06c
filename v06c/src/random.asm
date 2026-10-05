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
	ld	a, e			; степень двойки (1, 2, 4, ... 128): остаток — младшие биты
	dec	a
	ld	c, a
	and	e
	jp	nz, rnd_m8g
	ld	a, l
	and	c
	ld	l, a
	ld	h, 0
	ret
rnd_m8g:
	ld	a, e
	or	a
	jp	m, rnd_m8w
	; n < 128 (почти все вызовы): остаток в A после сдвига не больше 255 — 16 шагов по пять команд
	xor	a
	ld	c, e
	dup	16
	add	hl, hl
	rla
	cp	c
	jp	c, 1F
	sub	c
1
	edup
	ld	l, a
	ld	h, 0
	ret
rnd_m8w:
	xor	a
	; 128 <= n < 256: после сдвига остаток бывает больше 255 — тогда вычитать без сравнения
	ld	c, e
	dup	16
	add	hl, hl
	rla
	jp	c, 1F			; остаток >= 256 — вычитать точно
	cp	c
	jp	c, 2F
1	sub	c
2
	edup
	ld	l, a
	ld	h, 0
	ret
rnd_mod16:
	ld	b, d
	ld	c, e			; BC = n
	jp	umod16

; rand_seed := (rand_seed * 0x08088405 + 1) & 0xffffffff
; Умножение по таблицам: K[x] = x·08088405h (4 байта), страницы LCG_TAB..+3 — байты 0..3, индекс — младший байт
; адреса. s·K = K[s0] + (K[s1] << 8) + (K[s2] << 16) + (K[s3] << 24): десять выборок и сложения с переносом.
; Таблицы (1 КБ вне образа) строит lcg_init — вызвать один раз до первого Random. Портит AF, BC, DE, HL.
LCG_TAB		equ	0x9A00
lcg_next:
	ld	a, (rand_seed)
	ld	l, a
	ld	h, LCG_TAB >> 8
	ld	b, (hl)
	inc	h
	ld	c, (hl)
	inc	h
	ld	d, (hl)
	inc	h
	ld	e, (hl)			; E:D:C:B = K[s0]
	ld	a, (rand_seed + 1)
	ld	l, a
	ld	h, LCG_TAB >> 8
	ld	a, c
	add	a, (hl)
	ld	c, a
	inc	h
	ld	a, d
	adc	a, (hl)
	ld	d, a
	inc	h
	ld	a, e
	adc	a, (hl)
	ld	e, a
	ld	a, (rand_seed + 2)
	ld	l, a
	ld	h, LCG_TAB >> 8
	ld	a, d
	add	a, (hl)
	ld	d, a
	inc	h
	ld	a, e
	adc	a, (hl)
	ld	e, a
	ld	a, (rand_seed + 3)
	ld	l, a
	ld	h, LCG_TAB >> 8
	ld	a, e
	add	a, (hl)
	ld	e, a
	inc	b			; + 1
	jp	nz, lcg_1
	inc	c
	jp	nz, lcg_1
	inc	d
	jp	nz, lcg_1
	inc	e
lcg_1:
	ld	h, c
	ld	l, b
	ld	(rand_seed), hl
	ld	h, e
	ld	l, d
	ld	(rand_seed + 2), hl
	ret
; таблицы K[x] = x·08088405h для x = 0..255
lcg_init:
	ld	bc, 0
	ld	d, b
	ld	e, b
	ld	l, b
lcg_i1:
	ld	h, LCG_TAB >> 8
	ld	(hl), b
	inc	h
	ld	(hl), c
	inc	h
	ld	(hl), d
	inc	h
	ld	(hl), e
	ld	a, b
	add	a, 0x05
	ld	b, a
	ld	a, c
	adc	a, 0x84
	ld	c, a
	ld	a, d
	adc	a, 0x08
	ld	d, a
	ld	a, e
	adc	a, 0x08
	ld	e, a
	inc	l
	jp	nz, lcg_i1
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
umod_cnt:	db	0
