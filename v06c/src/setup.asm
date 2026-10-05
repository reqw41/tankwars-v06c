; Экран настройки матча (только игра): число игроков, кто на каком месте, число раундов и правила.
; Пункты: 0 — ИГРОКОВ, 1..4 — игроки, 5 — РАУНДОВ, 6 — ОТСКОК (стены), 7 — ВЕТЕР, 8 — ОСЫПАНИЕ, 9 — ПАДЕНИЕ танков,
; 10 — ОБЛОМКИ (взрыв танка ранит соседей), 11 — НАЧАТЬ, 12 — ПОМОЩЬ (экран с клавишами). Клавиши: вверх/вниз — пункт, влево/вправо — значение
; (по кругу), пробел или ВК — начать матч. Настройки — g_n, g_types, g_rounds, g_walls, g_windmode, g_crumble,
; g_fall, g_xkill (game.asm); курсор изначально на НАЧАТЬ. Перерисовывается только изменившаяся строка.
ST_NITEMS	equ	13
ST_START	equ	11
ST_HELP		equ	12
ST_COL		equ	4		; столбец подписи
ST_VCOL		equ	14		; столбец значения

setup:
	call	clear_screen
	ld	a, 1
	call	gm_scene
	; палитра: цвета мест при полном здоровье — имена игроков цветом своих танков
	ld	a, MAX_PLAYERS
	ld	(n_players), a
	xor	a
st_pl:
	ld	(gm_i), a
	inc	a
	call	dt_ptr
	ld	(gm_p), hl
	ld	de, PL_MEN
	add	hl, de
	ld	(hl), 100
	inc	hl
	ld	(hl), 0
	call	gnp_colors
	ld	a, (gm_i)
	inc	a
	cp	MAX_PLAYERS
	jp	nz, st_pl
	call	gm_pal
	ld	de, s_gtitle
	ld	hl, 0x0B02
	ld	bc, 0x0902
	call	gm_text
	ld	de, s_help
	ld	hl, 0x011A
	ld	bc, 0x1D02
	call	gm_text
	ld	a, ST_START
	ld	(st_cur), a
	xor	a
st_all:
	push	af
	call	st_item
	pop	af
	inc	a
	cp	ST_NITEMS
	jp	nz, st_all
st_key:
	xor	a
	ld	(g_phase), a
	call	get_key
	cp	5
	jp	z, st_fire
	cp	3
	jp	z, st_down
	cp	4
	jp	z, st_up
	ld	c, 1
	cp	2
	jp	z, st_chg
	ld	c, 0xFF
	cp	1
	jp	nz, st_key
st_chg:
	ld	a, (st_cur)
	cp	ST_START
	jp	nc, st_key
	or	a
	jp	z, st_c_opt
	cp	5
	jp	nc, st_c_opt
	; тип игрока: 0..7 по кругу
	ld	e, a
	ld	d, 0
	ld	hl, g_types - 1
	add	hl, de
	ld	a, (hl)
	add	a, c
	and	7
	ld	(hl), a
	jp	st_redraw
	; огонь: на ПОМОЩЬ — экран помощи и снова настройка, иначе — начать матч
st_fire:
	ld	a, (st_cur)
	cp	ST_HELP
	ret	nz
	call	clear_screen
	ld	hl, s_helptext
	ld	a, 1
st_h1:
	ld	(st_y), a
	ld	a, (hl)
	cp	0xFF
	jp	z, st_h2
	push	hl
	ld	a, (st_y)
	ld	c, a
	xor	a
	ld	b, 2
	call	ui_at
	pop	hl
	call	ui_zstr
	inc	hl
	ld	a, (st_y)
	inc	a
	jp	st_h1
st_h2:
	call	get_key
	jp	setup
	; настройка из таблицы: шаг вперёд или назад, за краем — другой край
st_c_opt:
	push	bc
	call	st_ld
	pop	bc
	ld	hl, (st_e_var)
	ld	a, (st_e_step)
	ld	b, a
	ld	a, c
	dec	a
	jp	nz, sco_dec
	ld	a, (st_e_max)
	cp	(hl)
	ld	a, (st_e_min)
	jp	z, sco_set
	ld	a, (hl)
	add	a, b
	jp	sco_set
