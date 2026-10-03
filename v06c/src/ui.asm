; Панель, результаты, магазин — те же строки, что drawPanel/drawResults/drawShop эталона.

PLY_NAME	equ	0
PLY_IDX		equ	16
PLY_FAC		equ	17
PLY_ANG		equ	18
PLY_POW		equ	20
PLY_MEN		equ	22
PLY_WPN		equ	24
PLY_GD		equ	25
PLY_HERB	equ	26
PLY_VICK	equ	28
PLY_WINS	equ	30
PLY_SCORE	equ	32
PLY_SPENT	equ	36
PLY_SHLD	equ	40
PLY_DAMP	equ	42
PLY_AMMO	equ	44
PLY_SIZE	equ	80

	include	"names.inc"

; A=col, C=row, B=color
ui_at:
	ld	(ch_col), a
	ld	a, c
	ld	(ch_row), a
	ld	a, b
	ld	(ch_c), a
	ret

ui_zstr:
	ld	a, (hl)
	or	a
	ret	z
	ld	(ch), a
	push	hl
	call	draw_char
	pop	hl
	inc	hl
	ld	a, (ch_col)
	inc	a
	ld	(ch_col), a
	jp	ui_zstr

; HL имя (до 16, 0-терминатор), B ширина padR, рисует с текущих ch_*
ui_padr_name:
	push	hl
	push	bc
	call	ui_strlen16
	pop	bc
	ld	c, a
	pop	hl
	jp	ui_padr

ui_strlen16:
	ld	b, 16
	ld	c, 0
us16:
	ld	a, (hl)
	or	a
	jp	z, us16d
	inc	hl
	inc	c
	dec	b
	jp	nz, us16
us16d:
	ld	a, c
	ret

; HL src, C len, B width → padR в ui_buf и draw_text
ui_padr:
	ld	a, c
	cp	b
	jp	c, pr_short
	ld	de, ui_buf
	ld	a, b
pr_cp:
	or	a
	jp	z, pr_draw
	push	af
	ld	a, (hl)
	ld	(de), a
	inc	hl
	inc	de
	pop	af
	dec	a
	jp	pr_cp
pr_short:
	ld	de, ui_buf
	ld	a, c
	or	a
	jp	z, pr_sp
	push	bc
pr_s1:
	ld	a, (hl)
	ld	(de), a
	inc	hl
	inc	de
	dec	c
	jp	nz, pr_s1
	pop	bc
pr_sp:
	ld	a, b
	sub	c
	jp	z, pr_draw
	ld	c, a
pr_s2:
	ld	a, ' '
	ld	(de), a
	inc	de
	dec	c
	jp	nz, pr_s2
pr_draw:
	ld	de, ui_buf
	call	draw_text
	ret

; HL src, C len, B width → padL
ui_padl:
	ld	a, c
	cp	b
	jp	c, pl_short
	; последние B символов
	ld	a, c
	sub	b
	ld	e, a
	ld	d, 0
	add	hl, de
	ld	de, ui_buf
	ld	a, b
pl_cp:
	or	a
	jp	z, pr_draw
	push	af
	ld	a, (hl)
	ld	(de), a
	inc	hl
	inc	de
	pop	af
	dec	a
	jp	pl_cp
pl_short:
	ld	de, ui_buf
	ld	a, b
	sub	c
	jp	z, pl_copy
	push	bc
	ld	c, a
pl_sp:
	ld	a, ' '
	ld	(de), a
	inc	de
	dec	c
	jp	nz, pl_sp
	pop	bc
pl_copy:
	ld	a, c
	or	a
	jp	z, pr_draw
pl_c1:
	ld	a, (hl)
	ld	(de), a
	inc	hl
	inc	de
	dec	c
	jp	nz, pl_c1
	jp	pr_draw

; n32 — знаковое 32-битное LE → ui_num, C=длина
ui_itoa:
	ld	hl, ui_num
	ld	(it_out), hl
	ld	a, (n32 + 3)
	and	0x80
	jp	z, it_pos
	ld	a, '-'
	ld	(hl), a
	inc	hl
	ld	(it_out), hl
	xor	a
	ld	hl, n32
	ld	b, 4
it_neg:
	ld	a, 0
	sbc	a, (hl)
	ld	(hl), a
	inc	hl
	dec	b
	jp	nz, it_neg
