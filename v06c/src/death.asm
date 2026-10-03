; Гибель танка — death() эталона web/tankwars.js (PROFILE_V06C), семь вариантов.
; Вход: dt_variant (0..6), dt_victim (место 1..n; его PL_ALIVE уже 0), dt_wind (слово), dt_xkill (0/1);
;       n_players, players, RandSeed.
; Варианты: 0 — обломки по одному, 2 — обломки разом, 1 и 3 — искры, 4 — фонтан земли, 5 — исчез, 6 — серия взрывов.

DT_X0		equ	3
DT_X1		equ	252
DT_Y0		equ	27
DT_Y1		equ	252

death:
	ld	a, (dt_victim)
	call	dt_ptr
	ld	(dt_vp), hl
	ld	a, (hl)			; PL_X = 0
	ld	(dt_x), a
	inc	hl
	ld	a, (hl)			; PL_Y = 1
	ld	(dt_y), a
	ld	a, (dt_variant)
	or	a
	jp	z, death0
	dec	a
	jp	z, dt_sparks0
	dec	a
	jp	z, death2
	dec	a
	jp	z, dt_sparks1
	dec	a
	jp	z, death4
	dec	a
	jp	z, death5
	; --- 6: серия взрывов оружием 1..count в точке танка, «ничьих» ---
	ld	de, 10
	call	random
	ld	a, l
	ld	b, 1
	cp	2
	jp	c, dt6_c
	inc	b
	cp	5
	jp	c, dt6_c
	inc	b
	cp	8
	jp	c, dt6_c
	inc	b
dt6_c:
	ld	a, b
	ld	(dt_cnt), a
	ld	a, 1
dt6_l:
	ld	(dt_j), a
	ld	(ex_weapon), a
	ld	hl, 0
	ld	(ex_x), hl
	ld	(ex_y), hl
	ld	a, (dt_x)
	ld	l, a
	ld	(ex_x + 2), hl
	ld	a, (dt_y)
	ld	l, a
	ld	(ex_y + 2), hl
	ld	a, 1			; попадание «в землю»
	ld	(ex_hit), a
	xor	a
	ld	(ex_shooter), a
	call	explode
	call	redraw_all
	ld	a, (dt_cnt)
	ld	b, a
	ld	a, (dt_j)
	cp	b
	jp	z, dt_men1
	inc	a
	jp	dt6_l

; --- 5: исчез ---
death5:
	call	dt_men1
	ld	a, (dt_victim)
	jp	erase_tb
; men = −1
dt_men1:
	ld	hl, (dt_vp)
	ld	de, PL_MEN
	add	hl, de
	ld	(hl), 0xFF
	inc	hl
	ld	(hl), 0xFF
	ret

; --- 4: фонтан земли ---
death4:
	ld	de, 30
	call	random
	ld	de, 30
	add	hl, de
	ld	a, l
	ld	(dt_cnt), a		; waves
	ld	a, 1
dt4_w:
	ld	(dt_j), a
	ld	de, 50
	call	random
	ld	(dt_n), hl
dt4_p:
	ld	hl, (dt_n)
	ld	a, h
	or	l
	jp	z, dt4_wn
	dec	hl
	ld	(dt_n), hl
	ld	a, (dt_j)		; h = Random(10·r)
	call	dt_mul10
	ex	de, hl
	call	random
	ld	(dt_a), hl
	call	dt_half			; HL = trunc(Random(h + 10) − 5 − h/2)
	ex	de, hl
	ld	a, (dt_x)
	ld	l, a
	ld	h, 0
	add	hl, de
	ld	(dt_px), hl		; x = tx + dx
	ld	hl, (dt_a)
	call	dt_neg
	ex	de, hl
	ld	a, (dt_y)
	ld	l, a
	ld	h, 0
	add	hl, de
	ld	(dt_py), hl		; y = ty − h
dt4_r:	; отражать, пока точка не в поле
	call	dt_infield
	jp	nc, dt4_put
	call	dt_reflect
	jp	dt4_r
dt4_put:
	ld	a, (dt_px)
	ld	d, a
	ld	a, (dt_py)
	ld	e, a
	ld	a, 1
	call	putpixel
	jp	dt4_p
dt4_wn:
	ld	a, (dt_cnt)
	ld	b, a
	ld	a, (dt_j)
	cp	b
	jp	z, dt4_end
	inc	a
	jp	dt4_w
dt4_end:
	call	redraw_all
	ld	a, (dt_victim)
	jp	erase_tb

; --- 1 и 3: искры ---
dt_sparks0:
	xor	a
	jp	dt_sp
dt_sparks1:
	ld	a, 1
dt_sp:
	ld	(dt_mode), a
	ld	de, 5
	call	random
	ld	a, l
	add	a, 5
	ld	(dt_cnt), a		; bursts
