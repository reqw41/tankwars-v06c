; Рельеф раунда — generateTerrain() эталона web/tankwars.js в профиле PROFILE_V06C (ветка fixed).
; Вход:  A = число игроков (2..4); RandSeed — в rand_seed (random.asm).
; Выход: terr_top[x], x = 0..255 — верхняя строка земли в столбце x (байт); 0xFF — столбца нет.
;        Если col(x, h) вызывается для одного x несколько раз, остаётся наименьшее значение top = 253 - h.
;        terr_h — итоговая высота h (слово). RandSeed продвинут ровно так же, как в эталоне.
; Подпрограммы: random (DE = n -> HL = Random(n)), rnd_hi (HL = старшие 16 бит следующего RandSeed).
; X0 = 3, X1 = 252, init = 200, lo = 20, hi = 185, min = 3, max = 205, m = 50 - 6*(n-2).

GT_X0		equ	3
GT_X1LIM	equ	253			; x < X1 + 1
GT_P20		equ	13107			; 0.2 * 65536
GT_P10		equ	6554			; 0.1 * 65536

gen_terrain:
	; m = 50 - 6*(n-2) = 62 - 6*n
	ld	l, a
	ld	h, 0
	add	hl, hl			; HL = 2n
	ld	e, l
	ld	d, h			; DE = 2n
	add	hl, hl			; HL = 4n
	add	hl, de			; HL = 6n
	ld	a, 62
	sub	l			; m = 62 - 6n
	ld	(gt_m), a
	; terr_top[0..255] = 0xFF
	ld	hl, terr_top
	ld	a, 0xFF
	ld	b, 0
gt_fill:
	ld	(hl), a
	inc	hl
	dec	b
	jp	nz, gt_fill
	; d = 1 - 2*Random(2)
	ld	de, 2
	call	random
	ld	a, l
	or	h
	ld	hl, 1			; A/Z — от Random(2)
	jp	nz, gt_dneg
	ld	(gt_d), hl
	jp	gt_h0
gt_dneg:
	ld	hl, -1
	ld	(gt_d), hl
gt_h0:
	; h = Random(200); s = 0; x = X0
	ld	de, 200
	call	random
	ld	(gt_h), hl
	ld	hl, 0
	ld	(gt_s), hl
	ld	hl, GT_X0
	ld	(gt_x), hl
gt_loop:
	; if x >= 253 -> done
	ld	hl, (gt_x)
	ld	a, h
	or	a
	jp	nz, gt_done
	ld	a, l
	cp	GT_X1LIM
	jp	nc, gt_done
	; if (m + 3 > x) or (252 - m < x): col(x,h); x++; continue
	ld	a, (gt_m)
	add	a, 3
	ld	e, a
	ld	hl, (gt_x)
	ld	a, h
	or	a
	jp	nz, gt_edge
	ld	a, l
	cp	e
	jp	c, gt_edge
	ld	a, (gt_m)
	ld	e, a
	ld	a, 252
	sub	e			; 252 - m
	ld	e, a
	ld	a, h
	or	a
	jp	nz, gt_edge
	ld	a, l
	cp	e
	jp	z, gt_body		; x == 252-m — ещё тело (эталон: edge только при x > 252-m)
	jp	c, gt_body
gt_edge:
	call	gt_col
	call	gt_xp1
	jp	gt_loop
gt_body:
	; a = |s|
	ld	hl, (gt_s)
	call	gt_abs
	ld	a, l
	cp	0
	jp	z, gt_b0
	cp	1
	jp	z, gt_b1
	cp	2
	jp	z, gt_b2
	cp	3
	jp	z, gt_b3
	cp	4
	jp	z, gt_b4
	jp	gt_r1
gt_b0:
	call	gt_col
	call	gt_xp1
	call	gt_col
	call	gt_xp1
	call	gt_col
	jp	gt_r1
gt_b1:
	call	gt_col
	call	gt_xp1
	call	gt_col
	call	gt_xp1
	call	gt_st
	call	gt_col
	jp	gt_r1
gt_b2:
	call	gt_col
	call	gt_xp1
	call	gt_st
	call	gt_col
	call	gt_xp1
	call	gt_st
	call	gt_col
	jp	gt_r1
gt_b3:
	call	gt_col
	call	gt_xp1
	call	gt_st
	call	gt_col
	call	gt_st
	jp	gt_r1
gt_b4:
	call	gt_col
	call	gt_st
	call	gt_st
gt_r1:
	; r1 = rnd_hi(); if r1 < 0.2: s += d
	call	rnd_hi
	ld	de, GT_P20
	ld	a, h
	sub	d
	jp	c, gt_r1_hit
	jp	nz, gt_r2
	ld	a, l
	sub	e
	jp	nc, gt_r2
gt_r1_hit:
	ld	hl, (gt_d)
	ex	de, hl
	ld	hl, (gt_s)
	add	hl, de
	ld	(gt_s), hl