it_pos:
	xor	a
	ld	(it_nz), a
	ld	hl, pow10
	ld	(it_pw), hl
	ld	b, 8
it_d:
	push	bc
	ld	hl, (it_pw)
	ld	de, p32
	ld	b, 4
it_ldp:
	ld	a, (hl)
	ld	(de), a
	inc	hl
	inc	de
	dec	b
	jp	nz, it_ldp
	ld	(it_pw), hl
	ld	a, '0'
	ld	(it_dg), a
it_more:
	call	ui_cmp32
	jp	c, it_put
	call	ui_sub32
	ld	a, (it_dg)
	inc	a
	ld	(it_dg), a
	jp	it_more
it_put:
	pop	bc
	ld	a, (it_dg)
	cp	'0'
	jp	nz, it_st
	ld	a, (it_nz)
	or	a
	jp	nz, it_st0
	ld	a, b
	cp	1
	jp	nz, it_sk
it_st0:
	ld	a, '0'
it_st:
	ld	hl, (it_out)
	ld	(hl), a
	inc	hl
	ld	(it_out), hl
	ld	a, 1
	ld	(it_nz), a
it_sk:
	dec	b
	jp	nz, it_d
	ld	hl, (it_out)
	ld	a, l
	ld	de, ui_num
	sub	e
	ld	c, a
	ld	(ui_nlen), a
	ret

ui_cmp32:
	ld	b, 4
	ld	de, n32 + 3
	ld	hl, p32 + 3
c32:
	ld	a, (de)
	cp	(hl)
	jp	nz, c32d
	dec	de
	dec	hl
	dec	b
	jp	nz, c32
	xor	a
	ret
c32d:
	ret

ui_sub32:
	or	a
	ld	hl, n32
	ld	de, p32
	ld	b, 4
s32:
	ld	a, (de)
	ld	c, a
	ld	a, (hl)
	sbc	a, c
	ld	(hl), a
	inc	hl
	inc	de
	dec	b
	jp	nz, s32
	ret

; HL = адрес i16, знаковое → n32
ld_i16:
	ld	a, (hl)
	ld	(n32), a
	inc	hl
	ld	a, (hl)
	ld	(n32 + 1), a
	rla
	sbc	a, a
	ld	(n32 + 2), a
	ld	(n32 + 3), a
	ret

; HL = адрес i32
ld_i32:
	ld	de, n32
	ld	b, 4
l32:
	ld	a, (hl)
	ld	(de), a
	inc	hl
	inc	de
	dec	b
	jp	nz, l32
	ret

ui_tankc:
	ld	hl, (ui_p)
	ld	de, PLY_IDX
	add	hl, de
	ld	a, (hl)
	add	a, 3
	ret

; HL += ui_p
add_ui_p:
	ld	a, (ui_p)
	ld	e, a
	ld	a, (ui_p + 1)
	ld	d, a
	add	hl, de
	ret

add_ui_ps:
	ld	a, (ui_ps)
	ld	e, a
	ld	a, (ui_ps + 1)
	ld	d, a
	add	hl, de
	ret

add_ui_menu:
	ld	a, (ui_menu)
	ld	e, a
	ld	a, (ui_menu + 1)
	ld	d, a
	add	hl, de
	ret

; HL := HL - A (A = индекс имени, HL = индекс*16)
dp_wsub:
	ld	e, a
	ld	d, 0
	ld	a, l
	sub	e
	ld	l, a
	ld	a, h
	sbc	a, d
	ld	h, a
	ret