sco_dec:
	ld	a, (st_e_min)
	cp	(hl)
	ld	a, (st_e_max)
	jp	z, sco_set
	ld	a, (hl)
	sub	b
sco_set:
	ld	(hl), a
st_redraw:
	ld	a, (st_cur)
	call	st_item
	ld	a, (st_cur)
	or	a
	jp	nz, st_key
	inc	a			; изменилось число игроков — строки игроков
st_rp:
	push	af
	call	st_item
	pop	af
	inc	a
	cp	5
	jp	nz, st_rp
	jp	st_key
st_down:
	ld	a, (st_cur)
	inc	a
	cp	ST_NITEMS
	jp	c, st_d1
	xor	a
st_d1:
	call	st_skip
	jp	nc, st_set
	ld	a, 5			; скрытые строки игроков — сразу к РАУНДОВ
	jp	st_set
st_up:
	ld	a, (st_cur)
	or	a
	jp	nz, st_u1
	ld	a, ST_NITEMS
st_u1:
	dec	a
	call	st_skip
	jp	nc, st_set
	ld	a, (g_n)
st_set:
	ld	b, a
	ld	a, (st_cur)
	ld	c, a
	ld	a, b
	ld	(st_cur), a
	ld	a, c
	call	st_item			; прежняя строка — уже без отметки
	ld	a, (st_cur)
	call	st_item
	jp	st_key
; CF = 1, если пункт A — игрок сверх g_n
st_skip:
	cp	5
	jp	nc, st_sk0		; остальные пункты видны всегда
	ld	b, a
	ld	a, (g_n)
	cp	b
	ld	a, b
	ret				; CF = 1, если g_n < A
st_sk0:
	or	a
	ret

; нарисовать пункт A целиком: отметка курсора, подпись, значение
st_item:
	ld	(st_i), a
	cp	ST_START
	jp	z, sti_start
	cp	ST_HELP
	jp	z, sti_help
	or	a
	jp	z, sti_opt
	cp	5
	jp	nc, sti_opt
	add	a, 6			; игроки — строки 7..10
	ld	(st_y), a
	ld	l, a
	ld	a, (st_i)
	call	st_mark
	call	st_name			; st_buf — 16 знаков
	ld	a, (st_i)
	add	a, 3
	ld	c, a
	ld	b, 16
	ld	de, st_buf
	ld	a, (st_y)
	ld	l, a
	ld	h, ST_COL
	jp	gm_text
sti_start:
	ld	l, 21
	call	st_mark
	ld	de, s_start
	ld	hl, ST_COL * 256 + 21
	ld	bc, 0x0602
	jp	gm_text
sti_help:
	ld	l, 23
	call	st_mark
	ld	de, s_helpitem
	ld	hl, ST_COL * 256 + 23
	ld	bc, 0x0602
	jp	gm_text
sti_opt:
	call	st_ld
	ld	a, (st_e_row)
	ld	l, a
	ld	a, (st_i)
	call	st_mark
	ld	hl, (st_e_lbl)
	ex	de, hl
	ld	a, (st_e_row)
	ld	l, a
	ld	h, ST_COL
	ld	bc, 0x0802
	call	gm_text
	ld	hl, (st_e_var)
	ld	a, (hl)
	ld	(st_v), a
	ld	hl, (st_e_names)
	ld	a, h
	or	l
	jp	z, sti_num
	ld	a, (st_e_min)		; название значения: 9 знаков, по порядку от наименьшего
	ld	b, a
	ld	a, (st_v)
	sub	b
	ld	de, 9
sti_n:
	or	a
	jp	z, sti_n1
	add	hl, de
	dec	a
	jp	sti_n
sti_n1:
	ex	de, hl
	ld	a, (st_e_row)
	ld	l, a
	ld	h, ST_VCOL
	ld	bc, 0x0902
	jp	gm_text
sti_num:
	ld	a, (st_e_row)
	ld	l, a
	ld	h, ST_VCOL
	ld	a, (st_v)
	jp	st_num

; запись таблицы настроек для пункта st_i (0 или 5..10) -> ячейки st_e_*
st_ld:
	ld	a, (st_i)
	or	a
	jp	z, sld_0
	sub	4
