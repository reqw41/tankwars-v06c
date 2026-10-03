; Магазин компьютерного игрока — aiShop() эталона web/tankwars.js (вместе с shopMenu, aiChoice, shopCommit).
; Вход: A = место игрока 1..n (запись в players). Стратегия закупки — поле PL_STRAT записи (0..4).
; Выход: изменённая запись (PL_SPENT, запасы).
; Стиль — action.asm/match.asm: значения держу в ячейках после таблиц; подпрограммы портят AF, BC, DE, HL.

ai_shop:
	call	sh_find			; sh_pp = запись игрока
	; money = score - spent
	ld	hl, (sh_pp)
	ld	de, PL_SPENT
	add	hl, de
	call	sh_sub_score		; sh_money = score - spent
	; money < 3000 -> выйти (считаю знак в черновике sh_left, sh_money цел)
	ld	hl, sh_money
	ld	de, sh_left
	ld	b, 4
sh_cp1:
	ld	a, (hl)
	ld	(de), a
	inc	hl
	inc	de
	dec	b
	jp	nz, sh_cp1
	ld	hl, sh_left
	call	sh_sub32_3000
	jp	m, sh_ret
	; стратегия 0 -> выйти
	ld	hl, (sh_pp)
	ld	de, PL_STRAT
	add	hl, de
	ld	a, (hl)
	or	a
	jp	z, sh_ret
	call	sh_menu			; позиции в sh_cat/sh_num/sh_qty, число в sh_count
	xor	a
	ld	(sh_cart), a
	ld	(sh_cart + 1), a
	ld	(sh_cart + 2), a
	ld	(sh_cart + 3), a
	; покупки: не больше 10000 повторов
	ld	hl, 10000
	ld	(sh_step), hl
sh_buy_lp:
	ld	hl, (sh_step)
	dec	hl
	ld	(sh_step), hl
	call	sh_choice		; sh_sel = позиция или 0xFF = «нет»
	ld	a, (sh_sel)
	cp	0xFF
	jp	z, sh_commit
	inc	a			; выход и при sel == count (пустое меню, sel = 0)
	ld	c, a
	ld	b, 0
	ld	hl, sh_count
	ld	a, (hl)
	cp	c
	jp	c, sh_commit		; как !menu[sel] в эталоне
	; категория и номер позиции sel -> sh_selcat/sh_selnum, цена -> sh_price
	ld	a, (sh_sel)
	ld	c, a
	ld	b, 0
	ld	hl, sh_cat
	add	hl, bc
	ld	a, (hl)
	ld	(sh_selcat), a
	or	a
	jp	z, sh_by_pw
	cp	1
	jp	z, sh_by_pg
	ld	hl, sh_dprice
	jp	sh_by_ptab
sh_by_pw:
	ld	hl, sh_wprice
	jp	sh_by_ptab
sh_by_pg:
	ld	hl, sh_gprice
sh_by_ptab:
	ld	hl, sh_num
	add	hl, bc			; bc = sel (не менялся)
	ld	a, (hl)
	ld	(sh_selnum), a
sh_by_price:
	ld	a, (sh_selcat)
	or	a
	jp	z, sh_bp_w
	cp	1
	jp	z, sh_bp_g
	ld	hl, sh_dprice
	jp	sh_bp_tab
sh_bp_w:
	ld	hl, sh_wprice
	jp	sh_bp_tab
sh_bp_g:
	ld	hl, sh_gprice
sh_bp_tab:
	ld	a, (sh_selnum)
	ld	e, a
	ld	d, 0
	add	hl, de
	add	hl, de
	ld	a, (hl)
	ld	(sh_price), a
	inc	hl
	ld	a, (hl)
	ld	(sh_price + 1), a
	; qty[sel]
	ld	a, (sh_sel)
	ld	c, a
	ld	b, 0
	ld	hl, sh_qty
	add	hl, bc
	ld	a, (hl)
	ld	c, a			; C = qty[sel]
	cp	9
	jp	nc, sh_commit		; qty >= 9 — закончить покупки
	; price <= left, left = money - cart
	call	sh_calc_left
	ld	a, (sh_price)
	ld	e, a
	ld	a, (sh_price + 1)
	ld	d, a
	ld	hl, sh_left
	call	sh_le32
	jp	c, sh_buy_lp		; не влезает — qty не растёт, следующий повтор
	; cart += price; qty[sel]++
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
	ld	a, (sh_sel)
	ld	c, a
	ld	b, 0
	ld	hl, sh_qty
	add	hl, bc
	inc	(hl)
	ld	hl, (sh_step)
	ld	a, h
	or	l
	jp	nz, sh_buy_lp
	jp	sh_commit