draw_panel:
	call	clear_panel
	ld	a, (ui_p)
	ld	l, a
	ld	a, (ui_p + 1)
	ld	h, a
	ld	a, h
	or	l
	ret	z
	call	ui_tankc
	ld	b, a
	xor	a
	ld	c, 0
	call	ui_at
	ld	hl, (ui_p)
	ld	b, 13
	call	ui_padr_name
	ld	a, 21
	ld	c, 0
	ld	b, 2
	call	ui_at
	ld	hl, s_wind
	call	ui_zstr
	call	fmt_wind
	ld	hl, ui_num
	ld	b, 6
	call	ui_padl
	; строка ANG
	xor	a
	ld	c, 1
	ld	b, 2
	call	ui_at
	ld	hl, s_ang
	call	ui_zstr
	call	fmt_ang
	ld	hl, ui_num
	ld	b, 3
	call	ui_padr
	ld	hl, s_pow
	call	ui_zstr
	ld	hl, (ui_p)
	ld	de, PLY_POW
	add	hl, de
	call	ld_i16
	call	ui_itoa
	ld	hl, ui_num
	ld	b, 4
	call	ui_padr
	ld	hl, s_men
	call	ui_zstr
	ld	hl, (ui_p)
	ld	de, PLY_MEN
	add	hl, de
	call	ld_i16
	ld	a, (n32 + 3)
	and	0x80
	jp	z, dp_men
	xor	a
	ld	(n32), a
	ld	(n32 + 1), a
	ld	(n32 + 2), a
	ld	(n32 + 3), a
dp_men:
	call	ui_itoa
	ld	hl, ui_num
	ld	b, 3
	call	ui_padl
	; оружие
	xor	a
	ld	c, 2
	ld	b, 2
	call	ui_at
	ld	hl, (ui_p)
	ld	de, PLY_WPN
	add	hl, de
	ld	a, (hl)
	push	af
	ld	l, a
	ld	h, 0
	add	hl, hl
	add	hl, hl
	add	hl, hl
	add	hl, hl
	pop	af
	call	dp_wsub
	ld	de, wpn_names
	add	hl, de
	ld	c, 15
	ld	b, 15
	call	ui_padr
	ld	hl, s_x
	call	ui_zstr
	ld	hl, (ui_p)
	ld	de, PLY_WPN
	add	hl, de
	ld	a, (hl)
	ld	l, a
	ld	h, 0
	add	hl, hl
	ld	de, PLY_AMMO
	add	hl, de
	call	add_ui_p
	call	ld_i16
	call	ui_itoa
	ld	hl, ui_num
	ld	b, 5
	call	ui_padr
	; H если herb > 0
	ld	hl, (ui_p)
	ld	de, PLY_HERB
	add	hl, de
	ld	a, (hl)
	inc	hl
	ld	h, (hl)
	ld	l, a
	ld	a, h
	or	a
	jp	m, dp_vick
	or	l
	jp	z, dp_vick
	ld	a, 26
	ld	c, 2
	ld	b, 2
	call	ui_at
	ld	hl, (ui_p)
	ld	de, PLY_GD
	add	hl, de
	ld	a, (hl)
	and	1
	ld	a, ' '
	jp	z, dp_hch
	ld	a, '*'
dp_hch:
	ld	(ch), a
	call	draw_char
	ld	a, (ch_col)
	inc	a
	ld	(ch_col), a
	ld	a, 'H'
	ld	(ch), a
	call	draw_char
dp_vick:
	ld	hl, (ui_p)
	ld	de, PLY_VICK
	add	hl, de
	ld	a, (hl)
	inc	hl
	ld	h, (hl)
	ld	l, a
	ld	a, h
	or	a
	ret	m
	or	l
	ret	z
	ld	a, 29
	ld	c, 2
	ld	b, 2
	call	ui_at
	ld	hl, (ui_p)
	ld	de, PLY_GD
	add	hl, de
	ld	a, (hl)
	and	2
	ld	a, ' '
	jp	z, dp_vch
	ld	a, '*'
dp_vch:
	ld	(ch), a
	call	draw_char
	ld	a, (ch_col)
	inc	a
	ld	(ch_col), a
	ld	a, 'V'
	ld	(ch), a
	jp	draw_char

fmt_wind:
	ld	hl, (ui_wind)
	ld	a, h
	or	l
	jp	nz, fw_nz
	ld	a, '0'
	ld	(ui_num), a
	ld	c, 1
	ret
fw_nz:
	ld	a, h
	and	0x80
	jp	z, fw_pos
	; '<' + abs
	ld	a, l
	cpl
	ld	l, a
	ld	a, h
	cpl
	ld	h, a
	inc	hl
	ld	a, l
	ld	(n32), a
	ld	a, h
	ld	(n32 + 1), a
	xor	a
	ld	(n32 + 2), a
	ld	(n32 + 3), a
	call	ui_itoa
	; insert '<' at start: shift right
	ld	b, c
	inc	b
	ld	hl, ui_num
	ld	e, c
	ld	d, 0
	add	hl, de