sld_0:
	ld	l, a
	ld	h, 0
	add	hl, hl
	ld	d, h
	ld	e, l
	add	hl, hl
	add	hl, hl
	add	hl, de			; ·10
	ld	de, st_opts
	add	hl, de
	ld	de, st_e_row
	ld	b, 10
	jp	gm_copy

; отметка курсора в столбце 2 строки L для пункта A
st_mark:
	ld	b, a
	ld	a, (st_cur)
	cp	b
	ld	a, ' '
	jp	nz, st_m1
	ld	a, '>'
st_m1:
	ld	(st_buf), a
	ld	h, 2
	ld	de, st_buf
	ld	bc, 0x0102
	jp	gm_text
; число A (0..199) тремя знаками в столбце H строки L
st_num:
	ld	de, st_buf
	ld	b, ' '
	cp	100
	jp	c, stn_1
	sub	100
	ld	b, '1'
stn_1:
	ld	c, a
	ld	a, b
	ld	(de), a
	inc	de
	ld	a, c
	ld	c, 0
stn_2:
	cp	10
	jp	c, stn_3
	sub	10
	inc	c
	jp	stn_2
stn_3:
	push	af
	ld	a, c
	or	a
	jp	nz, stn_4
	ld	a, b
	cp	' '
	jp	z, stn_5		; ни сотен, ни десятков — пробел
	xor	a
stn_4:
	add	a, '0'
stn_5:
	ld	(de), a
	inc	de
	pop	af
	add	a, '0'
	ld	(de), a
	ld	de, st_buf
	ld	bc, 0x0302
	jp	gm_text
; st_buf = «N ИМЯ» игрока st_i, 16 знаков; место сверх g_n — пробелы
st_name:
	ld	hl, st_buf
	ld	b, 16
	ld	a, ' '
st_nm0:
	ld	(hl), a
	inc	hl
	dec	b
	jp	nz, st_nm0
	ld	a, (st_i)
	ld	b, a
	ld	a, (g_n)
	cp	b
	ret	c
	ld	a, b
	add	a, '0'
	ld	(st_buf), a
	ld	e, b
	ld	d, 0
	ld	hl, g_types - 1
	add	hl, de
	ld	a, (hl)
	or	a
	jp	nz, st_nm_ai
	ld	hl, s_player
	ld	de, st_buf + 2
	ld	b, 6
	call	gm_copy
	ld	a, (st_i)
	add	a, '0'
	ld	(de), a
	ret
st_nm_ai:
	ld	hl, s_ainames - 13
	ld	bc, 13
st_nm1:
	add	hl, bc
	dec	a
	jp	nz, st_nm1
	ld	de, st_buf + 2
	ld	b, 13
st_nm2:
	ld	a, (hl)
	or	a
	ret	z
	ld	(de), a
	inc	hl
	inc	de
	dec	b
	jp	nz, st_nm2
	ret
setup_end:

; настройки: строка экрана, подпись (8 знаков), ячейка, наименьшее, наибольшее, шаг, названия значений (0 — число)
st_opts:
	db	5
	dw	s_o_n, g_n
	db	2, MAX_PLAYERS, 1
	dw	0
	db	12
	dw	s_o_rounds, g_rounds
	db	1, 50, 1
	dw	0
	db	14
	dw	s_o_walls, g_walls
	db	0, 2, 1
	dw	s_v_walls
	db	15
	dw	s_o_wind, g_windmode
	db	0, 5, 1
	dw	s_v_wind
	db	16
	dw	s_o_crumble, g_crumble
	db	0, 100, 10
	dw	0
	db	17
	dw	s_o_fall, g_fall
	db	0, 1, 1
	dw	s_v_yes
	db	18
	dw	s_o_xkill, g_xkill
	db	0, 1, 1
	dw	s_v_yes
st_cur:		db	ST_START
st_i:		db	0
st_y:		db	0
st_v:		db	0
st_e_row:	db	0		; запись таблицы для текущего пункта (10 байт, порядок как в st_opts)
st_e_lbl:	dw	0
st_e_var:	dw	0
st_e_min:	db	0
st_e_max:	db	0
st_e_step:	db	0
st_e_names:	dw	0
st_buf:		ds	16