; шаг оплаты: для каждой позиции c с qty[c] > 0: spent += цена*qty; запас += пачка*qty
sh_commit:
	xor	a
	ld	(sh_c), a
sh_com_lp:
	ld	a, (sh_c)
	ld	c, a
	ld	b, 0
	ld	hl, sh_count
	ld	a, (hl)
	cp	c
	jp	z, sh_ret
	ld	hl, sh_qty
	add	hl, bc
	ld	a, (hl)
	ld	(sh_tmpa), a		; qty[c]; bc = c цел дальше
	or	a
	jp	z, sh_com_next
	; категория/номер позиции
	ld	hl, sh_cat
	add	hl, bc
	ld	a, (hl)
	ld	(sh_selcat), a
	ld	hl, sh_num
	add	hl, bc
	ld	a, (hl)
	ld	(sh_selnum), a
	; цена * qty -> sh_prod, затем spent += sh_prod
	ld	a, (sh_selcat)
	or	a
	jp	z, sh_cp_w
	cp	1
	jp	z, sh_cp_g
	ld	hl, sh_dprice
	jp	sh_cp_tab
sh_cp_w:
	ld	hl, sh_wprice
	jp	sh_cp_tab
sh_cp_g:
	ld	hl, sh_gprice
sh_cp_tab:
	ld	a, (sh_selnum)
	ld	e, a
	ld	d, 0
	add	hl, de
	add	hl, de
	ld	a, (hl)
	ld	e, a
	inc	hl
	ld	d, (hl)			; DE = цена
	ld	a, (sh_tmpa)
	ld	c, a
	call	sh_muli32
	call	sh_add_spent
	; пачка * qty -> sh_prod, затем запас += sh_prod
	ld	a, (sh_selcat)
	or	a
	jp	z, sh_ck_w
	cp	1
	jp	z, sh_ck_g
	ld	hl, sh_dpack
	jp	sh_ck_tab
sh_ck_w:
	ld	hl, sh_wpack
	jp	sh_ck_tab
sh_ck_g:
	ld	hl, sh_gpack
sh_ck_tab:
	ld	a, (sh_selnum)
	ld	e, a
	ld	d, 0
	add	hl, de
	add	hl, de
	ld	a, (hl)
	ld	e, a
	inc	hl
	ld	d, (hl)			; DE = пачка
	ld	a, (sh_tmpa)
	ld	c, a
	call	sh_muli32
	call	sh_add_have
sh_com_next:
	ld	hl, sh_c
	inc	(hl)
	jp	sh_com_lp

; --- shopMenu: список позиций (категория, номер), не больше 22 ---
sh_menu:
	xor	a
	ld	(sh_count), a
	ld	(sh_w), a
	; оружие 0..17: (запас > 0 или цена <= money) и пачка != 0
sh_mn_w_lp:
	ld	a, (sh_w)
	ld	e, a
	ld	d, 0
	ld	hl, sh_wpack
	add	hl, de
	add	hl, de
	ld	a, (hl)
	inc	hl
	or	(hl)
	jp	z, sh_mn_w_next		; пачка 0 — не продаётся
	; запас[w] > 0 ?
	ld	a, (sh_w)
	ld	e, a
	ld	d, 0
	ld	hl, (sh_pp)
	ld	bc, PL_AMMO
	add	hl, bc
	add	hl, de
	add	hl, de
	ld	a, (hl)
	ld	e, a
	inc	hl
	ld	d, (hl)
	ld	a, d
	or	a
	jp	m, sh_mn_w_price
	jp	nz, sh_mn_w_add
	ld	a, e
	or	a
	jp	nz, sh_mn_w_add