fw_sh:
	dec	hl
	ld	a, (hl)
	inc	hl
	ld	(hl), a
	dec	hl
	dec	c
	jp	nz, fw_sh
	ld	a, '<'
	ld	(hl), a
	ld	c, b
	ret
fw_pos:
	ld	a, l
	ld	(n32), a
	ld	a, h
	ld	(n32 + 1), a
	xor	a
	ld	(n32 + 2), a
	ld	(n32 + 3), a
	call	ui_itoa
	ld	hl, ui_num
	ld	b, 0
	ld	e, c
	ld	d, 0
	add	hl, de
	ld	a, '>'
	ld	(hl), a
	inc	c
	ret

fmt_ang:
	ld	hl, (ui_p)
	ld	de, PLY_ANG
	add	hl, de
	call	ld_i16
	call	ui_itoa
	ld	hl, (ui_p)
	ld	de, PLY_FAC
	add	hl, de
	ld	a, (hl)
	or	a
	jp	p, fa_rt
	; '<' + digits
	ld	b, c
	inc	b
	ld	hl, ui_num
	ld	e, c
	ld	d, 0
	add	hl, de
fa_sh:
	dec	hl
	ld	a, (hl)
	inc	hl
	ld	(hl), a
	dec	hl
	dec	c
	jp	nz, fa_sh
	ld	a, '<'
	ld	(hl), a
	ld	c, b
	ret
fa_rt:
	ld	hl, ui_num
	ld	e, c
	ld	d, 0
	add	hl, de
	ld	a, '>'
	ld	(hl), a
	inc	c
	ret

draw_results:
	call	clear_screen
	ld	a, 1
	call	draw_frame
	ld	a, (ui_round)
	ld	c, a
	ld	a, (ui_rounds)
	cp	c
	jp	z, dr_last
	jp	c, dr_last
	ld	a, 2
	ld	c, 5
	ld	b, 2
	call	ui_at
	ld	hl, s_after
	call	ui_zstr
	ld	a, (ui_round)
	ld	(n32), a
	xor	a
	ld	(n32 + 1), a
	ld	(n32 + 2), a
	ld	(n32 + 3), a
	call	ui_itoa
	ld	hl, ui_num
	ld	b, c
	ex	de, hl
	call	draw_text
	ld	hl, s_of
	call	ui_zstr
	ld	a, (ui_rounds)
	ld	(n32), a
	xor	a
	ld	(n32 + 1), a
	ld	(n32 + 2), a
	ld	(n32 + 3), a
	call	ui_itoa
	ld	hl, ui_num
	ld	b, c
	ex	de, hl
	call	draw_text
	jp	dr_hdr
dr_last:
	ld	a, 2
	ld	c, 5
	ld	b, 2
	call	ui_at
	ld	hl, s_final
	call	ui_zstr
dr_hdr:
	ld	a, 2
	ld	c, 8
	ld	b, 2
	call	ui_at
	ld	hl, s_hdr
	call	ui_zstr
	xor	a
	ld	(ui_i), a
dr_pl:
	ld	a, (ui_i)
	ld	c, a
	ld	a, (ui_n)
	cp	c
	jp	z, dr_mon
	jp	c, dr_mon
	ld	a, (ui_i)
	add	a, a
	add	a, 10
	ld	(ui_row), a
	ld	a, 2
	ld	c, a
	ld	a, (ui_row)
	ld	c, a
	ld	b, 2
	ld	a, 2
	call	ui_at
	ld	a, (ui_i)
	inc	a
	ld	(n32), a
	xor	a
	ld	(n32 + 1), a
	ld	(n32 + 2), a
	ld	(n32 + 3), a
	call	ui_itoa
	ld	hl, ui_num
	ld	b, c
	ex	de, hl
	call	draw_text
	call	ui_ply_i
	ld	(ui_p), hl
	call	ui_tankc
	ld	b, a
	ld	a, 4
	ld	c, a
	ld	a, (ui_row)
	ld	c, a
	ld	a, 4
	call	ui_at
	ld	hl, (ui_p)
	ld	b, 13
	call	ui_padr_name
	ld	a, 18
	ld	c, a
	ld	a, (ui_row)
	ld	c, a
	ld	b, 2
	ld	a, 18
	call	ui_at
	ld	hl, (ui_p)
	ld	de, PLY_WINS
	add	hl, de
	call	ld_i16
	call	ui_itoa
	ld	hl, ui_num
	ld	b, 4
	call	ui_padl
	ld	hl, (ui_p)
	ld	de, PLY_SCORE
	add	hl, de
	call	ld_i32
	call	ui_itoa
	ld	hl, ui_num
	ld	b, 7
	call	ui_padl
	ld	a, (ui_i)
	inc	a
	ld	(ui_i), a
	jp	dr_pl
