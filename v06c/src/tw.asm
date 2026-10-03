; Tank Wars / Вектор-06Ц — тестовый образ стенда (не игра).
; Грузится с 0100h. Экран: три плоскости A000h–FFFFh. Плоскость 8000h в картинку
; не входит: палитра парами одинаковых цветов.
	device	noslot64k
	org	0x0100

PARAM		equ	0x0080
PARAM_MODE	equ	PARAM + 0
PARAM_KIND	equ	PARAM + 1
PARAM_COUNT	equ	PARAM + 2
PARAM_SEED	equ	PARAM + 4
PARAM_N		equ	PARAM + 8
PARAM_X		equ	PARAM + 10
PARAM_Y		equ	PARAM + 11
PARAM_X2	equ	PARAM + 12
PARAM_Y2	equ	PARAM + 13
PARAM_C		equ	PARAM + 14
LIST		equ	0x4000
RESULT		equ	0x7000
STACK		equ	0x9F00

MODE_RANDOM	equ	1
MODE_PIXELS	equ	2
MODE_LINES	equ	3
MODE_BENCH	equ	4
MODE_ERASELN	equ	5
MODE_FRAME	equ	6
MODE_TANK	equ	7
MODE_CROSS	equ	8
MODE_RING	equ	9
MODE_CLEAR	equ	10
MODE_BARREL	equ	11
MODE_TEXT	equ	12
MODE_CRUMBLE	equ	13
MODE_REPLACE	equ	14
MODE_PAL	equ	15
MODE_UI		equ	16
MODE_DISC	equ	17
MODE_SHOW	equ	18
MODE_TERRAIN	equ	19
MODE_FX		equ	20
MODE_PLACE	equ	21
MODE_MATCH	equ	22
MODE_FLIGHT	equ	23
MODE_ROUND	equ	24
MODE_EXPLODE	equ	25
MODE_AFTER	equ	26
KIND_RANDOM	equ	1
KIND_PIXEL	equ	2
KIND_LINE	equ	3
KIND_FRAME	equ	4
KIND_TANK	equ	5
KIND_CROSS	equ	6
KIND_RING	equ	7
KIND_CLEAR	equ	8
KIND_BARREL	equ	9
KIND_CHAR	equ	10
KIND_PANEL	equ	11
KIND_CRUMBLE	equ	12
KIND_DISC	equ	13

PPI_CW		equ	0x00
PPI_C		equ	0x01
PPI_B		equ	0x02
PPI_A		equ	0x03
PAL_PORT	equ	0x0C
PPI_OUT		equ	0x88

entry:
	di
	ld	sp, STACK
	call	set_palette
	ld	a, (PARAM_MODE)
	cp	MODE_RANDOM
	jp	z, do_random
	cp	MODE_PIXELS
	jp	z, do_pixels
	cp	MODE_LINES
	jp	z, do_lines
	cp	MODE_BENCH
	jp	z, do_bench
	cp	MODE_ERASELN
	jp	z, do_eraseln
	cp	MODE_FRAME
	jp	z, do_frame
	cp	MODE_TANK
	jp	z, do_tank
	cp	MODE_CROSS
	jp	z, do_cross
	cp	MODE_CLEAR
	jp	z, do_clear
	cp	MODE_BARREL
	jp	z, do_barrel
	cp	MODE_TEXT
	jp	z, do_text
	cp	MODE_CRUMBLE
	jp	z, do_crumble
	cp	MODE_REPLACE
	jp	z, do_replace
	cp	MODE_PAL
	jp	z, do_pal
	cp	MODE_UI
	jp	z, do_ui
	cp	MODE_DISC
	jp	z, do_disc
	cp	MODE_SHOW
	jp	z, do_show
	cp	MODE_TERRAIN
	jp	z, do_terrain
	cp	MODE_FX
	jp	z, do_fx
	cp	MODE_PLACE
	jp	z, do_place
	cp	MODE_MATCH
	jp	z, do_match
	cp	MODE_FLIGHT
	jp	z, do_flight
	cp	MODE_ROUND
	jp	z, do_round
	cp	MODE_EXPLODE
	jp	z, do_explode
	cp	MODE_AFTER
	jp	z, do_after
	jp	done