gt_r2:
	; r2 = rnd_hi(); if r2 < 0.1 or |s| > 4: d = -d
	call	rnd_hi
	ld	de, GT_P10
	ld	a, h
	sub	d
	jp	c, gt_r2_flip
	jp	nz, gt_r2_big
	ld	a, l
	sub	e
	jp	c, gt_r2_flip
	jp	gt_r2_big
gt_r2_big:
	; DE = HL = r2 — не нужен; проверяем |s| > 4
	ld	hl, (gt_s)
	ld	a, h
	or	a
	jp	m, gt_r2_neg
	jp	nz, gt_r2_flip
	ld	a, l
	cp	5
	jp	c, gt_clamp
	jp	gt_r2_flip
gt_r2_neg:
	; s < 0: |s| > 4 <=> s < -4 (A = h)
	cp	0xFF
	jp	c, gt_r2_flip
	ld	a, l
	cp	0xFC
	jp	c, gt_r2_flip
	jp	gt_clamp
gt_r2_flip:
	ld	hl, (gt_d)
	call	gt_neg
	ld	(gt_d), hl
gt_clamp:
	; s = max(-4, min(4, s))
	ld	hl, (gt_s)
	ld	a, h
	or	a
	jp	m, gt_cl_neg
	jp	nz, gt_cl_pos
	ld	a, l
	cp	5
	jp	c, gt_fin
	jp	gt_cl_pos
gt_cl_neg:
	cp	0xFF
	jp	c, gt_cl_m4
	ld	a, l
	cp	0xFC
	jp	nc, gt_fin
gt_cl_m4:
	ld	hl, -4
	jp	gt_cl_w
gt_cl_pos:
	ld	hl, 4
gt_cl_w:
	ld	(gt_s), hl
gt_fin:
	; if h <= 20: d = 1
	ld	hl, (gt_h)
	ld	a, h
	or	a
	jp	m, gt_f_d1
	jp	nz, gt_f_hi
	ld	a, l
	cp	21
	jp	nc, gt_f_hi
gt_f_d1:
	ld	hl, 1
	ld	(gt_d), hl
gt_f_hi:
	; if h >= 185: d = -1
	ld	hl, (gt_h)
	ld	a, h
	or	a
	jp	m, gt_f_min
	jp	nz, gt_f_dm1
	ld	a, l
	cp	185
	jp	c, gt_f_min
gt_f_dm1:
	ld	hl, -1
	ld	(gt_d), hl
gt_f_min:
	; if h <= 3: s = 1
	ld	hl, (gt_h)
	ld	a, h
	or	a
	jp	m, gt_f_s1
	jp	nz, gt_f_max
	ld	a, l
	cp	4
	jp	nc, gt_f_max
gt_f_s1:
	ld	hl, 1
	ld	(gt_s), hl
gt_f_max:
	; if h >= 205: s = -1
	ld	hl, (gt_h)
	ld	a, h
	or	a
	jp	m, gt_next
	jp	nz, gt_f_sm1
	ld	a, l
	cp	205
	jp	c, gt_next
gt_f_sm1:
	ld	hl, -1
	ld	(gt_s), hl
gt_next:
	call	gt_xp1
	jp	gt_loop
gt_done:
	ld	hl, (gt_h)
	ld	(terr_h), hl
	ret

; col(x, h): top = 253 - h; если top < terr_top[x] (беззнаковое), записать. Портит AF, DE, HL.
gt_col:
	ld	hl, (gt_h)
	ld	a, 253
	sub	l			; A = top; DAD и ld hl,(nn) не трогают A
	ld	hl, (gt_x)
	ld	de, terr_top
	add	hl, de
	ld	e, a
	ld	a, (hl)
	cp	e
	ret	c			; existing < top — оставляем меньшее
	ld	(hl), e
	ret

gt_xp1:
	ld	hl, (gt_x)
	inc	hl
	ld	(gt_x), hl
	ret

; st(h): h += (s > 0 ? 1 : -1)
gt_st:
	ld	hl, (gt_h)
	ld	a, (gt_s + 1)
	or	a
	jp	m, gt_st_d
	inc	hl
	jp	gt_st_w
gt_st_d:
	dec	hl
gt_st_w:
	ld	(gt_h), hl
	ret

; HL = -HL (8080 без neg)
gt_neg:
	xor	a
	sub	l
	ld	l, a
	ld	a, 0
	sbc	a, h
	ld	h, a
	ret

; HL = |HL|
gt_abs:
	ld	a, h
	or	a
	ret	p
	jp	gt_neg

gen_terrain_end:

terr_top:	ds	256
terr_h:		dw	0

gt_m:		db	0
gt_h:		dw	0
gt_s:		dw	0
gt_d:		dw	0
gt_x:		dw	0