sh_mn_w_price:
	; цена[w] <= money ?
	ld	a, (sh_w)
	ld	e, a
	ld	d, 0
	ld	hl, sh_wprice
	add	hl, de
	add	hl, de
	ld	a, (hl)
	ld	e, a
	inc	hl
	ld	d, (hl)
	ld	hl, sh_money
	call	sh_le32
	jp	c, sh_mn_w_next
sh_mn_w_add:
	ld	a, 0
	ld	(sh_tmpb), a
	ld	a, (sh_w)
	call	sh_push
sh_mn_w_next:
	ld	hl, sh_w
	inc	(hl)
	ld	a, (hl)
	cp	18
	jp	c, sh_mn_w_lp
	; категория 1: herb (номер 0), vick (номер 1)
	ld	a, 1
	ld	(sh_tmpb), a
	call	sh_have16_herb
	jp	z, sh_mn_g_v0p
	ld	a, 0
	call	sh_push
	jp	sh_mn_g_v1
sh_mn_g_v0p:
	ld	de, 20000
	ld	hl, sh_money
	call	sh_le32
	jp	c, sh_mn_g_v1
	ld	a, 0
	call	sh_push
sh_mn_g_v1:
	call	sh_have16_vick
	jp	z, sh_mn_g_v1p
	ld	a, 1
	call	sh_push
	jp	sh_mn_d_s0
sh_mn_g_v1p:
	ld	de, 20000
	ld	hl, sh_money
	call	sh_le32
	jp	c, sh_mn_d_s0
	ld	a, 1
	call	sh_push
	; категория 2: щит (номер 0), демпфер (номер 1)
sh_mn_d_s0:
	ld	a, 2
	ld	(sh_tmpb), a
	call	sh_have32_shield
	jp	z, sh_mn_d_s0p
	ld	a, 0
	call	sh_push
	jp	sh_mn_d_s1
sh_mn_d_s0p:
	ld	de, 20000
	ld	hl, sh_money
	call	sh_le32
	jp	c, sh_mn_d_s1
	ld	a, 0
	call	sh_push
sh_mn_d_s1:
	call	sh_have32_damp
	jp	z, sh_mn_d_s1p
	ld	a, 1
	call	sh_push
	jp	sh_mn_r
sh_mn_d_s1p:
	ld	de, 10000
	ld	hl, sh_money
	call	sh_le32
	jp	c, sh_mn_r
	ld	a, 1
	call	sh_push
sh_mn_r:
	ret

; добавить позицию: A = номер, sh_tmpb = категория; qty = 0
sh_push:
	ld	(sh_tmpa), a
	ld	hl, sh_count
	ld	a, (hl)
	ld	e, a
	ld	d, 0
	ld	hl, sh_cat
	add	hl, de
	ld	a, (sh_tmpb)
	ld	(hl), a
	ld	hl, sh_num
	add	hl, de
	ld	a, (sh_tmpa)
	ld	(hl), a
	ld	hl, sh_qty
	add	hl, de
	xor	a
	ld	(hl), a
	ld	hl, sh_count
	inc	(hl)
	ret

; --- aiChoice: sh_sel = выбранная позиция или 0xFF = «нет» ---
sh_choice:
	call	sh_calc_left		; sh_left = money - cart
	ld	a, 0xFF
	ld	(sh_sel), a
	ld	hl, (sh_pp)
	ld	de, PL_STRAT
	add	hl, de
	ld	a, (hl)
	cp	1
	jp	z, sh_ch_s1
	cp	2
	jp	z, sh_ch_s23
	cp	3
	jp	z, sh_ch_s23
	cp	4
	jp	z, sh_ch_s4
	ret				; стратегия вне 1..4 — «нет»

; стратегия 1: от последней позиции к первой; категория 0, номер 1..4,
; запас[w] + пачка[w]*qty[c] < 20 и цена[w] <= left. Отката на позицию 0 нет.
sh_ch_s1:
	ld	hl, sh_count
	ld	a, (hl)
	or	a
	jp	z, sh_ch_r
	dec	a
	ld	(sh_c), a
