; Осыпание crumbleColumns(v, bg=0): байтовые столбцы, поле x 3..252, y 27..253.
; Столбец без «земля над пустотой» пропускается (байты трёх плоскостей).

crumble:
	ld	a, 0xA0
	ld	(cr_ah), a
	xor	a
	ld	(cr_col), a
cr_cols:
	; столбец, в котором после прошлого осыпания ничего не менялось, уже устойчив — пропустить
	ld	a, (cr_col)
	ld	e, a
	ld	d, 0
	ld	hl, cr_dirty
	add	hl, de
	ld	a, (hl)
	or	a
	jp	z, cr_nxt
	ld	(hl), 0
	ld	a, (cr_col)
	or	a
	ld	b, 0x1F
	jp	z, cr_gotm
	cp	31
	ld	b, 0xFF
	jp	nz, cr_gotm
	ld	b, 0xF8
cr_gotm:
	ld	a, b
	ld	(cr_vm), a
	ld	a, (cr_ah)
	ld	h, a
	ld	l, 2
	xor	a
	ld	c, a
	ld	e, a
	ld	(cr_l0), a
; Просмотр столбца снизу вверх: C — «ниже есть пустота» (по битам), E — «земля над пустотой».
; Быстрые пути: пока пустоты нет (C = 0) — пропуск строк сплошной земли; когда пустота во всех битах (C = FFh) —
; пропуск пустых строк. В обоих случаях строка не меняет ни C, ни E.
cr_sk:
	ld	a, c
	or	a
	jp	z, cr_f0
	inc	a
	jp	z, cr_f1
cr_slow:
	ld	a, h
	add	a, 0x20
	ld	h, a
	ld	a, (hl)
	ld	(cr_pc), a
	ld	a, h
	add	a, 0x20
	ld	h, a
	ld	a, (hl)
	ld	(cr_pe), a
	ld	a, h
	sub	0x40
	ld	h, a
	ld	a, (hl)
	ld	(cr_pa), a
	ld	b, a
	ld	a, (cr_pc)
	or	b
	ld	b, a
	ld	a, (cr_pe)
	or	b
	ld	(cr_occ), a
	cpl
	ld	(cr_em), a
	ld	a, (cr_pc)
	cpl
	ld	b, a
	ld	a, (cr_pe)
	cpl
	and	b
	ld	b, a
	ld	a, (cr_pa)
	and	b
	ld	b, a
	and	c
	jp	z, cr_s1
	ld	d, a
	ld	a, l
	ld	(cr_l1), a		; самая верхняя строка с землёй над пустотой
	ld	a, d
cr_s1:
	or	e
	ld	e, a
	ld	a, b
	cpl
	ld	b, a
	ld	a, (cr_occ)
	and	b
	cpl
	and	c
	ld	c, a
	ld	a, (cr_em)
	or	c
	ld	c, a
	inc	l
	ld	a, l
	cp	229
	jp	nz, cr_sk
cr_scend:
	ld	a, (cr_vm)
	and	e
	jp	z, cr_nxt
	ld	(cr_vm), a		; дальше — только те биты, где есть что осыпать
	; Второй проход — по битам маски cr_vm, каждый бит своим столбцом точек от cr_l0 до cr_l1 снизу вверх.
	; cr_slot — нижняя свободная точка, куда упадёт земля (0 — нет). Маска бита вписывается прямо в команды.
	ld	a, (cr_l1)
	inc	a
	ld	(cr_m3 + 1), a
	ld	a, 0x80
cr_b:
	ld	(cr_bit), a
	ld	hl, cr_vm
	and	(hl)
	jp	z, cr_bnx
	ld	(cr_m1 + 1), a
	ld	(cr_m2 + 1), a
	xor	a
	ld	(cr_slot), a
	ld	a, (cr_ah)
	ld	h, a
	ld	a, (cr_l0)
	ld	l, a
	call	cr_ptrs
cr_r:
	ld	a, (bc)			; C000 | E000: занято не землёй
	ex	de, hl
	or	(hl)
	ex	de, hl
cr_m1:
	and	0
	jp	nz, cr_blk
	ld	a, (hl)
cr_m2:
	and	0
	jp	z, cr_fre
	ld	a, (cr_slot)		; земля: есть куда падать — перенести точку
	or	a
	jp	z, cr_nx2
	push	de
	ld	e, a
	ld	a, (cr_bit)
	cpl
	and	(hl)
	ld	(hl), a
	ld	d, l
	ld	l, e
	ld	a, (cr_bit)
	or	(hl)
	ld	(hl), a
	ld	l, d
	inc	e
	ld	a, e
	ld	(cr_slot), a
	pop	de
	jp	cr_nx2