dr_mon:
	ld	a, 2
	ld	c, 20
	ld	b, 2
	call	ui_at
	ld	hl, s_money
	call	ui_zstr
	xor	a
	ld	(ui_i), a
dr_ml:
	ld	a, (ui_i)
	ld	c, a
	ld	a, (ui_n)
	cp	c
	jp	z, dr_foot
	jp	c, dr_foot
	call	ui_ply_i
	ld	(ui_p), hl
	call	ui_money
	call	ui_itoa
	call	ui_tankc
	ld	b, a
	ld	a, (ui_i)
	ld	c, a
	add	a, a
	add	a, c
	add	a, a			; *6
	add	a, 8
	ld	c, 20
	call	ui_at
	ld	a, (ui_nlen)
	ld	c, a
	ld	hl, ui_num
	ld	b, 5
	call	ui_padl
	ld	a, (ui_i)
	inc	a
	ld	(ui_i), a
	jp	dr_ml
dr_foot:
	ld	a, (ui_round)
	ld	c, a
	ld	a, (ui_rounds)
	cp	c
	jp	z, dr_go
	jp	c, dr_go
	ld	a, 2
	ld	c, 28
	ld	b, 2
	call	ui_at
	ld	hl, s_press
	jp	ui_zstr
dr_go:
	ld	a, 2
	ld	c, 28
	ld	b, 2
	call	ui_at
	ld	hl, s_over
	jp	ui_zstr

ui_ply_i:
	ld	a, (ui_i)
	ld	l, a
	ld	h, 0
	add	hl, hl
	add	hl, hl
	add	hl, hl
	add	hl, hl			; *16
	ld	e, l
	ld	d, h
	add	hl, hl
	add	hl, hl			; *64
	add	hl, de			; *80
	jp	add_ui_ps

; score - spent → n32
ui_money:
	ld	hl, (ui_p)
	ld	de, PLY_SCORE
	add	hl, de
	call	ld_i32
	ld	hl, (ui_p)
	ld	de, PLY_SPENT
	add	hl, de
	ld	de, p32
	ld	b, 4
um_cp:
	ld	a, (hl)
	ld	(de), a
	inc	hl
	inc	de
	dec	b
	jp	nz, um_cp
	jp	ui_sub32

draw_shop:
	call	clear_screen
	xor	a
	ld	c, 0
	ld	b, 2
	call	ui_at
	ld	hl, s_shop
	call	ui_zstr
	call	ui_tankc
	ld	b, a
	ld	a, 5
	ld	c, 0
	call	ui_at
	ld	hl, (ui_p)
	ld	b, 13
	call	ui_padr_name
	xor	a
	ld	c, 1
	ld	b, 2
	call	ui_at
	ld	hl, s_moneys
	call	ui_zstr
	call	ui_money
	; n32 -= cart
	ld	a, (ui_cart)
	ld	(p32), a
	ld	a, (ui_cart + 1)
	ld	(p32 + 1), a
	rla
	sbc	a, a
	ld	(p32 + 2), a
	ld	(p32 + 3), a
	call	ui_sub32
	call	ui_itoa
	ld	hl, ui_num
	ld	b, 6
	call	ui_padl
	ld	hl, s_cart
	call	ui_zstr
	ld	a, (ui_cart)
	ld	(n32), a
	ld	a, (ui_cart + 1)
	ld	(n32 + 1), a
	rla
	sbc	a, a
	ld	(n32 + 2), a
	ld	(n32 + 3), a
	call	ui_itoa
	ld	hl, ui_num
	ld	b, 6
	call	ui_padl
	ld	a, 2
	ld	c, 3
	ld	b, 2
	call	ui_at
	ld	hl, s_item
	call	ui_zstr
	xor	a
	ld	(ui_i), a