sh_ch_s1_lp:
	ld	a, (sh_c)
	ld	c, a
	ld	b, 0
	ld	hl, sh_cat
	add	hl, bc
	ld	a, (hl)
	or	a
	jp	nz, sh_ch_s1_next
	ld	hl, sh_num
	add	hl, bc
	ld	a, (hl)
	cp	1
	jp	c, sh_ch_s1_next
	cp	5
	jp	nc, sh_ch_s1_next
	ld	(sh_selnum), a
	; произведение пачка[w] * qty[c]
	ld	a, (sh_c)
	ld	c, a
	ld	b, 0
	ld	hl, sh_qty
	add	hl, bc
	ld	c, (hl)			; C = qty[c]
	ld	a, (sh_selnum)
	ld	e, a
	ld	d, 0
	ld	hl, sh_wpack
	add	hl, de
	add	hl, de
	ld	a, (hl)
	ld	e, a
	inc	hl
	ld	d, (hl)			; DE = пачка[w]
	call	sh_mul16		; HL = произведение
	ld	(sh_prod), hl
	ld	hl, 0
	ld	(sh_prod + 2), hl
	; + запас[w]
	ld	a, (sh_selnum)
	add	a, a
	ld	e, a
	ld	d, 0
	ld	hl, (sh_pp)
	ld	bc, PL_AMMO
	add	hl, bc
	add	hl, de
	ld	a, (hl)
	ld	e, a
	inc	hl
	ld	d, (hl)			; DE = запас[w]
	ld	hl, (sh_prod)
	add	hl, de			; сумма
	; сумма < 20 (со знаком)?
	ld	a, l
	sub	20
	ld	a, h
	sbc	a, 0
	jp	p, sh_ch_s1_next
	; цена[w] <= left?
	ld	a, (sh_selnum)
	ld	e, a
	ld	d, 0
	ld	hl, sh_wprice
	add	hl, de
	add	hl, de
	ld	a, (hl)
	ld	e, a
	inc	hl
	ld	d, (hl)
	ld	hl, sh_left
	call	sh_le32
	jp	c, sh_ch_s1_next
	ld	a, (sh_c)
	ld	(sh_sel), a
sh_ch_s1_next:
	ld	hl, sh_c
	ld	a, (hl)
	or	a
	ret	z			; первой позиции уже коснулись
	dec	(hl)
	jp	sh_ch_s1_lp

; стратегии 2 (hi = 4) и 3 (hi = 5): от первой позиции к последней; категория 0,
; номер 1..hi, цена[w] <= left; затем откат на позицию 0
sh_ch_s23:
	ld	hl, (sh_pp)
	ld	de, PL_STRAT
	add	hl, de
	ld	a, (hl)
	cp	2
	ld	a, 4
	jp	z, sh_ch_hi_st
	ld	a, 5
sh_ch_hi_st:
	ld	(sh_hi), a
	xor	a
	ld	(sh_c), a
sh_ch_s23_lp:
	ld	a, (sh_c)
	ld	c, a
	ld	b, 0
	ld	hl, sh_count
	ld	a, (hl)
	cp	c
	jp	z, sh_ch_ovr
	ld	hl, sh_cat
	add	hl, bc
	ld	a, (hl)
	or	a
	jp	nz, sh_ch_s23_next
	ld	hl, sh_num
	add	hl, bc
	ld	a, (hl)
	cp	1
	jp	c, sh_ch_s23_next
	ld	e, a
	ld	a, (sh_hi)
	cp	e
	jp	c, sh_ch_s23_next		; w > hi
	ld	a, e
	ld	(sh_selnum), a
	ld	d, 0
	ld	hl, sh_wprice
	add	hl, de
	add	hl, de
	ld	a, (hl)
	ld	e, a
	inc	hl
	ld	d, (hl)
	ld	hl, sh_left
	call	sh_le32
	jp	c, sh_ch_s23_next
	ld	a, (sh_c)
	ld	(sh_sel), a
sh_ch_s23_next:
	ld	hl, sh_c
	inc	(hl)
	jp	sh_ch_s23_lp

; стратегия 4: от последней позиции к первой; категория 2, цена_d[номер] <= left; затем откат
sh_ch_s4:
	ld	hl, sh_count
	ld	a, (hl)
	or	a
	jp	z, sh_ch_ovr
	dec	a
	ld	(sh_c), a