cr_fre:
	ld	a, (cr_slot)
	or	a
	jp	nz, cr_nx2
	ld	a, l
	ld	(cr_slot), a
	jp	cr_nx2
cr_blk:
	xor	a
	ld	(cr_slot), a
cr_nx2:
	inc	l
	inc	e
	inc	c
	ld	a, l
cr_m3:
	cp	0
	jp	nz, cr_r
cr_bnx:
	ld	a, (cr_bit)
	or	a
	rra
	jp	nz, cr_b
	jp	cr_nxt
; C = 0: строки сплошной земли (A000 = FFh, C000 = E000 = 0)
cr_f0:
	ld	a, e
	ld	(cr_e), a
	call	cr_ptrs
cr_f0l:
	ld	a, (hl)
	inc	a
	jp	nz, cr_f0x
	ld	a, (bc)
	ex	de, hl
	or	(hl)
	ex	de, hl
	jp	nz, cr_f0x
	inc	l
	inc	e
	inc	c
	ld	a, l
	cp	229
	jp	nz, cr_f0l
	ld	a, (cr_e)
	ld	e, a
	ld	c, 0
	jp	cr_scend
cr_f0x:
	ld	a, (cr_l0)
	or	a
	jp	nz, cr_f0y
	ld	a, l
	ld	(cr_l0), a		; первая строка, где уже не сплошная земля
cr_f0y:
	ld	a, (cr_e)
	ld	e, a
	ld	c, 0
	jp	cr_slow
; C = FFh: пустые строки (все три плоскости 0)
cr_f1:
	ld	a, e
	ld	(cr_e), a
	call	cr_ptrs
cr_f1l:
	ld	a, (bc)
	ex	de, hl
	or	(hl)
	ex	de, hl
	or	(hl)
	jp	nz, cr_f1x
	inc	l
	inc	e
	inc	c
	ld	a, l
	cp	229
	jp	nz, cr_f1l
	ld	a, (cr_e)
	ld	e, a
	ld	c, 0xFF
	jp	cr_scend
cr_f1x:
	ld	a, (cr_e)
	ld	e, a
	ld	c, 0xFF
	jp	cr_slow
; DE и BC — та же строка в плоскостях C000 и E000 (HL — в A000)
cr_ptrs:
	ld	e, l
	ld	c, l
	ld	a, h
	add	a, 0x20
	ld	d, a
	add	a, 0x20
	ld	b, a
	ret
cr_nxt:
	ld	a, (cr_ah)
	inc	a
	ld	(cr_ah), a
	ld	a, (cr_col)
	inc	a
	ld	(cr_col), a
	cp	32
	jp	nz, cr_cols
	ret
; --- Пометки «столбец байтов менялся» (cr_dirty, 32 байта). Осыпание смотрит только помеченные столбцы.
; Помечать обязан каждый, кто меняет точки поля: круг (взрыв, грязь) — свой диапазон; мяч, прошедший сквозь землю;
; ствол танка; всё редкое (начало раунда, падение танка, гибель, лазер, особое оружие) — весь экран.
cr_mark_all:
	ld	hl, cr_dirty
	ld	b, 32
	ld	a, 1
cr_ma1:
	ld	(hl), a
	inc	hl
	dec	b
	jp	nz, cr_ma1
	ret
; точки x от D до E включительно (0..255, D <= E)
cr_mark_span:
	ld	a, e
	rrca
	rrca
	rrca
	and	0x1F
	ld	e, a
	ld	a, d
	rrca
	rrca
	rrca
	and	0x1F
	ld	d, a
	ld	c, a
	ld	b, 0
	ld	hl, cr_dirty
	add	hl, bc
	ld	a, e
	sub	d
	inc	a
	ld	b, a
	ld	a, 1
	jp	cr_ma1
; точки x от A − B до A + B с обрезкой по экрану
cr_mark_x:
	ld	c, a
	sub	b
	jp	nc, cr_mx1
	xor	a
cr_mx1:
	ld	d, a
	ld	a, c
	add	a, b
	jp	nc, cr_mx2
	ld	a, 255
cr_mx2:
	ld	e, a
	jp	cr_mark_span
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
	ret	z
rt_go:
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

cr_ah:	db	0
cr_col:	db	0
cr_vm:	db	0
cr_pa:	db	0
cr_pc:	db	0
cr_pe:	db	0
cr_occ:	db	0
cr_em:	db	0
cr_l:	db	0
cr_bit:	db	0
cr_bi:	db	0
cr_n:	db	0
cr_e:		db	0
cr_dirty:	ds	32, 1			; в начале помечено всё
cr_slot:	db	0
cr_l0:		db	0
cr_l1:		db	0
cr_fl:	ds	8
