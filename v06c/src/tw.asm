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
KIND_RANDOM	equ	1
KIND_PIXEL	equ	2
KIND_LINE	equ	3

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
