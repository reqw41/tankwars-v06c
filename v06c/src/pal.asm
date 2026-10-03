; Палитра 16 регистров парами. 0..3 — страница, 4..7 — tankPalV06C(p).
; pal_men/divr/divg/divb: по 4 слова (игроки 0..3); канал включён, если делитель = 1.

; pal_apply = pal_prepare (расчёт 8 байт цветов) + pal_out (запись 16 регистров).
; На машине pal_out зовут сразу после прерывания кадра, пока луч в бордюре: регистр палитры выбирается цветом
; под лучом, в бордюре это индекс из порта 02h. Расчёт делается заранее — он в бордюр не помещается.
pal_apply:
	call	pal_prepare
	jp	pal_out
pal_prepare:
	ld	de, pal_page
	ld	hl, pal_byte
	ld	b, 4
pa_cp:
	ld	a, (de)
	ld	(hl), a
	inc	de
	inc	hl
	dec	b
	jp	nz, pa_cp
	xor	a
	ld	(pal_cur), a
pa_tn:
	call	tank_rgb_byte
	ld	hl, pal_byte + 4
	ld	a, (pal_cur)
	ld	e, a
	ld	d, 0
	add	hl, de
	ld	a, (tr_byte)
	ld	(hl), a
	ld	a, (pal_cur)
	inc	a
	ld	(pal_cur), a
	cp	4
	jp	nz, pa_tn
	ret
pal_out:
	ld	a, 0x88
	out	(0), a
	ld	a, 0xFF
	out	(3), a		; прокрутка FFh: верхняя строка экрана — младший байт адреса FFh
	xor	a
	out	(1), a
	ld	b, 15			; от 15 к 0: вторая запись в порт 0Ch доходит уже при следующем индексе,
	ld	hl, RESULT + 15		; при обходе вниз последним остаётся верный цвет индекса 0
pa_out:
	ld	a, b
	and	0x04
	ld	c, 0
	jp	z, pa_p1
	ld	c, 1
pa_p1:
	ld	a, b
	and	0x02
	jp	z, pa_p2
	ld	a, c
	or	2
	ld	c, a
pa_p2:
	ld	a, b
	and	0x01
	jp	z, pa_p3
	ld	a, c
	or	4
	ld	c, a
pa_p3:
	ld	e, c
	ld	d, 0
	push	hl
	ld	hl, pal_byte
	add	hl, de
	ld	c, (hl)
	pop	hl
	ld	a, b
	out	(2), a
	ld	a, c
	out	(0x0C), a
	out	(0x0C), a
	ld	(hl), c
	dec	hl
	dec	b
	jp	p, pa_out
	xor	a
	out	(2), a
	ret

; tankPalV06C: men≤0 → чёрный; m=min(men,100);
; R,G = 3+m·4/100 если делитель канала = 1, иначе 0; B = 1+m·2/100.
tank_rgb_byte:
	ld	a, (pal_cur)
	ld	e, a
	ld	d, 0
	ld	hl, pal_men
	add	hl, de
	add	hl, de
	ld	e, (hl)
	inc	hl
	ld	d, (hl)
	ld	a, d
	and	0x80
	jp	nz, tr_blk
	ld	a, d
	or	e
	jp	z, tr_blk
	ld	a, d
	or	a
	jp	nz, tr_cap
	ld	a, e
	cp	101
	jp	c, tr_m
tr_cap:
	ld	e, 100
tr_m:
	ld	a, e
	ld	b, 0
tr_d25:
	cp	25
	jp	c, tr_d25d
	sub	25
	inc	b
	jp	tr_d25
tr_d25d:
	ld	a, b
	add	a, 3
	ld	(tr_rg), a
	ld	a, e
	ld	b, 1
	cp	50
	jp	c, tr_bb
	inc	b
	cp	100
	jp	c, tr_bb
	inc	b
tr_bb:
	ld	a, b
	ld	(tr_bv), a
	xor	a
	ld	(tr_r), a
	ld	(tr_g), a
	ld	(tr_b), a
	ld	hl, pal_divr
	call	tr_on
	jp	nz, tr_nr
	ld	a, (tr_rg)
	ld	(tr_r), a
tr_nr:
	ld	hl, pal_divg
	call	tr_on
	jp	nz, tr_ng
	ld	a, (tr_rg)
	ld	(tr_g), a
tr_ng:
	ld	hl, pal_divb
	call	tr_on
	jp	nz, tr_nb
	ld	a, (tr_bv)
	ld	(tr_b), a
tr_nb:
	ld	a, (tr_b)
	and	3
	rlca
	rlca
	rlca
	rlca
	rlca
	rlca
	ld	b, a
	ld	a, (tr_g)
	and	7
	rlca
	rlca
	rlca
	or	b
	ld	b, a
	ld	a, (tr_r)
	and	7
	or	b
	ld	(tr_byte), a
	ret
tr_blk:
	xor	a
	ld	(tr_byte), a
	ret

; HL = pal_div*, pal_cur. ZF=1 если слово = 1.
tr_on:
	ld	a, (pal_cur)
	ld	e, a
	ld	d, 0
	add	hl, de
	add	hl, de
	ld	a, (hl)
	cp	1
	ret	nz
	inc	hl
	ld	a, (hl)
	or	a
	ret

pal_apply_end:

pal_page:
	db	0x00, 0x29, 0xAD, 0x77
pal_byte:	ds	8
pal_men:	ds	8
pal_divr:	ds	8
pal_divg:	ds	8
pal_divb:	ds	8
pal_cur:	db	0
tr_rg:		db	0
tr_bv:		db	0
tr_r:		db	0
tr_g:		db	0
tr_b:		db	0
tr_byte:	db	0
