; Гибель танка — death() эталона web/tankwars.js (PROFILE_V06C), семь вариантов.
; Вход: dt_variant (0..6), dt_victim (место 1..n; его PL_ALIVE уже 0), dt_wind (слово), dt_xkill (0/1);
;       n_players, players, RandSeed.
; Варианты: 0 — обломки по одному, 2 — обломки разом, 1 и 3 — искры, 4 — фонтан земли, 5 — исчез, 6 — серия взрывов.

DT_X0		equ	3
DT_X1		equ	252
DT_Y0		equ	27
DT_Y1		equ	252

death:
	call	cr_mark_all		; гибель меняет экран где угодно
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
	; Обход по плоскости C000: байт без подходящих битов (небо и земля для цвета 3 — всегда) пропускается сразу.
	ld	hl, 0xC000
rc_lp:
	ld	a, (hl)
	xor	d
	jp	z, rc_nx
	ld	b, a
	ld	a, h
	sub	0x20
	ld	h, a
	ld	a, (hl)			; A000
	xor	c
	and	b
	ld	b, a
	ld	a, h
	add	a, 0x40
	ld	h, a
	ld	a, (hl)			; E000
	xor	e
	and	b
	jp	z, rc_no
	cpl
	ld	b, a			; маска: что оставить
	and	(hl)
	ld	(hl), a
	ld	a, h
	sub	0x40
	ld	h, a
	ld	a, (hl)
	and	b
	ld	(hl), a
	ld	a, h
	add	a, 0x20
	ld	h, a
	ld	a, (hl)
	and	b
	ld	(hl), a
	jp	rc_nx
rc_no:
	ld	a, h
	sub	0x20
	ld	h, a
rc_nx:
	inc	hl
	ld	a, h
	cp	0xE0
	jp	nz, rc_lp
	ld	de, 0
	ld	a, (dt_rc0)
	jp	putpixel

; ===== варианты 0 и 2: обломки =====
; Обломок: X, Y, VX, VY (Q16.16, координаты во вьюпорте поля). Шаг: X += VX; Y += VY; VY += 0.007; VX += ветер/5000.

; --- 0: одиннадцать обломков по очереди, каждый кончается вспышкой ---
death0:
	call	dt_frag_setup
	ld	a, 11
d0_f:
	ld	(dt_cnt), a
	call	dt_frag_new
d0_s:
	call	dt_frag_step		; A = цвет под обломком, dt_px/dt_py
	ld	b, 0			; done
	cp	1
	jp	z, d0_d1
	cp	2
	jp	nz, d0_t
d0_d1:
	ld	b, 1
d0_t:
	ld	c, a
	ld	a, b
	ld	(dt_done), a
	ld	a, c
	ld	de, 5
	call	dt_frag_tank		; CF = 1 — упёрся в щит
	jp	nc, d0_b
	ld	a, 1
	ld	(dt_done), a
d0_b:	; py < 0, py > 256, px < 0, px > 256
	ld	hl, (dt_py)
	ld	de, 256
	call	dt_range
	jp	c, d0_d2
	ld	hl, (dt_px)
	ld	de, 256
	call	dt_range
	jp	nc, d0_p
d0_d2:
	ld	a, 1
	ld	(dt_done), a
d0_p:
	call	dt_frag_put
	ld	a, (dt_done)
	or	a
	jp	z, d0_s
	xor	a
	call	dt_blast
	ld	a, (dt_cnt)
	dec	a
	jp	nz, d0_f
	jp	dt_outro

; --- 2: одиннадцать обломков разом, вспышки потом ---
death2:
	call	dt_frag_setup
	ld	hl, dt_frags
	ld	a, 11
d2_n:
	ld	(dt_cnt), a
	push	hl
	call	dt_frag_new
	pop	hl
	ld	de, dt_f
	ld	b, 16
	call	fx_copy
	ld	(hl), 0			; dead
	ld	de, 5
	add	hl, de
	ld	a, (dt_cnt)
	dec	a
	jp	nz, d2_n
d2_pass:
	xor	a
	ld	(dt_any), a
	ld	hl, dt_frags
	ld	a, 11
d2_f:
	ld	(dt_cnt), a
	ld	(dt_fp), hl
	ld	de, 16
	add	hl, de
	ld	a, (hl)
	or	a
	jp	nz, d2_nx		; уже остановился
	ld	hl, dt_f
	ex	de, hl
	ld	hl, (dt_fp)
	ex	de, hl
	ld	b, 16
	call	fx_copy			; запись -> рабочая копия
	call	dt_frag_step
	ld	b, a
	ld	a, 1
	ld	(dt_any), a
	xor	a
	ld	(dt_done), a
	ld	a, b
	cp	1
	jp	z, d2_d1
	cp	2
	jp	nz, d2_t
d2_d1:
	ld	a, 1
	ld	(dt_done), a
	ld	a, b
d2_t:
	ld	de, 10
	call	dt_frag_tank
	jp	nc, d2_b
	ld	a, 1
	ld	(dt_done), a
