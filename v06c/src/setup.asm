; Экран настройки матча (только игровой образ): число игроков, кто на каком месте, число раундов.
; Строки: 0 — PLAYERS, 1..4 — игроки, 5 — ROUNDS, 6 — START. Клавиши: вверх/вниз — строка, влево/вправо — значение,
; пробел или ВК — начать матч. Настройки — g_n, g_types, g_rounds (game.asm); курсор изначально на START.

setup:
	call	clear_screen
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
	ld	hl, 0x0B04
	ld	bc, 0x0902
	call	gm_text
	ld	de, s_help
	ld	hl, 0x0218
	ld	bc, 0x1C02
	call	gm_text
	ld	a, 6
	ld	(st_cur), a
st_draw:
	; PLAYERS n
	xor	a
	ld	l, 8
	call	st_mark
	ld	de, s_players
	ld	hl, 0x0408
	ld	bc, 0x0702
	call	gm_text
	ld	a, (g_n)
	ld	hl, 0x0D08
	call	st_num
	; игроки
	ld	a, 1
st_row:
	ld	(st_i), a
	add	a, 9
	ld	l, a			; строка 10..13
	ld	(st_y), a
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
	ld	h, 4
	call	gm_text
	ld	a, (st_i)
	inc	a
	cp	MAX_PLAYERS + 1
	jp	nz, st_row
	; ROUNDS n
	ld	a, 5
	ld	l, 15
	call	st_mark
	ld	de, s_rounds
	ld	hl, 0x040F
	ld	bc, 0x0602
	call	gm_text
	ld	a, (g_rounds)
	ld	hl, 0x0D0F
	call	st_num
	; START
	ld	a, 6
	ld	l, 18
	call	st_mark
	ld	de, s_start
	ld	hl, 0x0412
	ld	bc, 0x0502
	call	gm_text
st_key:
	xor	a
	ld	(g_phase), a
	call	get_key
	cp	5
	ret	z
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
	or	a
	jp	z, st_c_n
	cp	5
	jp	z, st_c_r
	jp	nc, st_key
	; тип игрока: 0..7 по кругу
	ld	e, a
	ld	d, 0
	ld	hl, g_types - 1
	add	hl, de
	ld	a, (hl)
	add	a, c
	and	7
	ld	(hl), a
	jp	st_draw
st_c_n:
	ld	a, (g_n)
	add	a, c
	cp	2
	jp	c, st_key
	cp	MAX_PLAYERS + 1
	jp	nc, st_key
	ld	(g_n), a
	jp	st_draw
st_c_r:
	ld	a, (g_rounds)
	add	a, c
	jp	z, st_key
	cp	51
	jp	nc, st_key
	ld	(g_rounds), a
	jp	st_draw
st_down:
	ld	a, (st_cur)
	inc	a
	cp	7
	jp	c, st_d1
	xor	a
st_d1:
	call	st_skip
	jp	nc, st_set
	ld	a, 5			; скрытые строки игроков — сразу к ROUNDS
	jp	st_set
st_up:
	ld	a, (st_cur)
	or	a
	jp	nz, st_u1
	ld	a, 7
st_u1:
	dec	a
	call	st_skip
	jp	nc, st_set
	ld	a, (g_n)
st_set:
	ld	(st_cur), a
	jp	st_draw
; CF = 1, если строка A — игрок сверх g_n
st_skip:
	cp	5
	jp	nc, st_sk0		; ROUNDS и START видны всегда
	ld	b, a
	ld	a, (g_n)
	cp	b
	ld	a, b
	ret				; CF = 1, если g_n < A
st_sk0:
	or	a
	ret

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
; число A (0..99) двумя знаками в столбце H строки L
st_num:
	ld	b, ' '
	ld	c, '0'
st_n1:
	cp	10
	jp	c, st_n2
	sub	10
	inc	c
	ld	b, c
	jp	st_n1
st_n2:
	add	a, '0'
	ld	(st_buf + 1), a
	ld	a, b
	ld	(st_buf), a
	ld	de, st_buf
	ld	bc, 0x0202
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
	ld	b, 7
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

s_players:	db	"PLAYERS"
s_rounds:	db	"ROUNDS"
s_start:	db	"START"
s_help:		db	"ARROWS: CHOOSE  SPACE: START"
st_cur:		db	6
st_i:		db	0
st_y:		db	0
st_buf:		ds	16