ds_lp:
	ld	a, (ui_i)
	ld	c, a
	ld	a, (ui_nmenu)
	cp	c
	jp	z, ds_btns
	jp	c, ds_btns
	ld	a, (ui_i)
	add	a, 4
	ld	(ui_row), a
	ld	a, (ui_sel)
	ld	c, a
	ld	a, (ui_i)
	cp	c
	ld	a, ' '
	jp	nz, ds_cur
	ld	a, '>'
ds_cur:
	ld	(ch), a
	xor	a
	ld	c, a
	ld	a, (ui_row)
	ld	c, a
	ld	b, 2
	xor	a
	call	ui_at
	call	draw_char
	ld	a, 2
	ld	c, a
	ld	a, (ui_row)
	ld	c, a
	ld	b, 2
	ld	a, 2
	call	ui_at
	call	ds_item
	ld	a, (ui_i)
	inc	a
	ld	(ui_i), a
	jp	ds_lp
ds_btns:
	ld	a, (ui_nmenu)
	add	a, 5
	ld	(ui_row), a
	ld	a, (ui_sel)
	ld	c, a
	ld	a, (ui_nmenu)
	cp	c
	ld	a, ' '
	jp	nz, ds_b1
	ld	a, '>'
ds_b1:
	ld	(ch), a
	xor	a
	ld	c, a
	ld	a, (ui_row)
	ld	c, a
	ld	b, 2
	xor	a
	call	ui_at
	call	draw_char
	ld	a, (ch_col)
	inc	a
	ld	(ch_col), a
	ld	hl, s_buy
	call	ui_zstr
	ld	a, (ui_nmenu)
	inc	a
	ld	c, a
	ld	a, (ui_sel)
	cp	c
	ld	a, ' '
	jp	nz, ds_b2
	ld	a, '>'
ds_b2:
	ld	(ch), a
	ld	a, 10
	ld	c, a
	ld	a, (ui_row)
	ld	c, a
	ld	b, 2
	ld	a, 10
	call	ui_at
	call	draw_char
	ld	a, (ch_col)
	inc	a
	ld	(ch_col), a
	ld	hl, s_done
	jp	ui_zstr

; строка товара: padR name 15 + padL price 6 + padL have 6 + padL qty 3
ds_item:
	ld	a, (ui_i)
	ld	l, a
	ld	h, 0
	add	hl, hl
	add	hl, hl			; *4 cat,i,qtylo,qtyhi
	call	add_ui_menu
	ld	a, (hl)
	ld	(ui_cat), a
	inc	hl
	ld	a, (hl)
	ld	(ui_idx), a
	inc	hl
	ld	(ui_qptr), hl
	call	ds_name
	ld	c, 15
	ld	b, 15
	call	ui_padr
	call	ds_price
	call	ui_itoa
	ld	hl, ui_num
	ld	b, 6
	call	ui_padl
	call	ds_have
	call	ui_itoa
	ld	hl, ui_num
	ld	b, 6
	call	ui_padl
	ld	hl, (ui_qptr)
	ld	a, (hl)
	inc	hl
	or	(hl)
	dec	hl
	jp	nz, ds_qty
	ld	c, 0
	ld	b, 3
	ld	hl, ui_num
	jp	ui_padl
ds_qty:
	call	ld_i16
	call	ui_itoa
	ld	hl, ui_num
	ld	b, 3
	jp	ui_padl

ds_name:
	ld	a, (ui_cat)
	or	a
	jp	nz, dn_s
	ld	a, (ui_idx)
	ld	l, a
	ld	h, 0
	add	hl, hl
	add	hl, hl
	add	hl, hl
	add	hl, hl
	call	dp_wsub_a
	ld	de, wpn_names
	add	hl, de
	ret
dn_s:
	cp	1
	jp	nz, dn_s2
	ld	a, (ui_idx)
	ld	l, a
	ld	h, 0
	add	hl, hl
	add	hl, hl
	add	hl, hl
	add	hl, hl
	call	dp_wsub_a
	ld	de, shop_n1
	add	hl, de
	ret