done:
	halt
	jp	done

; Палитра: idx=(p0<<3)|(p1<<2)|(p2<<1)|p3, цвет игры c=p1+2*p2+4*p3.
; pal[i] = pal[i+8], поэтому бит плоскости 8000h на картинку не влияет.
set_palette:
	ld	a, PPI_OUT
	out	(PPI_CW), a
	ld	a, 0xFF
	out	(PPI_A), a		; прокрутка FFh
	xor	a
	out	(PPI_C), a
	ld	b, 0
sp_lp:
	ld	a, b
	and	0x04		; p1 → bit0 цвета
	jp	z, sp_b0
	ld	a, 1
	jp	sp_c1
sp_b0:
	xor	a
sp_c1:
	ld	c, a
	ld	a, b
	and	0x02		; p2 → bit1
	jp	z, sp_b1
	ld	a, c
	or	2
	ld	c, a
sp_b1:
	ld	a, b
	and	0x01		; p3 → bit2
	jp	z, sp_b2
	ld	a, c
	or	4
	ld	c, a
sp_b2:
	ld	hl, pal_rgb
	ld	a, l
	add	a, c
	ld	l, a
	ld	a, h
	adc	a, 0
	ld	h, a
	ld	a, b
	out	(PPI_B), a
	ld	a, (hl)
	out	(PAL_PORT), a
	out	(PAL_PORT), a
	inc	b
	ld	a, b
	cp	16
	jp	c, sp_lp
	xor	a
	out	(PPI_B), a
	ret

pal_rgb:
	db	0x00, 0x02, 0x14, 0x16, 0xA0, 0xA2, 0xB4, 0xB6

do_random:
	ld	hl, PARAM_SEED
	ld	de, rand_seed
	ld	b, 4
	call	copy_b
	ld	hl, (PARAM_COUNT)
	ld	(left), hl
	ld	hl, LIST
	ld	(list_ptr), hl
	ld	hl, RESULT
	ld	(res_ptr), hl
dr_lp:
	ld	hl, (left)
	ld	a, h
	or	l
	jp	z, dr_fin
	dec	hl
	ld	(left), hl
	ld	hl, (list_ptr)
	ld	e, (hl)
	inc	hl
	ld	d, (hl)
	inc	hl
	ld	(list_ptr), hl
	call	random
	ex	de, hl
	ld	hl, (res_ptr)
	ld	(hl), e
	inc	hl
	ld	(hl), d
	inc	hl
	ld	(res_ptr), hl
	jp	dr_lp
dr_fin:
	ld	hl, rand_seed
	ld	de, PARAM_SEED
	ld	b, 4
	call	copy_b
	jp	done

do_pixels:
	ld	hl, (PARAM_COUNT)
	ld	(left), hl
	ld	hl, LIST
	ld	(list_ptr), hl
dp_plot:
	ld	hl, (left)
	ld	a, h
	or	l
	jp	z, dp_read
	dec	hl
	ld	(left), hl
	ld	hl, (list_ptr)
	ld	d, (hl)
	inc	hl
	ld	e, (hl)
	inc	hl
	ld	a, (hl)
	inc	hl
	ld	(list_ptr), hl
	call	putpixel
	jp	dp_plot
dp_read:
	ld	hl, (PARAM_COUNT)
	ld	(left), hl
	ld	hl, LIST
	ld	(list_ptr), hl
	ld	hl, RESULT
	ld	(res_ptr), hl
dp_rdlp:
	ld	hl, (left)
	ld	a, h
	or	l
	jp	z, done
	dec	hl
	ld	(left), hl
	ld	hl, (list_ptr)
	ld	d, (hl)
	inc	hl
	ld	e, (hl)
	inc	hl
	inc	hl			; пропуск цвета
	ld	(list_ptr), hl
	call	getpixel
	ld	hl, (res_ptr)
	ld	(hl), a
	inc	hl
	ld	(res_ptr), hl
	jp	dp_rdlp