dt_sb:
	ld	de, 48
	call	random
	inc	hl
	inc	hl
	ld	a, l
	ld	(dt_m), a		; m = 2..49
	ld	de, 8
	call	random
	ld	a, l
	inc	a
	ld	(dt_kind), a
	ld	hl, dt_buf1
	ld	(dt_cur), hl
	ld	hl, dt_buf2
	ld	(dt_prev), hl
	ld	a, 1
dt_sf:
	ld	(dt_j), a		; кадр f = 1..5
	; расчёт кадра в dt_cur
	ld	hl, (dt_cur)
	ld	(dt_bp), hl
	ld	a, (dt_m)
dt_sg:
	ld	(dt_i), a
	ld	a, (dt_j)
	call	dt_mul10
	ex	de, hl
	call	random
	ld	(dt_a), hl		; a = Random(10·f)
	call	dt_half
	ld	(dt_b), hl		; b
	call	dt_shape		; dt_px, dt_py
	call	dt_reflect
	ld	hl, (dt_bp)
	ld	a, (dt_px)
	ld	(hl), a
	inc	hl
	ld	a, (dt_py)
	ld	(hl), a
	inc	hl
	ld	(dt_bp), hl
	ld	a, (dt_i)
	dec	a
	jp	nz, dt_sg
	; рисование кадра
	ld	hl, (dt_cur)
	ld	(dt_bp), hl
	ld	hl, (dt_prev)
	ld	(dt_bq), hl
	ld	a, (dt_m)
dt_sd:
	ld	(dt_i), a
	ld	hl, (dt_bp)
	ld	d, (hl)
	inc	hl
	ld	e, (hl)
	inc	hl
	ld	(dt_bp), hl
	ex	de, hl
	ld	(dt_pt), hl		; L = y, H = x
	call	dt_phit
	ld	de, 14
	call	random			; цвет искры: число берётся всегда
	ld	a, (dt_mode)
	or	a
	ld	a, 3
	jp	z, dt_sd1
	ld	a, l
	cp	1			; 0xC9 + 1 = 0xCA — комок земли
	ld	a, 3
	jp	nz, dt_sd1
	ld	a, 1
dt_sd1:
	ld	hl, (dt_pt)
	ld	d, h
	ld	e, l
	call	putpixel
	ld	a, (dt_mode)
	or	a
	jp	nz, dt_sd2
	ld	a, (dt_j)
	cp	1
	jp	z, dt_sd2
	ld	hl, (dt_bq)		; стереть ту же искру прошлого кадра
	ld	d, (hl)
	inc	hl
	ld	e, (hl)
	inc	hl
	ld	(dt_bq), hl
	xor	a
	call	putpixel
dt_sd2:
	ld	a, (dt_i)
	dec	a
	jp	nz, dt_sd
	; кадры меняются местами
	ld	hl, (dt_cur)
	ex	de, hl
	ld	hl, (dt_prev)
	ld	(dt_cur), hl
	ex	de, hl
	ld	(dt_prev), hl
	ld	a, (dt_j)
	cp	5
	jp	z, dt_sl
	inc	a
	jp	dt_sf
dt_sl:	; режим 0: стереть последний кадр (он теперь в dt_prev)
	ld	a, (dt_mode)
	or	a
	jp	nz, dt_sn
	ld	hl, (dt_prev)
	ld	(dt_bq), hl
	ld	a, (dt_m)
dt_se:
	ld	(dt_i), a
	ld	hl, (dt_bq)
	ld	d, (hl)
	inc	hl
	ld	e, (hl)
	inc	hl
	ld	(dt_bq), hl
	xor	a
	call	putpixel
	ld	a, (dt_i)
	dec	a
	jp	nz, dt_se
dt_sn:
	ld	a, (dt_cnt)
	dec	a
	ld	(dt_cnt), a
	jp	nz, dt_sb
	call	redraw_all
	ld	a, (dt_victim)
	call	erase_tb
	ld	a, 3
	jp	replace_color

; искра попала в танк без щита: men −= Random(3). Точка — dt_pt (H = x, L = y).
dt_phit:
	ld	a, (dt_xkill)
	or	a
	ret	z
	ld	hl, (dt_pt)
	ld	d, h
	ld	e, l
	call	getpixel
	cp	4
	ret	c
	sub	3			; место 1..4
	ld	b, a
	ld	a, (n_players)
	cp	b
	ret	c
	ld	a, b
	call	dt_ptr
	ld	(dt_hp), hl
	call	dt_shield_pos
	ret	c			; щит > 0
	ld	de, 3
	call	random
	ex	de, hl
dt_hurt:				; men −= DE игроку dt_hp
	ld	hl, (dt_hp)
	ld	bc, PL_MEN
	add	hl, bc
	ld	a, (hl)
	sub	e
	ld	(hl), a
	inc	hl
	ld	a, (hl)
	sbc	a, d
	ld	(hl), a
	ret