sh_ch_s4_lp:
	ld	a, (sh_c)
	ld	c, a
	ld	b, 0
	ld	hl, sh_cat
	add	hl, bc
	ld	a, (hl)
	cp	2
	jp	nz, sh_ch_s4_next
	ld	hl, sh_num
	add	hl, bc
	ld	a, (hl)
	ld	e, a
	ld	d, 0
	ld	hl, sh_dprice
	add	hl, de
	add	hl, de
	ld	a, (hl)
	ld	e, a
	inc	hl
	ld	d, (hl)
	ld	hl, sh_left
	call	sh_le32
	jp	c, sh_ch_s4_next
	ld	a, (sh_c)
	ld	(sh_sel), a
sh_ch_s4_next:
	ld	hl, sh_c
	ld	a, (hl)
	or	a
	jp	z, sh_ch_ovr
	dec	(hl)
	jp	sh_ch_s4_lp

; откат стратегий 2..4: если запас[1] + 100*qty[0] < 20 — sel = 0 (первая позиция меню)
sh_ch_ovr:
	ld	hl, (sh_pp)
	ld	de, PL_AMMO + 2
	add	hl, de
	ld	a, (hl)
	ld	e, a
	inc	hl
	ld	d, (hl)			; DE = запас[1]
	; qty[0] (пустое меню — 0)
	ld	c, 0
	ld	hl, sh_count
	ld	a, (hl)
	or	a
	jp	z, sh_ch_ovr_sum
	ld	hl, sh_qty
	ld	c, (hl)
sh_ch_ovr_sum:
	; HL = 100 * C
	ld	b, c
	ld	hl, 0
	ld	a, b
	or	a
	jp	z, sh_ch_ovr_add
sh_ch_ovr_100:
	ld	a, l
	add	a, 100
	ld	l, a
	ld	a, h
	adc	a, 0
	ld	h, a
	dec	b
	ld	a, b
	or	a
	jp	nz, sh_ch_ovr_100
sh_ch_ovr_add:
	add	hl, de
	ld	a, l
	sub	20
	ld	a, h
	sbc	a, 0
	jp	p, sh_ch_r
	ld	a, 0
	ld	(sh_sel), a
sh_ch_r:
	ret

; --- вспомогательные ---

; адрес записи: players + (A - 1) * PL_SIZE; в sh_pp
sh_find:
	ld	hl, players
	ld	(sh_pp), hl
	dec	a
	ret	z
	ld	c, a
sh_find_l:
	ld	de, PL_SIZE
	add	hl, de
	dec	c
	jp	nz, sh_find_l
	ld	(sh_pp), hl
	ret

; HL = &PL_SPENT записи (указатель на вычитаемое); sh_money = score - spent
sh_sub_score:
	ld	(sh_ptr), hl
	ld	de, PL_SCORE - PL_SPENT	; -4: &score
	add	hl, de
	ld	de, sh_money
	ld	b, 4
sh_ss_cp:
	ld	a, (hl)
	ld	(de), a
	inc	hl
	inc	de
	dec	b
	jp	nz, sh_ss_cp
	ld	hl, (sh_ptr)
	ld	de, sh_money
	jp	sh_sub4

; DE (32 бита) = DE - HL (32 бита), заём по цепочке
sh_sub4:
	or	a
	ld	b, 4
sh_sub4_lp:
	ld	a, (de)
	sbc	a, (hl)
	ld	(de), a
	inc	hl
	inc	de
	dec	b
	jp	nz, sh_sub4_lp
	ret

; HL (32 бита) -= 3000; флаг знака результата в флагах последнего sbc
sh_sub32_3000:
	ld	a, (hl)
	sub	$B8
	ld	(hl), a
	inc	hl
	ld	a, (hl)
	sbc	a, $0B
	ld	(hl), a
	inc	hl
	ld	a, (hl)
	sbc	a, 0
	ld	(hl), a
	inc	hl
	ld	a, (hl)
	sbc	a, 0
	ld	(hl), a
	ret

; sh_left = sh_money - sh_cart
sh_calc_left:
	ld	hl, sh_money
	ld	de, sh_left
	ld	b, 4
