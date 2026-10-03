; Осыпание crumbleColumns(v, bg=0) и замена временного цвета 3 на 0 (replaceTmp, o=65535..1).

crumble:
	xor	a
	ld	(cr_x), a
cr_xloop:
	ld	a, 0xFF
	ld	(cr_fl), a		; floor=-1 как 0xFF флаг в cr_ff
	xor	a
	ld	(cr_ff), a		; 0 = нет пола
	ld	a, 255
	ld	(cr_y), a
cr_yloop:
	ld	a, (cr_x)
	ld	d, a
	ld	a, (cr_y)
	ld	e, a
	call	getpixel
	ld	b, a
	or	a
	jp	nz, cr_not0
	ld	a, (cr_ff)
	or	a
	jp	nz, cr_yn
	ld	a, (cr_y)
	ld	(cr_fl), a
	ld	a, 1
	ld	(cr_ff), a
	jp	cr_yn
cr_not0:
	ld	a, b
	cp	1
	jp	nz, cr_reset
	ld	a, (cr_ff)
	or	a
	jp	z, cr_reset
	ld	a, (cr_y)
	cp	254
	jp	nc, cr_reset		; y<=253
	; o>0: не (0,0)
	ld	a, (cr_x)
	or	a
	jp	nz, cr_move
	ld	a, (cr_y)
	or	a
	jp	z, cr_reset
cr_move:
	ld	a, (cr_x)
	ld	d, a
	ld	a, (cr_y)
	ld	e, a
	xor	a
	call	putpixel
	ld	a, (cr_x)
	ld	d, a
	ld	a, (cr_fl)
	ld	e, a
	ld	a, 1
	call	putpixel
	ld	a, (cr_fl)
	dec	a
	ld	(cr_fl), a
	jp	cr_yn
cr_reset:
	xor	a
	ld	(cr_ff), a
cr_yn:
	ld	a, (cr_y)
	or	a
	jp	z, cr_xn
	dec	a
	ld	(cr_y), a
	jp	cr_yloop
cr_xn:
	ld	a, (cr_x)
	inc	a
	ld	(cr_x), a
	jp	nz, cr_xloop
	ret
crumble_end:

; Заменить цвет 3 на 0 для o=65535..1 (точку (0,0) не трогать).
replace_tmp:
	ld	d, 0
	ld	e, 0
rt_lp:
	inc	d
	jp	nz, rt_go
	inc	e
	ld	a, e
	or	d
	ret	z			; wrap 65536 → конец (после 255,255)
rt_go:
	; (d,e)=(x,y) после inc x; если x wrapped, y++
	; wait: we start 0,0 then inc d first → (1,0) ... skip (0,0). After (255,y) inc d → 0, inc e.
	; When (255,255): inc d → 0, inc e → 0, a=0 ret. We processed (255,255). Never (0,0). Good.
	; BUG: after (255,y) we inc d to 0 then jp nz fails, inc e. We need to process (0, y+1) not skip.
	; Current: from (255,y) inc d → 0 ZF, inc e. Then rt_go with (0, y+1). Falls through to getpixel. Good.
	; Start: d=0,e=0, first inc d → 1, process (1,0). Skip (0,0). Good.
	call	rt_one
	jp	rt_lp
rt_one:
	push	de
	call	getpixel
	cp	3
	jp	nz, rt_no
	pop	de
	push	de
	xor	a
	call	putpixel
rt_no:
	pop	de
	ret
replace_tmp_end:

cr_x:	db	0
cr_y:	db	0
cr_fl:	db	0
cr_ff:	db	0
