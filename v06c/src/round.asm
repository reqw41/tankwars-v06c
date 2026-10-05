; Начало раунда — roundStart() эталона web/tankwars.js (PROFILE_V06C).
; Вход: n_players (match.asm), rs_walls (0 — стены обычные, 1 — случайно, 2 — отражают), rs_windmode (0..5),
;       RandSeed в rand_seed, записи игроков в players.
; Выход: rs_rebound (0/1), rs_first (0..n-1), rs_wind (слово со знаком); в записях игроков заполнены
;        PL_X, PL_Y, PL_ANGLE, PL_FACING, PL_POWER = 200, PL_MEN = 100, PL_ALIVE = 1, PL_AI_N = 0; экран раунда нарисован.
; Порядок вызовов случайных чисел — как в эталоне: rnd_hi на rebound, gen_terrain, place_tanks,
; Random(n) на первого, Random(5) только при режиме 5, Random(span) всегда, 4 × rnd_hi на шквал.
; Все вызываемые подпрограммы портят AF, BC, DE, HL — счётчики и значения храним в ячейках памяти.

round_start:
	call	cr_mark_all		; новый экран: осыпанию смотреть всё
	; 1. rebound = (r < 32768), r = rnd_hi() — ВСЕГДА; стены 0 → 0, стены 2 → 1
	call	rnd_hi
	ld	a, h
	and	0x80
	jp	nz, rs_rb0
	ld	a, 1
	jp	rs_rb_set
rs_rb0:	xor	a
rs_rb_set:
	ld	(rs_rebound), a
	ld	a, (rs_walls)
	or	a
	jp	nz, rs_rb_w2
	xor	a
	ld	(rs_rebound), a
	jp	rs_rb_done
rs_rb_w2:
	cp	2
	jp	nz, rs_rb_done
	ld	a, 1
	ld	(rs_rebound), a
rs_rb_done:
	; 2..5. экран раунда: очистка, рамка (rebound=1 как в drawBackground(0)), рельеф
	call	clear_screen
	ld	a, 1
	call	draw_frame
	ld	a, (n_players)
	call	gen_terrain
	call	render_terrain
	; 5b. правка под эталон: renderTerrain рисует столбцы с top >= 253 строками 252..top
	; (min/max с Y1=252), а render_terrain их пропускает — дорисовать землёй (цвет 1).
	; Порядок случайных чисел не меняется: putpixel их не берёт.
	xor	a
	ld	(rs_fx), a
rs_fix:
	ld	a, (rs_fx)
	ld	e, a
	ld	d, 0
	ld	hl, terr_top
	add	hl, de
	ld	a, (hl)
	cp	0xFF
	jp	z, rs_fx_next
	cp	253
	jp	c, rs_fx_next		; top < 253 — уже нарисовано render_terrain
	ld	(rs_ftop), a
	ld	a, 252
	ld	(rs_fy), a
rs_frow:
	ld	a, (rs_fx)
	ld	d, a
	ld	a, (rs_fy)
	ld	e, a
	ld	a, 1
	call	putpixel
	ld	hl, rs_fy
	inc	(hl)
	ld	a, (rs_fy)
	ld	hl, rs_ftop
	cp	(hl)
	jp	c, rs_frow
rs_fx_next:
	ld	hl, rs_fx
	inc	(hl)
	ld	a, (rs_fx)
	or	a
	jp	nz, rs_fix
	; 6. расстановка танков
	ld	a, (rs_rebound)
	ld	(pl_rebound), a
	ld	a, (n_players)
	call	place_tanks
	; 7. запись игрока i (место i = запись i-1 в players)
	ld	a, (n_players)
	ld	(rs_i), a
rs_ploop:
	ld	a, (rs_i)
	or	a
	jp	z, rs_pdone
	dec	a
	ld	(rs_i), a		; rs_i = i-1 = 0..n-1
	; HL = players + (i-1)*108 (сложением, 108 = не степень двух)
	ld	b, a
	ld	hl, 0
	ld	de, PL_SIZE
	ld	a, b
	or	a
	jp	z, rs_mdone
rs_mul:	add	hl, de
	dec	b
	jp	nz, rs_mul
rs_mdone:
	ld	de, players
	add	hl, de
	ld	(rs_rec), hl
	; PL_X = tk_x[i-1]
	ld	a, (rs_i)
	ld	e, a
	ld	d, 0
	ld	hl, tk_x
	add	hl, de
	ld	a, (hl)
	ld	hl, (rs_rec)
	ld	(hl), a		; PL_X
	; PL_Y = tk_y[i-1]
	ld	a, (rs_i)
	ld	e, a
	ld	d, 0
	ld	hl, tk_y
	add	hl, de
	ld	a, (hl)
	ld	hl, (rs_rec)
	ld	de, PL_Y
	add	hl, de
	ld	(hl), a
	; PL_ANGLE = tk_angle[i-1]
	ld	a, (rs_i)
	ld	e, a
	ld	d, 0
	ld	hl, tk_angle
	add	hl, de
	ld	a, (hl)
	ld	hl, (rs_rec)
	ld	de, PL_ANGLE
	add	hl, de
	ld	(hl), a
	; PL_FACING = tk_facing[i-1]
	ld	a, (rs_i)
	ld	e, a
	ld	d, 0
	ld	hl, tk_facing
	add	hl, de
	ld	a, (hl)
	ld	hl, (rs_rec)
	ld	de, PL_FACING
	add	hl, de
	ld	(hl), a
	; PL_POWER = 200, PL_MEN = 100 (слова), PL_ALIVE = 1
	ld	hl, (rs_rec)
	ld	de, PL_POWER
	add	hl, de
	ld	(hl), 200
	inc	hl
	ld	(hl), 0
	ld	hl, (rs_rec)
	ld	de, PL_MEN
	add	hl, de
	ld	(hl), 100
	inc	hl
	ld	(hl), 0
	ld	hl, (rs_rec)
	ld	de, PL_ALIVE
	add	hl, de
	ld	(hl), 1
	; PL_AI_N = 0
	ld	de, PL_AI_N - PL_ALIVE
	add	hl, de
	ld	(hl), 0
	jp	rs_ploop