d2_b:	; py < 0, py > Y1 − Y0, px < 0, px > X1 − X0
	ld	hl, (dt_py)
	ld	de, DT_Y1 - DT_Y0
	call	dt_range
	jp	c, d2_d2
	ld	hl, (dt_px)
	ld	de, DT_X1 - DT_X0
	call	dt_range
	jp	nc, d2_p
d2_d2:
	ld	a, 1
	ld	(dt_done), a
d2_p:
	call	dt_frag_put
	ld	hl, (dt_fp)		; рабочая копия -> запись
	ld	de, dt_f
	ld	b, 16
	call	fx_copy
	ld	a, (dt_done)
	or	a
	jp	z, d2_nx
	ld	(hl), a			; dead = 1, конечная точка
	inc	hl
	ld	a, (dt_px)
	ld	(hl), a
	inc	hl
	ld	a, (dt_px + 1)
	ld	(hl), a
	inc	hl
	ld	a, (dt_py)
	ld	(hl), a
	inc	hl
	ld	a, (dt_py + 1)
	ld	(hl), a
d2_nx:
	ld	hl, (dt_fp)
	ld	de, 21
	add	hl, de
	ld	a, (dt_cnt)
	dec	a
	jp	nz, d2_f
	ld	a, (dt_any)
	or	a
	jp	nz, d2_pass
	; вспышки в точках остановки
	ld	hl, dt_frags + 17
	ld	a, 11
d2_bl:
	ld	(dt_cnt), a
	ld	e, (hl)
	inc	hl
	ld	d, (hl)
	inc	hl
	ex	de, hl
	ld	(dt_px), hl
	ex	de, hl
	ld	e, (hl)
	inc	hl
	ld	d, (hl)
	ex	de, hl
	ld	(dt_py), hl
	ex	de, hl
	ld	de, 18
	add	hl, de
	push	hl
	ld	a, 1
	call	dt_blast
	pop	hl
	ld	a, (dt_cnt)
	dec	a
	jp	nz, d2_bl
	jp	dt_outro

; общее начало: 54 случайных числа, ветер/5000, координаты танка во вьюпорте
dt_frag_setup:
	ld	a, 54
	call	dt_burn
	ld	hl, 0
	ld	(fx_a), hl
	ld	hl, (dt_wind)
	ld	(fx_a + 2), hl
	ld	de, 5000
	call	fx_idiv
	ld	hl, dt_wq
	ld	de, fx_a
	ld	b, 4
	jp	fx_copy
; A раз взять Random(65535)
dt_burn:
	ld	(dt_bn), a
dt_burn1:
	ld	de, 0xFFFF
	call	random
	ld	a, (dt_bn)
	dec	a
	ld	(dt_bn), a
	jp	nz, dt_burn1
	ret
; новый обломок в рабочей копии dt_f: X = tx, Y = ty, VX = 0.5 − Random, VY = 0.1 − Random
dt_frag_new:
	ld	hl, 0
	ld	(dt_f), hl
	ld	(dt_f + 4), hl
	ld	a, (dt_x)
	sub	DT_X0
	ld	l, a
	ld	(dt_f + 2), hl
	ld	a, (dt_y)
	sub	DT_Y0
	ld	l, a
	ld	(dt_f + 6), hl
	call	rnd_hi
	ld	de, dt_f + 8
	ld	bc, 32768
	call	dt_vel
	call	rnd_hi
	ld	de, dt_f + 12
	ld	bc, 6554
; (DE) = BC − HL, 32 бита со знаком
dt_vel:
	ld	a, c
	sub	l
	ld	(de), a
	inc	de
	ld	a, b
	sbc	a, h
	ld	(de), a
	inc	de
	ld	a, 0
	sbc	a, 0
	ld	(de), a
	inc	de
	ld	(de), a
	ret
; шаг обломка; на выходе dt_px, dt_py (вьюпорт, слова) и A = цвет точки под ним (0 за экраном)
dt_frag_step:
	ld	hl, dt_f
	ld	de, dt_f + 8
	ld	b, 4
	call	fx_addm			; X += VX
	ld	hl, dt_f + 4
	ld	de, dt_f + 12
	ld	b, 4
	call	fx_addm			; Y += VY
	ld	hl, dt_f + 12		; VY += 459
	ld	a, (hl)
	add	a, 459 & 255
	ld	(hl), a
	inc	hl
	ld	a, (hl)
	adc	a, 459 >> 8
	ld	(hl), a
	inc	hl
	ld	a, (hl)
	adc	a, 0
	ld	(hl), a
	inc	hl
	ld	a, (hl)
	adc	a, 0
	ld	(hl), a
	ld	hl, dt_f + 8		; VX += ветер/5000
	ld	de, dt_wq
	ld	b, 4
	call	fx_addm
	ld	hl, fx_a
	ld	de, dt_f
	ld	b, 4
	call	fx_copy
	call	fx_trunc
	ld	(dt_px), hl
	ld	hl, fx_a
	ld	de, dt_f + 4
	ld	b, 4
	call	fx_copy
	call	fx_trunc
	ld	(dt_py), hl
	; цвет точки (px + X0, py + Y0), если она на экране
	ld	hl, (dt_px)
	ld	de, DT_X0
	add	hl, de
	ld	a, h
	or	a
	jp	nz, dt_fs0
	ld	b, l
	ld	hl, (dt_py)
	ld	de, DT_Y0
	add	hl, de
	ld	a, h
	or	a
	jp	nz, dt_fs0
	ld	d, b
	ld	e, l
	jp	getpixel