do_lines:
	ld	hl, (PARAM_COUNT)
	ld	(left), hl
	ld	hl, LIST
	ld	(list_ptr), hl
dl_lp:
	ld	hl, (left)
	ld	a, h
	or	l
	jp	z, done
	dec	hl
	ld	(left), hl
	ld	hl, (list_ptr)
	ld	a, (hl)
	ld	(ln_x1), a
	xor	a
	ld	(ln_x1 + 1), a
	inc	hl
	ld	a, (hl)
	ld	(ln_y1), a
	xor	a
	ld	(ln_y1 + 1), a
	inc	hl
	ld	a, (hl)
	ld	(ln_x2), a
	xor	a
	ld	(ln_x2 + 1), a
	inc	hl
	ld	a, (hl)
	ld	(ln_y2), a
	xor	a
	ld	(ln_y2 + 1), a
	inc	hl
	ld	a, (hl)
	ld	(ln_c), a
	inc	hl
	ld	(list_ptr), hl
	call	line
	jp	dl_lp

do_bench:
	ld	a, (PARAM_KIND)
	cp	KIND_RANDOM
	jp	z, bench_random
	cp	KIND_PIXEL
	jp	z, bench_pixel
	cp	KIND_LINE
	jp	z, bench_line
	cp	KIND_FRAME
	jp	z, bench_frame
	cp	KIND_TANK
	jp	z, bench_tank
	cp	KIND_CROSS
	jp	z, bench_cross
	cp	KIND_DISC
	jp	z, bench_disc
	cp	KIND_CLEAR
	jp	z, bench_clear
	cp	KIND_BARREL
	jp	z, bench_barrel
	cp	KIND_CHAR
	jp	z, bench_char
	cp	KIND_PANEL
	jp	z, bench_panel
	cp	KIND_CRUMBLE
	jp	z, bench_crumble
	jp	done

bench_random:
	ld	hl, PARAM_SEED
	ld	de, rand_seed
	ld	b, 4
	call	copy_b
	ld	hl, (PARAM_N)
	ex	de, hl
bench_random_call:
	call	random
bench_random_ret:
	ld	(RESULT), hl
	jp	done

bench_pixel:
	ld	a, (PARAM_X)
	ld	d, a
	ld	a, (PARAM_Y)
	ld	e, a
	ld	a, (PARAM_C)
bench_pixel_call:
	call	putpixel
bench_pixel_ret:
	ld	a, (PARAM_X)
	ld	d, a
	ld	a, (PARAM_Y)
	ld	e, a
	call	getpixel
	ld	(RESULT), a
	jp	done

bench_line:
	ld	a, (PARAM_X)
	ld	(ln_x1), a
	xor	a
	ld	(ln_x1 + 1), a
	ld	a, (PARAM_Y)
	ld	(ln_y1), a
	xor	a
	ld	(ln_y1 + 1), a
	ld	a, (PARAM_X2)
	ld	(ln_x2), a
	xor	a
	ld	(ln_x2 + 1), a
	ld	a, (PARAM_Y2)
	ld	(ln_y2), a
	xor	a
	ld	(ln_y2 + 1), a
	ld	a, (PARAM_C)
	ld	(ln_c), a
bench_line_call:
	call	line
bench_line_ret:
	jp	done

do_eraseln:
	ld	a, 1
	call	fill_screen
	jp	do_lines

do_frame:
	ld	hl, (PARAM_COUNT)
	ld	(left), hl
	ld	hl, LIST
	ld	(list_ptr), hl
df_lp:
	ld	hl, (left)
	ld	a, h
	or	l
	jp	z, done
	dec	hl
	ld	(left), hl
	ld	hl, (list_ptr)
	ld	a, (hl)
	inc	hl
	ld	(list_ptr), hl
	call	draw_frame
	jp	df_lp

do_tank:
	ld	hl, (PARAM_COUNT)
	ld	(left), hl
	ld	hl, LIST
	ld	(list_ptr), hl
