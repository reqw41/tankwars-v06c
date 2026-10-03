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
LIST		equ	0x2000
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
	cp	MODE_RING
	jp	z, do_ring
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
	jp	done
done:
	halt
	jp	done

; Палитра: idx=(p0<<3)|(p1<<2)|(p2<<1)|p3, цвет игры c=p1+2*p2+4*p3.
; pal[i] = pal[i+8], поэтому бит плоскости 8000h на картинку не влияет.
set_palette:
	ld	a, PPI_OUT
	out	(PPI_CW), a
	xor	a
	out	(PPI_A), a
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
	cp	KIND_RING
	jp	z, bench_ring
	cp	KIND_CLEAR
	jp	z, bench_clear
	cp	KIND_BARREL
	jp	z, bench_barrel
	cp	KIND_CHAR
	jp	z, bench_char
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

do_ring:
	ld	hl, (PARAM_COUNT)
	ld	(left), hl
	ld	hl, LIST
	ld	(list_ptr), hl
drg_lp:
	ld	hl, (left)
	ld	a, h
	or	l
	jp	z, done
	dec	hl
	ld	(left), hl
	ld	hl, (list_ptr)
	ld	a, (hl)
	ld	(ring_cx), a
	inc	hl
	ld	a, (hl)
	ld	(ring_cx + 1), a
	inc	hl
	ld	a, (hl)
	ld	(ring_cy), a
	inc	hl
	ld	a, (hl)
	ld	(ring_cy + 1), a
	inc	hl
	ld	a, (hl)
	ld	(ring_r), a
	inc	hl
	ld	a, (hl)
	ld	(ring_c), a
	inc	hl
	ld	(list_ptr), hl
	call	ring
	jp	drg_lp

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

bench_ring:
	ld	a, (PARAM_X)
	ld	(ring_cx), a
	xor	a
	ld	(ring_cx + 1), a
	ld	a, (PARAM_Y)
	ld	(ring_cy), a
	xor	a
	ld	(ring_cy + 1), a
	ld	a, (PARAM_X2)
	ld	(ring_r), a
	ld	a, (PARAM_C)
	ld	(ring_c), a
bench_ring_call:
	call	ring
bench_ring_ret:
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

copy_b:
	ld	a, (hl)
	ld	(de), a
	inc	hl
	inc	de
	dec	b
	jp	nz, copy_b
	ret

	include	"random.asm"
	include	"pixel.asm"
	include	"line.asm"
	include	"frame.asm"
	include	"sprite.asm"
	include	"fill.asm"
	include	"ring.asm"
	include	"barrel.asm"
	include	"text.asm"
	include	"crumble.asm"

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
	display	"ring=", /h, ring, "-", /h, ring_end, " bytes ", /d, ring_end - ring
	display	"draw_tank_barrel=", /h, draw_tank_barrel, "-", /h, draw_tank_barrel_end, " bytes ", /d, draw_tank_barrel_end - draw_tank_barrel
	display	"draw_char=", /h, draw_char, "-", /h, draw_char_end, " bytes ", /d, draw_char_end - draw_char
	display	"crumble=", /h, crumble, "-", /h, crumble_end, " bytes ", /d, crumble_end - crumble
	display	"replace_tmp=", /h, replace_tmp, "-", /h, replace_tmp_end, " bytes ", /d, replace_tmp_end - replace_tmp