dt_fs0:
	xor	a
	ret
; обломок над танком: A = цвет, DE = добавка к урону (5 или 10). CF = 1 — у танка щит (обломок останавливается);
; иначе при включённом xkill танк теряет Random(10) + добавка.
dt_frag_tank:
	cp	4
	jp	c, dt_ft0
	sub	3
	ld	b, a
	ld	a, (dt_xkill)
	or	a
	jp	z, dt_ft0
	ld	a, (n_players)
	cp	b
	jp	c, dt_ft0
	ld	a, b
	push	de
	call	dt_ptr
	ld	(dt_hp), hl
	call	dt_shield_pos
	pop	de
	ret	c
	push	de
	ld	de, 10
	call	random
	pop	de
	add	hl, de
	ex	de, hl
	call	dt_hurt
dt_ft0:
	or	a
	ret
; CF = 1, если HL < 0 или HL > DE (слова со знаком)
dt_range:
	ld	a, h
	or	a
	scf
	ret	m
	call	fl_scmp
	cp	1
	scf
	ret	z
	or	a
	ret
; точка обломка цветом жертвы, если она в поле
dt_frag_put:
	ld	hl, (dt_px)
	ld	de, DT_X0
	add	hl, de
	ld	a, h
	or	a
	ret	nz
	ld	a, l
	cp	DT_X0
	ret	c
	cp	DT_X1 + 1
	ret	nc
	ld	b, a
	ld	hl, (dt_py)
	ld	de, DT_Y0
	add	hl, de
	ld	a, h
	or	a
	ret	nz
	ld	a, l
	cp	DT_Y0
	ret	c
	cp	DT_Y1 + 1
	ret	nc
	ld	d, b
	ld	e, a
	ld	a, (dt_victim)
	add	a, 3
	jp	putpixel
; вспышка в точке (dt_px, dt_py): круг радиуса 4k в двух центрах, огонь и стирание. A = 1 — с лишними случайными числами.
dt_blast:
	ld	(dt_c0), a
	ld	de, 3
	call	random			; оттенок: число берётся, цвет один
	ld	de, 10
	call	random
	ld	a, l
	ld	b, 4
	cp	3
	jp	c, dt_bk
	ld	b, 8
	cp	6
	jp	c, dt_bk
	ld	b, 12
	cp	8
	jp	c, dt_bk
	ld	b, 16
	jp	z, dt_bk
	ld	b, 20
dt_bk:
	ld	a, b
	ld	(dk_r), a
	call	dt_blast_rnd
	ld	hl, (dt_px)
	ld	de, DT_X0
	add	hl, de
	ld	(dk_x), hl
	ld	hl, (dt_py)
	ld	de, DT_Y0
	add	hl, de
	ld	(dk_y), hl
	xor	a
	ld	(dk_el), a
	inc	a
	ld	(dk_er), a
	ld	a, 3
	ld	(dk_c), a
	call	disc
	call	dt_blast_rnd
	xor	a
	ld	(dk_c), a
	jp	disc
; при dt_c0 = 1: (радиус + 1) раз Random(65535)
dt_blast_rnd:
	ld	a, (dt_c0)
	or	a
	ret	z
	ld	a, (dk_r)
	inc	a
	jp	dt_burn
; общий конец вариантов 0 и 2
dt_outro:
	ld	a, 150
	call	dt_burn
	ld	a, 45
dt_o1:
	ld	(dt_bn), a
	ld	de, 63
	call	random
	ld	a, (dt_bn)
	dec	a
	jp	nz, dt_o1
	ld	a, (dt_x)
	ld	l, a
	ld	h, 0
	ld	(dk_x), hl
	ld	a, (dt_y)
	ld	l, a
	ld	(dk_y), hl
	xor	a
	ld	(dk_el), a
	inc	a
	ld	(dk_er), a
	ld	a, 30
	ld	(dk_r), a
	ld	a, 3
	ld	(dk_c), a
	call	disc
	xor	a
	ld	(dk_c), a
	call	disc
	call	redraw_all
	ld	a, (dt_victim)
	add	a, 3
	call	replace_color
	ld	a, 3
	jp	replace_color
death_end:

dt_f:		ds	16
dt_wq:		ds	4
dt_frags:	ds	11 * 21
dt_fp:		dw	0
dt_done:	db	0
dt_any:		db	0
dt_bn:		db	0
dt_c0:		db	0

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