; CF = 1, если щит игрока dt_hp > 0
dt_shield_pos:
	ld	hl, (dt_hp)
	ld	de, PL_SHIELD + 3
	add	hl, de
	ld	a, (hl)
	or	a
	jp	m, dt_sp_no
	dec	hl
	or	(hl)
	dec	hl
	or	(hl)
	dec	hl
	or	(hl)
	jp	z, dt_sp_no
	scf
	ret
dt_sp_no:
	or	a
	ret

; точка искры по виду: dt_px, dt_py (слова) из dt_x, dt_y, dt_a, dt_b
dt_shape:
	ld	a, (dt_kind)
	cp	3
	jp	z, dt_sh3
	cp	4
	jp	z, dt_sh4
	; виды 1, 2, 5..8: x = tx + b (+a для 5, 7; −a для 6, 8), y = ty − a (1, 5, 6) или ty + a (2, 7, 8)
	ld	hl, (dt_b)
	ex	de, hl
	ld	a, (dt_x)
	ld	l, a
	ld	h, 0
	add	hl, de
	ld	a, (dt_kind)
	cp	5
	jp	c, dt_sh_x
	and	1
	jp	z, dt_sh_m		; 6, 8: − a
	ex	de, hl
	ld	hl, (dt_a)
	add	hl, de
	jp	dt_sh_x
dt_sh_m:
	ex	de, hl
	ld	hl, (dt_a)
	call	dt_neg
	add	hl, de
dt_sh_x:
	ld	(dt_px), hl
	ld	hl, (dt_a)
	ld	a, (dt_kind)
	cp	2
	jp	z, dt_sh_y
	cp	7
	jp	nc, dt_sh_y
	call	dt_neg			; 1, 5, 6: y = ty − a
dt_sh_y:
	ex	de, hl
	ld	a, (dt_y)
	ld	l, a
	ld	h, 0
	add	hl, de
	ld	(dt_py), hl
	ret
dt_sh3:					; x = tx + a, y = ty − b
	ld	hl, (dt_a)
	jp	dt_sh34
dt_sh4:					; x = tx − a, y = ty − b
	ld	hl, (dt_a)
	call	dt_neg
dt_sh34:
	ex	de, hl
	ld	a, (dt_x)
	ld	l, a
	ld	h, 0
	add	hl, de
	ld	(dt_px), hl
	ld	hl, (dt_b)
	call	dt_neg
	jp	dt_sh_y

; HL = trunc(Random(dt_a + 10) − 5 − dt_a/2) к нулю
dt_half:
	ld	hl, (dt_a)
	ld	de, 10
	add	hl, de
	ex	de, hl
	call	random			; w
	ld	de, -5
	add	hl, de
	add	hl, hl			; 2(w − 5)
	ex	de, hl
	ld	hl, (dt_a)
	call	dt_neg
	add	hl, de			; 2(w − 5) − a
	ld	a, h
	or	a
	jp	m, dt_hf_n
	rra
	ld	h, a
	ld	a, l
	rra
	ld	l, a
	ret
dt_hf_n:
	call	dt_neg
	or	a
	ld	a, h
	rra
	ld	h, a
	ld	a, l
	rra
	ld	l, a
; HL = −HL
dt_neg:
	ld	a, l
	cpl
	ld	l, a
	ld	a, h
	cpl
	ld	h, a
	inc	hl
	ret
; HL = A·10
dt_mul10:
	ld	l, a
	ld	h, 0
	add	hl, hl
	ld	d, h
	ld	e, l
	add	hl, hl
	add	hl, hl
	add	hl, de
	ret

; CF = 1, если точка (dt_px, dt_py) вне поля
dt_infield:
	ld	hl, (dt_py)
	ld	de, DT_Y1
	call	fl_scmp
	cp	1
	jp	z, dt_if_out
	ld	hl, (dt_px)
	ld	de, DT_X0
	call	fl_scmp
	cp	0xFF
	jp	z, dt_if_out
	ld	hl, (dt_py)
	ld	de, DT_Y0
	call	fl_scmp
	cp	0xFF
	jp	z, dt_if_out
	ld	hl, (dt_px)
	ld	de, DT_X1
	call	fl_scmp
	cp	1
	jp	z, dt_if_out
	or	a
	ret
dt_if_out:
	scf
	ret
; один проход отражения внутрь поля
dt_reflect:
	ld	hl, (dt_px)
	ld	de, DT_X1
	call	fl_scmp
	cp	1
	jp	nz, dt_rf2
	ld	hl, (dt_px)
	call	dt_neg
	ld	de, 2 * DT_X1
	add	hl, de
	ld	(dt_px), hl