rs_pdone:
	; 8. rs_first = Random(n)
	ld	a, (n_players)
	ld	e, a
	ld	d, 0
	call	random
	ld	a, l
	ld	(rs_first), a
	; 9. ветер
	call	rs_wind_calc
	ret

; generateWind: eff = (mode == 5) ? Random(5) : mode; span = SPANS[eff];
; w = span/2 - Random(span) (16 бит, со знаком); 4 × rnd_hi с порогами 6554,6554,3277,3277: w = w·4 (16 бит);
; клампы ±30000. Портит AF, BC, DE, HL.
rs_wind_calc:
	ld	a, (rs_windmode)
	ld	(rs_mode), a
	cp	5
	jp	nz, rs_weff
	ld	de, 5
	call	random
	ld	a, l
	ld	(rs_mode), a
rs_weff:
	; span = rs_spans[eff]
	ld	a, (rs_mode)
	ld	e, a
	ld	d, 0
	ld	hl, rs_spans
	add	hl, de
	add	hl, de
	ld	a, (hl)
	inc	hl
	ld	h, (hl)
	ld	l, a
	ld	(rs_span), hl
	; r = Random(span) — ВСЕГДА, при span = 0 даёт 0, но шаг генератора делает
	ex	de, hl		; DE = span
	call	random
	ld	(rs_r), hl
	; half = span >> 1 (span чётное)
	ld	hl, (rs_span)
	or	a			; CY = 0
	ld	a, h
	rra
	ld	h, a
	ld	a, l
	rra
	ld	l, a		; HL = half
	ld	(rs_half), hl
	; w = half - r (слово со знаком, переполнение отбрасывается)
	ld	hl, (rs_r)
	ex	de, hl		; DE = r
	ld	hl, (rs_half)
	ld	a, l
	sub	e
	ld	l, a
	ld	a, h
	sbc	a, d
	ld	h, a
	ld	(rs_w), hl
rs_wcont:
	; пороги шквала: 4 × rnd_hi, если t < порог: w = w·4 (16 бит)
	ld	hl, rs_th
	ld	(rs_tp), hl
	ld	a, 4
	ld	(rs_wc), a
rs_wl:
	ld	hl, (rs_tp)
	ld	a, (hl)
	ld	(rs_thv), a
	inc	hl
	ld	a, (hl)
	ld	(rs_thv + 1), a
	inc	hl
	ld	(rs_tp), hl
	call	rnd_hi		; HL = t (DE портится — сравнение только через A/B)
	ld	a, (rs_thv + 1)
	cp	h
	jp	c, rs_wnext		; порог_ст < t_ст → t >= порог
	jp	nz, rs_wmul		; порог_ст > t_ст → t < порог
	ld	a, (rs_thv)
	cp	l
	jp	c, rs_wnext		; порог_мл < t_мл → t >= порог
	jp	nz, rs_wmul		; t < порог
	jp	rs_wnext
rs_wmul:
	ld	hl, (rs_w)
	add	hl, hl
	add	hl, hl		; w·4, старшие биты отбрасываются
	ld	(rs_w), hl
rs_wnext:
	ld	a, (rs_wc)
	dec	a
	ld	(rs_wc), a
	jp	nz, rs_wl
	; клампы: w > 30000 → 30000; w < -30000 → -30000
	ld	hl, (rs_w)
	ld	a, h
	or	a
	jp	m, rs_wlo		; отрицательное — верхний кламп не нужен
	cp	0x75		; 30000 = 7530h
	jp	c, rs_wstore		; w < 30000
	jp	nz, rs_whi
	ld	a, l
	cp	0x31
	jp	c, rs_wstore		; w <= 30000
rs_whi:	ld	hl, 30000
	jp	rs_wstore
rs_wlo:
	cp	0x8A		; -30000 = 8AC0h; беззнаковое HL < 8AC0h = w < -30000
	jp	c, rs_wclamplo
	jp	nz, rs_wstore
	ld	a, l
	cp	0xC0
	jp	c, rs_wclamplo
	jp	rs_wstore
rs_wclamplo:
	ld	hl, 0x8AC0		; -30000
rs_wstore:
	ld	(rs_wind), hl
	ret

round_end:

rs_walls:	db	0
rs_windmode:	db	0
rs_rebound:	db	0
rs_first:	db	0
rs_wind:	dw	0

; --- рабочие ячейки и таблицы ---
rs_i:		db	0
rs_rec:		dw	0
rs_fx:		db	0
rs_fy:		db	0
rs_ftop:	db	0
rs_mode:	db	0
rs_span:	dw	0
rs_r:		dw	0
rs_half:	dw	0
rs_w:		dw	0
rs_wc:		db	0
rs_tp:		dw	0
rs_thv:		dw	0
rs_spans:	dw	0, 20, 100, 300, 4000
rs_th:		dw	6554, 6554, 3277, 3277