sh_cl_cp:
	ld	a, (hl)
	ld	(de), a
	inc	hl
	inc	de
	dec	b
	jp	nz, sh_cl_cp
	ld	hl, sh_cart
	ld	de, sh_left
	jp	sh_sub4

; DE = цена (слово 0..20000), HL = адрес 32-битного значения.
; Выход: C = 0, если цена <= значения (цена неотрицательная: значение < 0 — ложь,
; старшее слово значения > 0 — истина, иначе сравнение младших слов без знака). Портит AF, HL.
sh_le32:
	inc	hl
	inc	hl
	inc	hl
	ld	a, (hl)			; знак
	or	a
	jp	m, sh_le_no
	jp	nz, sh_le_yes
	dec	hl
	ld	a, (hl)			; байт 2
	or	a
	jp	nz, sh_le_yes
	dec	hl
	ld	b, (hl)			; байт 1 (C не трогаю — в нём sel у вызывающих)
	dec	hl
	ld	a, (hl)			; байт 0
	ld	l, a
	ld	h, b			; HL = младшее слово без знака
	ld	a, l
	sub	e
	ld	a, h
	sbc	a, d
	ret				; C = 1: цена больше
sh_le_yes:
	or	a
	ret
sh_le_no:
	scf
	ret

; HL = DE * C (слово, C = 0..9). DE сохраняет, портит AF, BC, HL
sh_mul16:
	ld	b, c
	ld	hl, 0
	ld	a, b
	or	a
	ret	z
sh_mul16_lp:
	add	hl, de
	dec	b
	ld	a, b
	or	a
	jp	nz, sh_mul16_lp
	ret

; sh_prod = DE * C (32 бита, C = 0..9). Портит всё
sh_muli32:
	ld	hl, sh_prod
	xor	a
	ld	(hl), a
	inc	hl
	ld	(hl), a
	inc	hl
	ld	(hl), a
	inc	hl
	ld	(hl), a
	ld	a, c
	or	a
	ret	z
sh_muli32_lp:
	ld	hl, sh_prod
	ld	a, (hl)
	add	a, e
	ld	(hl), a
	inc	hl
	ld	a, (hl)
	adc	a, d
	ld	(hl), a
	inc	hl
	ld	a, (hl)
	adc	a, 0
	ld	(hl), a
	inc	hl
	ld	a, (hl)
	adc	a, 0
	ld	(hl), a
	dec	c
	ld	a, c
	or	a
	jp	nz, sh_muli32_lp
	ret

; PL_SPENT записи += sh_prod (32 бита)
sh_add_spent:
	ld	hl, (sh_pp)
	ld	de, PL_SPENT
	add	hl, de
	ld	de, sh_prod
	or	a
	ld	b, 4
sh_as_lp:
	ld	a, (de)
	adc	a, (hl)
	ld	(hl), a
	inc	de
	inc	hl
	dec	b
	jp	nz, sh_as_lp
	ret

; запас позиции (sh_selcat, sh_selnum) += sh_prod: категория 0/1 — слово (обрезка i16), 2 — 4 байта
sh_add_have:
	ld	a, (sh_selcat)
	or	a
	jp	z, sh_ah_w
	cp	1
	jp	z, sh_ah_g
	ld	a, (sh_selnum)
	add	a, a
	add	a, a			; 4 * номер
	ld	e, a
	ld	d, 0
	ld	hl, (sh_pp)
	ld	bc, PL_SHIELD
	add	hl, bc
	add	hl, de
	ld	de, sh_prod
	or	a
	ld	b, 4
sh_ah_4:
	ld	a, (de)
	adc	a, (hl)
	ld	(hl), a
	inc	de
	inc	hl
	dec	b
	jp	nz, sh_ah_4
	ret
sh_ah_w:
	ld	a, (sh_selnum)
	add	a, a
	ld	e, a
	ld	d, 0
	ld	hl, (sh_pp)
	ld	bc, PL_AMMO
	add	hl, bc
	add	hl, de
	jp	sh_ah_2