dt_lp:
	ld	hl, (left)
	ld	a, h
	or	l
	jp	z, done
	dec	hl
	ld	(left), hl
	ld	hl, (list_ptr)
	ld	d, (hl)
	inc	hl
	ld	e, (hl)
	inc	hl
	ld	a, (hl)
	inc	hl
	ld	b, (hl)
	inc	hl
	ld	(list_ptr), hl
	ld	c, a
	ld	a, b
	or	a
	ld	a, c
	jp	z, dt_draw
	call	erase_tank
	jp	dt_lp
dt_draw:
	call	draw_tank
	jp	dt_lp

do_cross:
	ld	hl, (PARAM_COUNT)
	ld	(left), hl
	ld	hl, LIST
	ld	(list_ptr), hl
dc_lp:
	ld	hl, (left)
	ld	a, h
	or	l
	jp	z, done
	dec	hl
	ld	(left), hl
	ld	hl, (list_ptr)
	ld	d, (hl)
	inc	hl
	ld	e, (hl)
	inc	hl
	ld	a, (hl)
	inc	hl
	ld	(list_ptr), hl
	call	draw_cross
	jp	dc_lp

; список: x (слово), y (слово) — экран, r, c, el, er — по 8 байт
do_disc:
	ld	hl, (PARAM_COUNT)
	ld	(left), hl
	ld	hl, LIST
	ld	(list_ptr), hl
ddk_lp:
	ld	hl, (left)
	ld	a, h
	or	l
	jp	z, done
	dec	hl
	ld	(left), hl
	ld	hl, (list_ptr)
	ld	de, dk_x
	ld	b, 8
ddk_cp:
	ld	a, (hl)
	ld	(de), a
	inc	hl
	inc	de
	dec	b
	jp	nz, ddk_cp
	ld	(list_ptr), hl
	call	disc
	jp	ddk_lp

bench_disc:
	ld	a, (PARAM_X)
	ld	l, a
	ld	h, 0
	ld	(dk_x), hl
	ld	a, (PARAM_Y)
	ld	l, a
	ld	(dk_y), hl
	ld	a, (PARAM_X2)
	ld	(dk_r), a
	ld	a, (PARAM_C)
	ld	(dk_c), a
	ld	a, 1
	ld	(dk_el), a
	ld	(dk_er), a
bench_disc_call:
	call	disc
bench_disc_ret:
	jp	done

do_clear:
	ld	a, (PARAM_KIND)
	or	a
	jp	z, do_clr_all
	dec	a
	jp	z, do_clr_pan
	jp	done
do_clr_all:
	call	clear_screen
	jp	done
do_clr_pan:
	call	clear_panel
	jp	done

bench_frame:
	ld	a, (PARAM_C)
bench_frame_call:
	call	draw_frame
bench_frame_ret:
	jp	done

bench_tank:
	ld	a, (PARAM_X)
	ld	d, a
	ld	a, (PARAM_Y)
	ld	e, a
	ld	a, (PARAM_C)
bench_tank_call:
	call	draw_tank
bench_tank_ret:
	jp	done

bench_cross:
	ld	a, (PARAM_X)
	ld	d, a
	ld	a, (PARAM_Y)
	ld	e, a
	ld	a, (PARAM_C)
bench_cross_call:
	call	draw_cross
bench_cross_ret:
	jp	done

bench_clear:
bench_clear_call:
	call	clear_screen
bench_clear_ret:
	jp	done

do_barrel:
	ld	hl, (PARAM_COUNT)
	ld	(left), hl
	ld	hl, LIST
	ld	(list_ptr), hl
dbb_lp:
	ld	hl, (left)
	ld	a, h
	or	l
	jp	z, done
	dec	hl
	ld	(left), hl
	ld	hl, (list_ptr)
	ld	a, (hl)
	ld	(tb_x), a
	inc	hl
	ld	a, (hl)
	ld	(tb_y), a
	inc	hl
	ld	a, (hl)
	ld	(tb_idx), a
	inc	hl
	ld	a, (hl)
	ld	(tb_angle), a
	inc	hl
	ld	a, (hl)
	ld	(tb_angle + 1), a
	inc	hl
	ld	a, (hl)
	ld	(tb_facing), a
	inc	hl
	ld	a, (hl)
	ld	(tb_alive), a
	inc	hl
	ld	a, (hl)
	inc	hl
	ld	(list_ptr), hl
	or	a
	jp	nz, dbb_er
	call	draw_tank_barrel
	jp	dbb_lp