dn_s2:
	ld	a, (ui_idx)
	ld	l, a
	ld	h, 0
	add	hl, hl
	add	hl, hl
	add	hl, hl
	add	hl, hl
	call	dp_wsub_a
	ld	de, shop_n2
	add	hl, de
	ret

dp_wsub_a:
	ld	a, (ui_idx)
	ld	e, a
	ld	d, 0
	ld	a, l
	sub	e
	ld	l, a
	ld	a, h
	sbc	a, d
	ld	h, a
	ret

ds_price:
	ld	a, (ui_cat)
	or	a
	jp	nz, dp_c1
	ld	a, (ui_idx)
	ld	l, a
	ld	h, 0
	add	hl, hl
	ld	de, wpn_price
	add	hl, de
	jp	ld_i16
dp_c1:
	cp	1
	jp	nz, dp_c2
	ld	a, (ui_idx)
	ld	l, a
	ld	h, 0
	add	hl, hl
	ld	de, shop_p1
	add	hl, de
	jp	ld_i16
dp_c2:
	ld	a, (ui_idx)
	ld	l, a
	ld	h, 0
	add	hl, hl
	ld	de, shop_p2
	add	hl, de
	jp	ld_i16

ds_have:
	ld	a, (ui_cat)
	or	a
	jp	nz, dh_c1
	ld	a, (ui_idx)
	ld	l, a
	ld	h, 0
	add	hl, hl
	ld	de, PLY_AMMO
	add	hl, de
	call	add_ui_p
	jp	ld_i16
dh_c1:
	cp	1
	jp	nz, dh_c2
	ld	a, (ui_idx)
	or	a
	jp	nz, dh_vick
	ld	hl, (ui_p)
	ld	de, PLY_HERB
	add	hl, de
	jp	ld_i16
dh_vick:
	ld	hl, (ui_p)
	ld	de, PLY_VICK
	add	hl, de
	jp	ld_i16
dh_c2:
	ld	a, (ui_idx)
	or	a
	jp	nz, dh_damp
	ld	hl, (ui_p)
	ld	de, PLY_SHLD
	add	hl, de
	jp	ld_i16
dh_damp:
	ld	hl, (ui_p)
	ld	de, PLY_DAMP
	add	hl, de
	jp	ld_i16

draw_panel_end:
draw_results_end:
draw_shop_end:

s_wind:	db	"WIND ", 0
s_ang:	db	"ANG ", 0
s_pow:	db	"  POW ", 0
s_men:	db	"  MEN ", 0
s_x:	db	" x", 0
s_after:	db	"AFTER ROUND ", 0
s_of:	db	" OF ", 0
s_final:	db	"FINAL RESULTS", 0
s_hdr:	db	"# PLAYER        WINS  SCORE", 0
s_money:	db	"MONEY", 0
s_press:	db	"PRESS ANY KEY", 0
s_over:	db	"GAME OVER", 0
s_shop:	db	"SHOP", 0
s_moneys:	db	"MONEY ", 0
s_cart:	db	"   CART ", 0
s_item:	db	"ITEM            PRICE  HAVE BUY", 0
s_buy:	db	" BUY", 0
s_done:	db	" DONE", 0

pow10:
	db	0x80, 0x96, 0x98, 0x00	; 10000000
	db	0x40, 0x42, 0x0F, 0x00
	db	0xA0, 0x86, 0x01, 0x00
	db	0x10, 0x27, 0x00, 0x00
	db	0xE8, 0x03, 0x00, 0x00
	db	0x64, 0x00, 0x00, 0x00
	db	0x0A, 0x00, 0x00, 0x00
	db	0x01, 0x00, 0x00, 0x00

n32:	db	0, 0, 0, 0
p32:	db	0, 0, 0, 0
it_pw:	dw	0
it_out:	dw	0
it_dg:	db	0
it_nz:	db	0
ui_p:	dw	0
ui_ps:	dw	0
ui_wind:	dw	0
ui_round:	db	0
ui_rounds:	db	0
ui_n:	db	0
ui_i:	db	0
ui_row:	db	0
ui_cart:	dw	0
ui_sel:	db	0
ui_nmenu:	db	0
ui_menu:	dw	0
ui_cat:	db	0
ui_idx:	db	0
ui_qptr:	dw	0
ui_nlen:	db	0
ui_buf:	ds	32
ui_num:	ds	16