sh_ah_g:
	ld	a, (sh_selnum)
	or	a
	jp	z, sh_ah_herb
	ld	hl, (sh_pp)
	ld	de, PL_VICK
	add	hl, de
	jp	sh_ah_2
sh_ah_herb:
	ld	hl, (sh_pp)
	ld	de, PL_HERB
	add	hl, de
sh_ah_2:
	ld	de, sh_prod
	ld	a, (de)
	add	a, (hl)
	ld	(hl), a
	inc	de
	inc	hl
	ld	a, (de)
	adc	a, (hl)
	ld	(hl), a
	ret

; Z = 1, если herb <= 0 (иначе Z = 0). Портит AF, DE, HL
sh_have16_herb:
	ld	hl, (sh_pp)
	ld	de, PL_HERB
	add	hl, de
	ld	e, (hl)
	inc	hl
	ld	h, (hl)
	ld	l, e			; (раньше L портился до чтения старшего байта)			; HL = herb
	ld	a, h
	or	a
	jp	m, sh_h16_le0
	ld	a, l
	or	h
	ret

; Z = 1, если vick <= 0
sh_have16_vick:
	ld	hl, (sh_pp)
	ld	de, PL_VICK
	add	hl, de
	ld	e, (hl)
	inc	hl
	ld	h, (hl)
	ld	l, e			; (раньше L портился до чтения старшего байта)
	ld	a, h
	or	a
	jp	m, sh_h16_le0
	ld	a, l
	or	h
	ret

sh_h16_le0:
	xor	a
	ret

; Z = 1, если shield <= 0 (32 бита)
sh_have32_shield:
	ld	hl, (sh_pp)
	ld	de, PL_SHIELD
	add	hl, de
	jp	sh_h32_chk

; Z = 1, если damp <= 0 (32 бита)
sh_have32_damp:
	ld	hl, (sh_pp)
	ld	de, PL_DAMP
	add	hl, de
sh_h32_chk:
	ld	a, (hl)
	inc	hl
	or	(hl)
	inc	hl
	or	(hl)
	inc	hl
	or	(hl)			; A = OR всех байтов, HL = на старшем
	ld	(sh_tmpa), a
	ld	a, (hl)			; старший байт — знак
	or	a
	jp	m, sh_h16_le0		; отрицательное — «<= 0»
	ld	a, (sh_tmpa)
	or	a			; (раньше флаг Z оставался от старшего байта)
	ret

sh_ret:
	ret
shop_end:

; оружие 0..17: цена (слово) и размер пачки (слово); пачка 0 — не продаётся
sh_wprice:	dw	0, 3000, 4000, 7000, 10000, 10000, 5000, 5000, 10000, 10000, 15000, 0, 4500, 4000, 6000, 8000, 10000, 4500
sh_wpack:	dw	0, 100, 10, 2, 1, 1000, 5, 10, 3, 3, 1, 0, 10, 10, 7, 3, 1, 10
; категория 1 (наведение: 0 — Herb, 1 — Vick) и категория 2 (защита: 0 — щит, 1 — демпфер)
sh_gprice:	dw	20000, 20000
sh_gpack:	dw	5, 5
sh_dprice:	dw	20000, 10000
sh_dpack:	dw	1000, 100

; --- ячейки Q7 ---
sh_pp:		dw	0			; адрес записи игрока
sh_money:	ds	4			; score - spent
sh_cart:	ds	4			; корзина
sh_left:	ds	4			; money - cart внутри выбора
sh_prod:	ds	4			; произведение цена/пачка * qty
sh_ptr:		dw	0			; временный указатель
sh_count:	db	0			; число позиций в меню
sh_cat:		ds	22			; категории позиций
sh_num:		ds	22			; номера позиций
sh_qty:		ds	22			; счётчики покупок позиции
sh_w:		db	0			; временный номер оружия / i
sh_c:		db	0			; индекс позиции c
sh_sel:		db	0			; выбор: позиция или 0xFF = «нет»
sh_selcat:	db	0
sh_selnum:	db	0
sh_hi:		db	0			; верхняя граница номера для стратегий 2/3
sh_price:	dw	0			; цена позиции sel
sh_step:	dw	0			; счётчик повторов покупки
sh_tmpa:	db	0
sh_tmpb:	db	0