dbb_er:
	call	erase_tank_barrel
	jp	dbb_lp

bench_barrel:
	ld	a, (PARAM_X)
	ld	(tb_x), a
	ld	a, (PARAM_Y)
	ld	(tb_y), a
	ld	a, 1
	ld	(tb_idx), a
	ld	a, 45
	ld	(tb_angle), a
	xor	a
	ld	(tb_angle + 1), a
	ld	a, 1
	ld	(tb_facing), a
	ld	(tb_alive), a
bench_barrel_call:
	call	draw_tank_barrel
bench_barrel_ret:
	jp	done

do_text:
	ld	hl, (PARAM_COUNT)
	ld	(left), hl
	ld	hl, LIST
	ld	(list_ptr), hl
dtx_lp:
	ld	hl, (left)
	ld	a, h
	or	l
	jp	z, done
	dec	hl
	ld	(left), hl
	ld	hl, (list_ptr)
	ld	a, (hl)
	ld	(ch_col), a
	inc	hl
	ld	a, (hl)
	ld	(ch_row), a
	inc	hl
	ld	a, (hl)
	ld	(ch_c), a
	inc	hl
	ld	b, (hl)
	inc	hl
	ex	de, hl
	ld	a, b
	or	a
	jp	z, dtx_empty
	call	draw_text
	jp	dtx_adv
dtx_empty:
	ex	de, hl
	ld	(list_ptr), hl
	jp	dtx_lp
dtx_adv:
	ex	de, hl
	ld	(list_ptr), hl
	jp	dtx_lp

bench_char:
	xor	a
	ld	(ch_col), a
	ld	(ch_row), a
	ld	a, 'A'
	ld	(ch), a
	ld	a, 2
	ld	(ch_c), a
bench_char_call:
	call	draw_char
bench_char_ret:
	jp	done

do_crumble:
	call	crumble
	jp	done

do_replace:
	call	replace_tmp
	jp	done

; Показ на настоящем видеотракте: палитра пишется сразу после прерывания кадра, пока луч в бордюре
; (регистр палитры выбирается цветом под лучом, в бордюре — индексом из порта 02h). Вектор RST 7 ставит стенд показа.
do_show:
	ld	hl, LIST
	ld	de, pal_men
	ld	b, 32
	call	copy_b
	call	pal_prepare
	ei
	halt
	di
	call	pal_out
	ei
show_idle:
	halt
	jp	show_idle

; рельеф: PARAM_SEED -> rand_seed, PARAM_KIND = число игроков; после вызова seed пишется обратно в PARAM_SEED
do_terrain:
	ld	hl, PARAM_SEED
	ld	de, rand_seed
	ld	b, 4
	call	copy_b
	ld	a, (PARAM_KIND)
	call	gen_terrain
	ld	hl, rand_seed
	ld	de, PARAM_SEED
	ld	b, 4
	call	copy_b
	jp	done

; арифметика: записи LIST по 9 байт (операция, a, b) -> RESULT по 8 байт
; 1 mul, 2 div, 3 idiv (b = делитель), 4 sqrt, 5 hypot, 6 sincos (a = градусы) -> cos, sin, 7 atan -> байт, 8 trunc -> слово
do_fx:
	ld	hl, (PARAM_COUNT)
	ld	(left), hl
	ld	hl, LIST
	ld	(list_ptr), hl
	ld	hl, RESULT
	ld	(res_ptr), hl
dfx_lp:
	ld	hl, (left)
	ld	a, h
	or	l
	jp	z, done
	dec	hl
	ld	(left), hl
	ld	hl, (list_ptr)
	ld	a, (hl)
	ld	(fx_op), a
	inc	hl
	ex	de, hl
	ld	hl, fx_a
	ld	b, 8
	call	fx_copy			; a и b подряд: fx_a, fx_b
	ex	de, hl
	ld	(list_ptr), hl
	ld	a, (fx_op)
	dec	a
	jp	z, dfx_mul
	dec	a
	jp	z, dfx_div
	dec	a
	jp	z, dfx_idiv
	dec	a
	jp	z, dfx_sqrt
	dec	a
	jp	z, dfx_hyp
	dec	a
	jp	z, dfx_sc
	dec	a
	jp	z, dfx_atan
	call	fx_trunc
	ld	(fx_a), hl
	jp	dfx_out
