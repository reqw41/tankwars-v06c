; После выстрела — начало afterShot() эталона web/tankwars.js (PROFILE_V06C): перерисовка танков, осыпание, падение.
; Вход: n_players, players; as_crumble (байт, процент осыпания 0..100), as_fall (0/1 — танки падают),
;       as_rebound (0/1 — стены отражают); RandSeed в rand_seed.
; Задача Q5 (docs/tasks/Q5-after.md). Готовая часть — rnd_le_pct.

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

; after_shot: 1) перерисовать все танки со стволами; 2) если as_crumble > 0 — рамка и жребий осыпания;
; 3) если as_fall != 0 — рамка и спуск каждого висящего танка. Все вызовы портят AF, BC, DE, HL —
; счётчики, координаты и адрес записи храним в ячейках памяти.
; Ствол рисуем не draw_tank_barrel, а af_draw_tb (draw_tank + tb_ends + af_line): обход line()
; эталона шагает по АДРЕСУ o = (o±1/±256) mod 65536, и ствол с конца экрана переносится в
; начало следующей строки (случай #52 теста: (249,140)->(256,138) пишет точку (0,139));
; line на 8080 такие точки отсекает putpixel16.
after_shot:
	ld	a, 1
	ld	(af_i), a
af_redraw:
	call	af_last_chk
	jp	c, af_crumble		; i > n_players
	call	af_rec_addr
	call	af_fill_tb
	call	af_draw_tb
	ld	hl, af_i
	inc	(hl)
	jp	af_redraw
; 2. осыпание: draw_frame(rebound); если rnd_le_pct(as_crumble) — crumble
af_crumble:
	ld	a, (as_crumble)
	or	a
	jp	z, af_fall_chk
	ld	a, (as_rebound)
	call	draw_frame
	ld	a, (as_crumble)
	call	rnd_le_pct
	jp	nc, af_fall_chk
	call	crumble
; 3. падение
af_fall_chk:
	ld	a, (as_fall)
	or	a
	jp	z, af_done
	ld	a, (as_rebound)
	call	draw_frame
	ld	a, 1
	ld	(af_i), a
af_fall_loop:
	call	af_last_chk
	jp	c, af_done
	call	af_rec_addr
	ld	hl, (af_rec)
	ld	a, (hl)
	ld	(af_x), a
	inc	hl
	ld	a, (hl)
	ld	(af_y), a
	; falling = PL_ALIVE
	ld	hl, (af_rec)
	ld	de, PL_ALIVE
	add	hl, de
	ld	a, (hl)
	ld	(af_falling), a
	; есть опора под корпусом (хотя бы один dx из -3..3) — не падает
	ld	a, -3
	ld	(af_dx), a
af_chk3:
	call	af_sup_dx
	jp	nc, af_chk3_next
	xor	a
	ld	(af_falling), a
	jp	af_chk_side
af_chk3_next:
	ld	hl, af_dx
	inc	(hl)
	ld	a, (af_dx)
	cp	4
	jp	nz, af_chk3
af_chk_side:
	; sup(x-4,y) и sup(x+4,y) — не падает
	ld	a, -4
	ld	(af_dx), a
	call	af_sup_dx
	jp	nc, af_do_fall
	ld	a, 4
	ld	(af_dx), a
	call	af_sup_dx
	jp	nc, af_do_fall
	xor	a
	ld	(af_falling), a
af_do_fall:
	ld	a, (af_falling)
	or	a
	jp	z, af_not_falling
	; стереть ствол: линия цвета 0 от (x,y) до конца ствола
	call	af_fill_tb
	call	tb_ends
	xor	a
	ld	(ln_c), a
	call	af_line
	jp	af_drop
af_not_falling:
	call	af_fill_tb
	call	af_draw_tb
	jp	af_next
; цикл спуска одного танка
af_drop:
	; ox = x, oy = y
	ld	a, (af_x)
	ld	(af_ox), a
	ld	a, (af_y)
	ld	(af_oy), a
	; корпус в (ox, oy) цветом i + 3
	ld	a, (af_ox)
	ld	d, a
	ld	a, (af_oy)
	ld	e, a
	ld	a, (af_i)
	add	a, 3
	call	draw_tank
	; y = y + 1
	ld	hl, af_y
	inc	(hl)
	; sup(x+4,y) — шаг влево
	ld	a, 4
	ld	(af_dx), a
	call	af_sup_dx
	jp	nc, af_nox1
	ld	hl, af_x
	dec	(hl)
af_nox1:
	; sup(x-4,y) — шаг вправо (x уже мог измениться)
	ld	a, -4
	ld	(af_dx), a
	call	af_sup_dx
	jp	nc, af_nox2
	ld	hl, af_x
	inc	(hl)
af_nox2:
	; landed = все dx из -4..4 дают sup
	ld	a, 1
	ld	(af_landed), a
	ld	a, -4
	ld	(af_dx), a
af_land_lp:
	call	af_sup_dx
	jp	c, af_land_next
	xor	a
	ld	(af_landed), a
af_land_next:
	ld	hl, af_dx
	inc	(hl)
	ld	a, (af_dx)
	cp	5
	jp	nz, af_land_lp
	; урон: если PL_DAMP > 0 — damp - 1, иначе men -= Random(3) + 1
	ld	hl, (af_rec)
	ld	de, PL_DAMP
	add	hl, de
	ld	a, (hl)
	inc	hl
	or	(hl)
	inc	hl
	or	(hl)
	inc	hl
	or	(hl)
	jp	z, af_hit
	dec	hl
	dec	hl
	dec	hl			; hl = &PL_DAMP (младший байт)
	ld	a, (hl)
	sub	1
	ld	(hl), a
	inc	hl
	ld	a, (hl)
	sbc	a, 0
	ld	(hl), a
	inc	hl
	ld	a, (hl)
	sbc	a, 0
	ld	(hl), a
	inc	hl
	ld	a, (hl)
	sbc	a, 0
	ld	(hl), a
	jp	af_derp
af_hit:
	ld	de, 3
	call	random
	inc	hl			; r + 1 (1..3)
	push	hl
	ld	hl, (af_rec)
	ld	de, PL_MEN
	add	hl, de
	pop	de
	ld	a, (hl)
	sub	e
	ld	(hl), a
	inc	hl
	ld	a, (hl)
	sbc	a, d
	ld	(hl), a
af_derp:
	; стереть корпус в (ox, oy)
	ld	a, (af_ox)
	ld	d, a
	ld	a, (af_oy)
	ld	e, a
	call	erase_tank
	ld	a, (af_landed)
	or	a
	jp	z, af_drop
	; записать новые x, y в запись и дорисовать танк со стволом
	ld	hl, (af_rec)
	ld	a, (af_x)
	ld	(hl), a
	inc	hl
	ld	a, (af_y)
	ld	(hl), a
	call	af_fill_tb
	call	af_draw_tb
af_next:
	ld	hl, af_i
	inc	(hl)
	jp	af_fall_loop
af_done:
	ret
after_end:

; CF = 1, если af_i > n_players. Портит AF, E.
af_last_chk:
	ld	a, (af_i)
	ld	e, a
	ld	a, (n_players)
	cp	e
	ret

; af_rec = players + (af_i - 1) * PL_SIZE. Портит AF, BC, DE, HL.
af_rec_addr:
	ld	a, (af_i)
	dec	a
	ld	b, a
	ld	hl, 0
	ld	de, PL_SIZE
	or	a
	jp	z, af_ra_done
af_ra_lp:
	add	hl, de
	dec	b
	jp	nz, af_ra_lp
af_ra_done:
	ld	de, players
	add	hl, de
	ld	(af_rec), hl
	ret

; Заполнить tb_x, tb_y, tb_angle (слово), tb_facing, tb_idx, tb_alive из записи af_rec.
af_fill_tb:
	ld	hl, (af_rec)
	ld	a, (hl)			; PL_X
	ld	(tb_x), a
	inc	hl
	ld	a, (hl)			; PL_Y
	ld	(tb_y), a
	inc	hl
	ld	a, (hl)			; PL_ANGLE — слово со старшим 0
	ld	(tb_angle), a
	xor	a
	ld	(tb_angle + 1), a
	inc	hl
	ld	a, (hl)			; PL_FACING
	ld	(tb_facing), a
	ld	a, (af_i)
	ld	(tb_idx), a
	inc	hl
	inc	hl
	inc	hl
	inc	hl
	inc	hl			; PL_ALIVE
	ld	a, (hl)
	ld	(tb_alive), a
	ret

; drawTankBarrel эталона: мёртвый не рисуется; корпус цветом i + 3, затем ствол тем же цветом
; адресным обходом af_line (не draw_tank_barrel — тот теряет точки за краем экрана).
af_draw_tb:
	ld	a, (tb_alive)
	or	a
	ret	z
	ld	a, (tb_x)
	ld	d, a
	ld	a, (tb_y)
	ld	e, a
	ld	a, (tb_idx)
	add	a, 3
	call	draw_tank
	call	tb_ends
	ld	a, (tb_idx)
	add	a, 3
	ld	(ln_c), a
	jp	af_line

; sup(x + af_dx, af_y): цвет (x+dx, y+1) равен 1 или 2. Вход: af_x, af_dx (знаковый байт), af_y.
; Координаты вне 0..255 эталон читает как 0 (off16 с clip) — это не опора.
; Выход: CF = 1 если sup. Портит AF, BC, DE, HL.
af_sup_dx:
	ld	a, (af_x)
	ld	l, a
	ld	h, 0
	ld	a, (af_dx)
	ld	e, a
	rlca				; CY = знаковый бит dx
	sbc	a, a
	ld	d, a			; DE = знаковое расширение dx
	add	hl, de			; X = x + dx точно (-4..259)
	ld	a, h
	or	a
	jp	nz, af_sup_no		; X вне 0..255 — чтение 0
	ld	a, (af_y)
	inc	a
	jp	z, af_sup_no		; y + 1 = 256 — чтение 0
	ld	e, a
	ld	d, l
	call	getpixel
	cp	1
	jp	z, af_sup_yes
	cp	2
	jp	z, af_sup_yes
af_sup_no:
	xor	a
	ret
af_sup_yes:
	scf
	ret

; af_line — обход line() эталона точь-в-точь: шаг по адресу o = (o±1) или (o±256) mod 65536,
; точка пишется в (o mod 256, o / 256) цветом ln_c. Вход: ln_x1, ln_y1, ln_x2, ln_y2 (знаковые
; слова), ln_c. Старт вне 0..255 — как off16 с clip: o = 0x10000, первая точка не пишется,
; дальше адреса 1, 2, ... (в тесте не случается, воспроизведено на всякий случай). Портит всё.
af_line:
	xor	a
	ld	(af_clip), a
	ld	hl, (ln_x1)
	ex	de, hl
	ld	hl, (ln_x2)
	call	sub16			; cx = x2 - x1
	ld	a, h
	or	l
	jp	nz, af_l_notv
	; вертикаль: ya = min(y1,y2), yb = max(y1,y2), шаг +256
	ld	hl, (ln_y2)
	ex	de, hl			; de = y2
	ld	hl, (ln_y1)
	call	cmp16			; y1 против y2
	jp	c, af_l_y1lo
	ld	hl, (ln_y2)
	ld	(af_ya), hl
	ld	hl, (ln_y1)
	ld	(af_yb), hl
	jp	af_l_vgo
af_l_y1lo:
	ld	hl, (ln_y1)
	ld	(af_ya), hl
	ld	hl, (ln_y2)
	ld	(af_yb), hl
af_l_vgo:
	ld	hl, (af_ya)
	ex	de, hl			; de = ya
	ld	hl, (af_yb)
	call	sub16			; yb - ya + 1
	inc	hl
	ld	(af_cnt), hl
	ld	hl, (ln_x1)
	ld	a, (af_ya)
	ld	e, a
	ld	a, (af_ya + 1)
	ld	d, a
	call	af_l_off
af_l_vlp:
	ld	hl, (af_cnt)
	ld	a, h
	or	l
	jp	z, af_l_ret
	dec	hl
	ld	(af_cnt), hl
	call	af_l_put
	ld	hl, (af_o)
	ld	de, 256
	add	hl, de
	ld	(af_o), hl
	jp	af_l_vlp
af_l_notv:
	; cx < 0 — поменять точки местами (как эталон)
	ld	a, h
	and	0x80
	jp	z, af_l_cxpos
	ld	hl, (ln_x1)
	ld	(af_tmp), hl
	ld	hl, (ln_x2)
	ld	(ln_x1), hl
	ld	hl, (af_tmp)
	ld	(ln_x2), hl
	ld	hl, (ln_y1)
	ld	(af_tmp), hl
	ld	hl, (ln_y2)
	ld	(ln_y1), hl
	ld	hl, (af_tmp)
	ld	(ln_y2), hl
	ld	hl, (ln_x1)
	ex	de, hl
	ld	hl, (ln_x2)
	call	sub16
af_l_cxpos:
	ld	(af_cx), hl
	; bx = y2 - y1
	ld	hl, (ln_y1)
	ex	de, hl
	ld	hl, (ln_y2)
	call	sub16
	ld	a, h
	or	l
	jp	nz, af_l_noth
	; горизонталь: o = off16(x1,y1), шаг +1
	ld	hl, (af_cx)
	inc	hl
	ld	(af_cnt), hl
	ld	hl, (ln_x1)
	ld	a, (ln_y1)
	ld	e, a
	ld	a, (ln_y1 + 1)
	ld	d, a
	call	af_l_off
af_l_hlp:
	ld	hl, (af_cnt)
	ld	a, h
	or	l
	jp	z, af_l_ret
	dec	hl
	ld	(af_cnt), hl
	call	af_l_put
	ld	hl, (af_o)
	inc	hl
	ld	(af_o), hl
	jp	af_l_hlp
af_l_noth:
	; шаг по y: +256 или -256
	ld	a, h
	and	0x80
	jp	z, af_l_bxpos
	ld	a, 0xFF
	ld	(af_stephi), a		; шаг -256
	call	neg16
	jp	af_l_bxgot
af_l_bxpos:
	ld	a, 1
	ld	(af_stephi), a		; шаг +256
af_l_bxgot:
	ld	(af_bx), hl
	; ymajor = bx > cx
	xor	a
	ld	(af_ymaj), a
	ld	hl, (af_cx)
	ex	de, hl			; de = cx
	ld	hl, (af_bx)
	call	cmp16
	jp	c, af_l_prep
	jp	z, af_l_prep
	ld	a, 1
	ld	(af_ymaj), a
	ld	hl, (af_bx)
	ld	(af_tmp), hl
	ld	hl, (af_cx)
	ld	(af_bx), hl
	ld	hl, (af_tmp)
	ld	(af_cx), hl
af_l_prep:
	; d2 = 2bx; err = d2 - cx; d22 = d2 - 2cx; cnt = cx + 1; o = off16(x1,y1)
	ld	hl, (af_bx)
	add	hl, hl
	ld	(af_d2), hl
	ld	a, (af_cx)
	ld	e, a
	ld	a, (af_cx + 1)
	ld	d, a
	ld	hl, (af_d2)
	call	sub16			; err = d2 - cx
	ld	(af_err), hl
	ld	hl, (af_cx)
	add	hl, hl
	ex	de, hl
	ld	hl, (af_d2)
	call	sub16
	ld	(af_d22), hl
	ld	hl, (af_cx)
	inc	hl
	ld	(af_cnt), hl
	ld	hl, (ln_x1)
	ld	a, (ln_y1)
	ld	e, a
	ld	a, (ln_y1 + 1)
	ld	d, a
	call	af_l_off
af_l_lp:
	ld	hl, (af_cnt)
	ld	a, h
	or	l
	jp	z, af_l_ret
	dec	hl
	ld	(af_cnt), hl
	call	af_l_put
	ld	hl, (af_o)
	inc	hl
	ld	(af_o), hl
	ld	a, (af_ymaj)
	or	a
	jp	nz, af_l_ym
	; x-ведущая: err < 0 -> err += d2; иначе err += d22 и o += шаг
	ld	hl, (af_err)
	ld	a, h
	and	0x80
	jp	z, af_l_xge
	ld	a, (af_d2)
	ld	e, a
	ld	a, (af_d2 + 1)
	ld	d, a
	add	hl, de
	ld	(af_err), hl
	jp	af_l_lp
af_l_xge:
	ld	a, (af_d22)
	ld	e, a
	ld	a, (af_d22 + 1)
	ld	d, a
	add	hl, de
	ld	(af_err), hl
	ld	hl, (af_o)
	ld	a, (af_stephi)
	ld	d, a
	ld	e, 0
	add	hl, de
	ld	(af_o), hl
	jp	af_l_lp
af_l_ym:
	; y-ведущая: o += шаг; err < 0 -> err += d2, o -= 1; иначе err += d22
	ld	hl, (af_o)
	ld	a, (af_stephi)
	ld	d, a
	ld	e, 0
	add	hl, de
	ld	(af_o), hl
	ld	hl, (af_err)
	ld	a, h
	and	0x80
	jp	z, af_l_ymge
	ld	a, (af_d2)
	ld	e, a
	ld	a, (af_d2 + 1)
	ld	d, a
	add	hl, de
	ld	(af_err), hl
	ld	hl, (af_o)
	dec	hl
	ld	(af_o), hl
	jp	af_l_lp
af_l_ymge:
	ld	a, (af_d22)
	ld	e, a
	ld	a, (af_d22 + 1)
	ld	d, a
	add	hl, de
	ld	(af_err), hl
	jp	af_l_lp
af_l_ret:
	ret

; o = (y mod 256)*256 + (x mod 256); вне 0..255 — как off16 с clip: o = 0x10000,
; храним 0 и af_clip != 0 (первая запись пропускается). Вход: HL = x, DE = y.
af_l_off:
	ld	a, h
	or	d
	ld	(af_clip), a
	ld	a, e
	ld	h, a			; o = (y mod 256)*256 + x; младший байт o — это l = x
	ld	a, (af_clip)
	or	a
	jp	z, af_lo_ok
	ld	hl, 0
af_lo_ok:
	ld	(af_o), hl
	ret

; нарисовать точку адреса af_o цветом ln_c
af_l_put:
	ld	a, (af_clip)
	or	a
	jp	z, af_l_p0
	xor	a
	ld	(af_clip), a		; «клипнутый» старт: первая точка не пишется
	ret
af_l_p0:
	ld	hl, (af_o)
	ld	d, l
	ld	e, h
	ld	a, (ln_c)
	jp	putpixel

as_crumble:	db	0
as_fall:	db	0
as_rebound:	db	0
as_pct:		db	0
af_i:		db	0
af_x:		db	0
af_y:		db	0
af_ox:		db	0
af_oy:		db	0
af_dx:		db	0
af_falling:	db	0
af_landed:	db	0
af_rec:		dw	0
af_cx:		dw	0
af_bx:		dw	0
af_err:		dw	0
af_d2:		dw	0
af_d22:		dw	0
af_o:		dw	0
af_cnt:		dw	0
af_ya:		dw	0
af_yb:		dw	0
af_tmp:		dw	0
af_stephi:	db	0
af_ymaj:	db	0
af_clip:	db	0
