; Магазин человека (только игровой образ): меню и оплата — подпрограммы магазина ИИ (shop.asm), экран — show_shop.
;   human_shop: вход A = место игрока. Денег меньше 3000 — сразу выход.
; Строки: позиции 0..count−1, затем BUY (count) и DONE (count+1). Клавиши: вверх/вниз — строка, вправо или огонь на
; позиции — ещё одна пачка (не больше 9 и пока хватает денег), влево — убрать пачку; огонь на BUY — оплатить и
; построить меню заново; огонь на DONE — оплатить и выйти.

human_shop:
	ld	(hs_place), a
	call	hs_money
	ld	hl, sh_money
	ld	de, sh_left
	ld	b, 4
	call	gm_copy
	ld	hl, sh_left
	call	sh_sub32_3000
	ret	m			; денег меньше 3000
hs_reset:
	call	hs_money
	call	sh_menu
	ld	hl, 0
	ld	(sh_cart), hl
	ld	(sh_cart + 2), hl
	xor	a
	ld	(hs_sel), a
	ld	(su_part), a		; экран целиком
hs_draw:
	ld	a, (hs_sel)
	ld	(su_sel), a
	ld	a, (hs_place)
	call	show_shop
hs_wait:
	ld	a, PH_SHOP
	ld	(g_phase), a
	call	get_key
	ld	b, a
	ld	a, PH_BUSY
	ld	(g_phase), a
	ld	a, (sh_count)
	inc	a
	ld	c, a			; C = номер строки DONE
	ld	a, b
	cp	3
	jp	z, hs_down
	cp	4
	jp	z, hs_up
	cp	1
	jp	z, hs_minus
	cp	2
	jp	z, hs_plus
	cp	5
	jp	nz, hs_wait
	; огонь: на позиции — плюс, на BUY — оплата и заново, на DONE — оплата и выход
	ld	a, (hs_sel)
	cp	c
	jp	z, sh_commit
	inc	a
	cp	c
	jp	nz, hs_plus
	call	sh_commit
	jp	hs_reset
hs_down:
	ld	a, (hs_sel)
	cp	c
	jp	nz, hs_d1
	ld	a, 0xFF
hs_d1:
	inc	a
hs_mv:					; курсор на строку A: перерисовать только курсор
	ld	b, a
	ld	a, (hs_sel)
	ld	(su_old), a
	ld	a, b
	ld	(hs_sel), a
	ld	a, 1
	ld	(su_part), a
	jp	hs_draw
hs_up:
	ld	a, (hs_sel)
	or	a
	jp	nz, hs_u1
	ld	a, c
	inc	a
hs_u1:
	dec	a
	jp	hs_mv
hs_plus:
	call	hs_item
	jp	nc, hs_wait		; не позиция
	ld	a, (hl)
	cp	9
	jp	nc, hs_wait
	call	sh_calc_left
	ld	hl, (sh_price)
	ex	de, hl
	ld	hl, sh_left
	call	sh_le32
	jp	c, hs_wait		; не хватает денег
	ld	hl, (hs_q)
	inc	(hl)
	ld	hl, sh_cart
	ld	a, (sh_price)
	add	a, (hl)
	ld	(hl), a
	inc	hl
	ld	a, (sh_price + 1)
	adc	a, (hl)
	ld	(hl), a
	inc	hl
	ld	a, 0
	adc	a, (hl)
	ld	(hl), a
	inc	hl
	ld	a, 0
	adc	a, (hl)
	ld	(hl), a
hs_chg:					; изменилось количество: строка денег и строка позиции
	ld	a, 2
	ld	(su_part), a
	jp	hs_draw
hs_minus:
	call	hs_item
	jp	nc, hs_wait
	ld	a, (hl)
	or	a
	jp	z, hs_wait
	dec	(hl)
	ld	hl, sh_cart
	ld	a, (sh_price)
	ld	b, a
	ld	a, (hl)
	sub	b
	ld	(hl), a
	inc	hl
	ld	a, (sh_price + 1)
	ld	b, a
	ld	a, (hl)
	sbc	a, b
	ld	(hl), a
	inc	hl
	ld	a, (hl)
	sbc	a, 0
	ld	(hl), a
	inc	hl
	ld	a, (hl)
	sbc	a, 0
	ld	(hl), a
	jp	hs_chg

; sh_pp и sh_money игрока hs_place
hs_money:
	ld	a, (hs_place)
	call	sh_find
	ld	hl, (sh_pp)
	ld	de, PL_SPENT
	add	hl, de
	jp	sh_sub_score
; выбранная позиция: CF = 1, если hs_sel — позиция меню; тогда HL = адрес её количества (и в hs_q), sh_price = цена
hs_item:
	ld	a, (sh_count)
	ld	b, a
	ld	a, (hs_sel)
	cp	b
	ret	nc
	ld	e, a
	ld	d, 0
	ld	hl, sh_num
	add	hl, de
	ld	c, (hl)			; номер
	ld	hl, sh_cat
	add	hl, de
	ld	a, (hl)			; категория
	ld	hl, sh_qty
	add	hl, de
	ld	(hs_q), hl
	ld	hl, sh_wprice
	or	a
	jp	z, hs_i1
	ld	hl, sh_gprice
	dec	a
	jp	z, hs_i1
	ld	hl, sh_dprice
hs_i1:
	ld	b, 0
	add	hl, bc
	add	hl, bc
	ld	a, (hl)
	inc	hl
	ld	h, (hl)
	ld	l, a
	ld	(sh_price), hl
	ld	hl, (hs_q)
	scf
	ret
hshop_end:

hs_place:	db	0
hs_sel:		db	0
hs_q:		dw	0