dfx_mul:
	call	fx_mul
	jp	dfx_out
dfx_div:
	call	fx_div
	jp	dfx_out
dfx_idiv:
	ld	hl, (fx_b)
	ex	de, hl
	call	fx_idiv
	jp	dfx_out
dfx_sqrt:
	call	fx_sqrt
	jp	dfx_out
dfx_hyp:
	call	fx_hypot
	jp	dfx_out
dfx_atan:
	call	fx_atan
	ld	(fx_a), a
	jp	dfx_out
dfx_sc:
	ld	hl, (fx_a)
	call	fx_sincos
	ld	hl, (res_ptr)
	ld	de, fx_cos
	ld	b, 8
	call	fx_copy			; cos и sin подряд
	ld	(res_ptr), hl
	jp	dfx_lp
dfx_out:
	ld	hl, (res_ptr)
	ld	de, fx_a
	ld	b, 4
	call	fx_copy
	inc	hl
	inc	hl
	inc	hl
	inc	hl
	ld	(res_ptr), hl
	jp	dfx_lp
fx_op:	db	0

; начало раунда без стен и ветра: очистка, рамка, рельеф, отрисовка рельефа, расстановка.
; PARAM_SEED -> rand_seed, PARAM_KIND = число игроков, PARAM_C = стены отражают (0/1); seed пишется обратно.
do_place:
	ld	hl, PARAM_SEED
	ld	de, rand_seed
	ld	b, 4
	call	copy_b
	call	clear_screen
	ld	a, 1
	call	draw_frame		; как drawBackground(0): две рамки без нижней линии земли
	ld	a, (PARAM_KIND)
	call	gen_terrain
	call	render_terrain
	ld	a, (PARAM_C)
	ld	(pl_rebound), a
	ld	a, (PARAM_KIND)
	call	place_tanks
	ld	hl, rand_seed
	ld	de, PARAM_SEED
	ld	b, 4
	call	copy_b
	jp	done

; матч: LIST = n записей игроков по PL_SIZE; PARAM_KIND: 1 перетасовка, 2 бонус (PARAM_C = место), 3 результаты (PARAM_C = auto)
; PARAM_N = число игроков; PARAM_SEED -> rand_seed и обратно; записи копируются в players и обратно в LIST.
do_match:
	ld	hl, PARAM_SEED
	ld	de, rand_seed
	ld	b, 4
	call	copy_b
	ld	a, (PARAM_N)
	ld	(n_players), a
	ld	hl, LIST
	ld	de, players
	call	dm_copy
	ld	a, (PARAM_KIND)
	dec	a
	jp	z, dm_shuffle
	dec	a
	jp	z, dm_bonus
	ld	a, (PARAM_C)
	call	results_sort
	jp	dm_out
dm_shuffle:
	call	shuffle_players
	jp	dm_out
dm_bonus:
	ld	a, (PARAM_C)
	call	winner_bonus
dm_out:
	ld	hl, players
	ld	de, LIST
	call	dm_copy
	ld	hl, rand_seed
	ld	de, PARAM_SEED
	ld	b, 4
	call	copy_b
	jp	done
dm_copy:				; MAX_PLAYERS * PL_SIZE байт из HL в DE
	ld	bc, MAX_PLAYERS * PL_SIZE
dm_cp:
	ld	a, (hl)
	ld	(de), a
	inc	hl
	inc	de
	dec	bc
	ld	a, b
	or	c
	jp	nz, dm_cp
	ret

; полёт: LIST = 14 байт входа (как ячейки fl_angle..fl_ball); экран загружает стенд. Выход — в RESULT: stop, hit, x, y
do_flight:
	ld	hl, LIST
	ld	de, fl_angle
	ld	b, 14
	call	copy_b