dt_rf2:
	ld	hl, (dt_py)
	ld	de, DT_Y1
	call	fl_scmp
	cp	1
	jp	nz, dt_rf3
	ld	hl, (dt_py)
	call	dt_neg
	ld	de, 2 * DT_Y1
	add	hl, de
	ld	(dt_py), hl
dt_rf3:
	ld	hl, (dt_py)
	ld	de, DT_Y0
	call	fl_scmp
	cp	0xFF
	jp	nz, dt_rf4
	ld	hl, (dt_py)
	call	dt_neg
	ld	de, 2 * DT_Y0
	add	hl, de
	ld	(dt_py), hl
dt_rf4:
	ld	hl, (dt_px)
	ld	de, DT_X0
	call	fl_scmp
	cp	0xFF
	ret	nz
	ld	hl, (dt_px)
	call	dt_neg
	ld	de, 2 * DT_X0
	add	hl, de
	ld	(dt_px), hl
	ret

; HL = адрес записи игрока с местом A (1..4)
dt_ptr:
	ld	hl, players
	ld	de, PL_SIZE
dt_ptr1:
	dec	a
	ret	z
	add	hl, de
	jp	dt_ptr1
; ячейки tb_* из записи игрока с местом A
dt_tb:
	ld	(tb_idx), a
	call	dt_ptr
	ld	a, (hl)
	ld	(tb_x), a
	inc	hl
	ld	a, (hl)
	ld	(tb_y), a
	inc	hl
	ld	a, (hl)
	ld	(tb_angle), a
	xor	a
	ld	(tb_angle + 1), a
	inc	hl
	ld	a, (hl)
	ld	(tb_facing), a
	ld	de, PL_ALIVE - PL_FACING
	add	hl, de
	ld	a, (hl)
	ld	(tb_alive), a
	ret
; стереть корпус и ствол игрока с местом A
erase_tb:
	call	dt_tb
	jp	erase_tank_barrel
; нарисовать всех живых
redraw_all:
	ld	a, 1
ra_lp:
	ld	(dt_ra), a
	call	dt_tb
	call	draw_tank_barrel
	ld	a, (n_players)
	ld	b, a
	ld	a, (dt_ra)
	cp	b
	ret	z
	inc	a
	jp	ra_lp

; Заменить цвет A на 0 по всему экрану, кроме точки (0, 0) — replaceColor() эталона. Идёт байтами по трём плоскостям.
replace_color:
	ld	(dt_rc), a
	ld	de, 0
	call	getpixel
	ld	(dt_rc0), a		; цвет точки (0, 0) — вернуть потом
	ld	a, (dt_rc)
	ld	c, 0xFF
	rra
	jp	nc, rc_1
	ld	c, 0
rc_1:
	ld	d, 0xFF
	rra
	jp	nc, rc_2
	ld	d, 0
rc_2:
	ld	e, 0xFF
	rra
	jp	nc, rc_3
	ld	e, 0
rc_3:
	ld	hl, 0xA000
rc_lp:
	ld	a, (hl)
	xor	c
	ld	b, a
	ld	a, h
	add	a, 0x20
	ld	h, a
	ld	a, (hl)
	xor	d
	and	b
	ld	b, a
	ld	a, h
	add	a, 0x20
	ld	h, a
	ld	a, (hl)
	xor	e
	and	b
	jp	z, rc_no
	cpl
	ld	b, a			; маска: что оставить
	and	(hl)
	ld	(hl), a
	ld	a, h
	sub	0x20
	ld	h, a
	ld	a, (hl)
	and	b
	ld	(hl), a
	ld	a, h
	sub	0x20
	ld	h, a
	ld	a, (hl)
	and	b
	ld	(hl), a
	jp	rc_nx
rc_no:
	ld	a, h
	sub	0x40
	ld	h, a
rc_nx:
	inc	hl
	ld	a, h
	cp	0xC0
	jp	nz, rc_lp
	ld	de, 0
	ld	a, (dt_rc0)
	jp	putpixel

death0:
death2:
	ret
death_end:

dt_variant:	db	0
dt_victim:	db	0
dt_wind:	dw	0
dt_xkill:	db	0
dt_vp:		dw	0
dt_hp:		dw	0
dt_x:		db	0
dt_y:		db	0
dt_cnt:		db	0
dt_j:		db	0
dt_i:		db	0
dt_m:		db	0
dt_n:		dw	0
dt_kind:	db	0
dt_mode:	db	0
dt_a:		dw	0
dt_b:		dw	0
dt_px:		dw	0
dt_py:		dw	0
dt_pt:		dw	0
dt_cur:		dw	0
dt_prev:	dw	0
dt_bp:		dw	0
dt_bq:		dw	0
dt_ra:		db	0
dt_rc:		db	0
dt_rc0:		db	0
dt_buf1:	ds	100
dt_buf2:	ds	100