bench_flight_call:
	call	flight
bench_flight_ret:
	ld	hl, fl_stop
	ld	de, RESULT
	ld	b, 10
	call	copy_b
	jp	done

; начало раунда: LIST = записи игроков; PARAM_N = число игроков, PARAM_KIND = стены (0/1/2), PARAM_C = режим ветра;
; PARAM_SEED -> rand_seed и обратно; после вызова записи копируются обратно в LIST, а rs_rebound, rs_first, rs_wind — в RESULT.
do_round:
	ld	hl, PARAM_SEED
	ld	de, rand_seed
	ld	b, 4
	call	copy_b
	ld	a, (PARAM_N)
	ld	(n_players), a
	ld	a, (PARAM_KIND)
	ld	(rs_walls), a
	ld	a, (PARAM_C)
	ld	(rs_windmode), a
	ld	hl, LIST
	ld	de, players
	call	dm_copy
	call	round_start
	ld	hl, players
	ld	de, LIST
	call	dm_copy
	ld	hl, rs_rebound
	ld	de, RESULT
	ld	b, 4
	call	copy_b
	ld	hl, rand_seed
	ld	de, PARAM_SEED
	ld	b, 4
	call	copy_b
	jp	done

; взрыв: LIST = записи игроков; RESULT (на входе) = 11 байт: x, y (Q16.16), hit, shooter, weapon; PARAM_N = число игроков.
; Экран загружает стенд. После вызова записи копируются обратно в LIST.
do_explode:
	ld	a, (PARAM_N)
	ld	(n_players), a
	ld	hl, LIST
	ld	de, players
	call	dm_copy
	ld	hl, RESULT
	ld	de, ex_x
	ld	b, 11
	call	copy_b
	call	explode
	ld	hl, players
	ld	de, LIST
	call	dm_copy
	jp	done

; после выстрела: LIST = записи игроков; PARAM_N = число игроков; PARAM_KIND = процент осыпания; PARAM_C = танки падают;
; PARAM_Y2 = стены отражают; PARAM_SEED -> rand_seed и обратно. Экран загружает стенд.
do_after:
	ld	hl, PARAM_SEED
	ld	de, rand_seed
	ld	b, 4
	call	copy_b
	ld	a, (PARAM_N)
	ld	(n_players), a
	ld	a, (PARAM_KIND)
	ld	(as_crumble), a
	ld	a, (PARAM_C)
	ld	(as_fall), a
	ld	a, (PARAM_Y2)
	ld	(as_rebound), a
	ld	hl, LIST
	ld	de, players
	call	dm_copy
	call	after_shot
	ld	hl, players
	ld	de, LIST
	call	dm_copy
	ld	hl, rand_seed
	ld	de, PARAM_SEED
	ld	b, 4
	call	copy_b
	jp	done

do_pal:
	ld	hl, LIST
	ld	de, pal_men
	ld	b, 8
	call	copy_b
	ld	de, pal_divr
	ld	b, 8
	call	copy_b
	ld	de, pal_divg
	ld	b, 8
	call	copy_b
	ld	de, pal_divb
	ld	b, 8
	call	copy_b
	call	pal_apply
	jp	done

do_ui:
	ld	a, (PARAM_KIND)
	or	a
	jp	z, do_panel
	dec	a
	jp	z, do_results
	dec	a
	jp	z, do_shop
	jp	done

do_panel:
	ld	hl, LIST
	ld	a, (hl)
	ld	(ui_wind), a
	inc	hl
	ld	a, (hl)
	ld	(ui_wind + 1), a
	inc	hl
	ld	(ui_p), hl
	call	draw_panel
	jp	done

do_results:
	ld	a, (LIST)
	ld	(ui_round), a
	ld	a, (LIST + 1)
	ld	(ui_rounds), a
	ld	a, (LIST + 2)
	ld	(ui_n), a
	ld	hl, LIST + 3
	ld	(ui_ps), hl
	call	draw_results
	jp	done

do_shop:
	ld	hl, LIST
	ld	a, (hl)
	ld	(ui_cart), a
	inc	hl
	ld	a, (hl)
	ld	(ui_cart + 1), a
	inc	hl
	ld	a, (hl)
	ld	(ui_sel), a
	inc	hl
	ld	a, (hl)
	ld	(ui_nmenu), a
	inc	hl
	ld	(ui_menu), hl
	ld	a, (ui_nmenu)
	ld	e, a
	ld	d, 0
	add	hl, de
	add	hl, de
	add	hl, de
	add	hl, de
	ld	(ui_p), hl
	call	draw_shop
	jp	done

bench_panel:
	ld	hl, LIST
	xor	a
	ld	(ui_wind), a
	ld	(ui_wind + 1), a
	ld	(ui_p), hl
bench_panel_call:
	call	draw_panel
bench_panel_ret:
	jp	done

bench_crumble:
bench_crumble_call:
	call	crumble
bench_crumble_ret:
	jp	done

copy_b:
	ld	a, (hl)
	ld	(de), a
	inc	hl
	inc	de
	dec	b
	jp	nz, copy_b
	ret

	include	"player.inc"
kernel_start:
	include	"random.asm"
	include	"pixel.asm"
	include	"line.asm"
	include	"frame.asm"
	include	"sprite.asm"
	include	"fill.asm"
	include	"disc.asm"
	include	"terrain.asm"
	include	"place.asm"
	include	"match.asm"
	include	"round.asm"
	include	"fx.asm"
	include	"flight.asm"
	include	"explode.asm"
	include	"after.asm"
	include	"barrel.asm"
	include	"text.asm"
	include	"crumble.asm"
	include	"pal.asm"
	include	"ui.asm"
kernel_end:

list_ptr:	dw	0
res_ptr:	dw	0
left:		dw	0

rom_end:
	savebin	"v06c/build/tw.rom", 0x0100, rom_end - 0x0100
	display	"rom_end=", /h, rom_end
	display	"random=", /h, random, "-", /h, random_end, " bytes ", /d, random_end - random
	display	"putpixel=", /h, putpixel, "-", /h, putpixel_end, " bytes ", /d, putpixel_end - putpixel
	display	"getpixel=", /h, getpixel, "-", /h, getpixel_end, " bytes ", /d, getpixel_end - getpixel
	display	"pixel=", /h, putpixel, "-", /h, pixel_end, " bytes ", /d, pixel_end - putpixel
	display	"line=", /h, line, "-", /h, line_end, " bytes ", /d, line_end - line
	display	"draw_frame=", /h, draw_frame, "-", /h, draw_frame_end, " bytes ", /d, draw_frame_end - draw_frame
	display	"draw_tank=", /h, draw_tank, "-", /h, draw_tank_end, " bytes ", /d, draw_tank_end - draw_tank
	display	"fill_screen=", /h, fill_screen, "-", /h, fill_screen_end, " bytes ", /d, fill_screen_end - fill_screen
	display	"draw_tank_barrel=", /h, draw_tank_barrel, "-", /h, draw_tank_barrel_end, " bytes ", /d, draw_tank_barrel_end - draw_tank_barrel
	display	"draw_char=", /h, draw_char, "-", /h, draw_char_end, " bytes ", /d, draw_char_end - draw_char
	display	"crumble=", /h, crumble, "-", /h, crumble_end, " bytes ", /d, crumble_end - crumble
	display	"replace_tmp=", /h, replace_tmp, "-", /h, replace_tmp_end, " bytes ", /d, replace_tmp_end - replace_tmp
	display	"pal_apply=", /h, pal_apply, "-", /h, pal_apply_end, " bytes ", /d, pal_apply_end - pal_apply
	display	"draw_panel=", /h, draw_panel, "-", /h, draw_panel_end, " bytes ", /d, draw_panel_end - draw_panel
	display	"disc=", /h, disc, "-", /h, disc_end, " bytes ", /d, disc_end - disc
	display	"fx=", /h, fx_shl, "-", /h, fx_end, " bytes ", /d, fx_end - fx_shl
	display	"stand=", /d, kernel_start - 0x0100
	display	"kernel=", /d, kernel_end - kernel_start
	display	"rom=", /d, rom_end - 0x0100
