; Экран магазина по записи игрока и спискам магазина — drawShop() эталона web/tankwars.js.
; Готовая draw_shop (ui.asm) читает игрока в «упакованном» виде (80 байт) и меню по 4 байта на позицию; здесь —
; переходник: запись игрока + списки sh_cat/sh_num/sh_qty (shop.asm) -> упакованный вид -> draw_shop.
;   show_shop: вход A = место игрока 1..n, su_sel (байт: выбранная строка, 0xFF — ничего).
;              Меню: sh_count позиций, sh_cat[i], sh_num[i], sh_qty[i] (байты); корзина — sh_cart (4 байта).
; Только команды 8080. Свои метки и ячейки — с префиксом su_, ячейки после shopui_end.

show_shop:
	; 1. упаковать игрока место A в блок 0 массива hd_pack (hd_pack1 портит все регистры).
	ld	(hd_place), a
	xor	a
	ld	(hd_blk), a
	call	hd_pack1
	; 2. собрать меню в su_menu: по 4 байта на позицию (cat, num, qty младший, 0).
	xor	a
	ld	(su_i), a
	ld	de, su_menu
	ld	a, (sh_count)
	or	a
	jp	z, su_fill
su_mlp:
	ld	a, (su_i)
	ld	c, a
	ld	b, 0
	ld	hl, sh_cat
	add	hl, bc
	ld	a, (hl)
	ld	(de), a
	inc	de
	ld	hl, sh_num
	add	hl, bc
	ld	a, (hl)
	ld	(de), a
	inc	de
	ld	hl, sh_qty
	add	hl, bc
	ld	a, (hl)
	ld	(de), a
	inc	de
	xor	a
	ld	(de), a
	inc	de
	ld	a, (su_i)
	inc	a
	ld	(su_i), a
	ld	c, a
	ld	a, (sh_count)
	cp	c			; su_i < sh_count (счётчик шагает по 1, равенство будет ровно на конце)
	jp	nz, su_mlp
	; 3. заполнить ячейки draw_shop.
su_fill:
	ld	a, (sh_cart)
	ld	(ui_cart), a
	ld	a, (sh_cart + 1)
	ld	(ui_cart + 1), a
	ld	hl, (sh_cart + 2)	; старшее слово корзины (правка архитектора: корзина бывает больше 65535)
	ld	(ui_cart2), hl
	ld	a, (su_sel)
	ld	(ui_sel), a
	ld	a, (sh_count)
	ld	(ui_nmenu), a
	ld	hl, su_menu
	ld	(ui_menu), hl
	ld	hl, hd_pack
	ld	(ui_p), hl
	; 4. нарисовать.
	call	draw_shop
	ret
shopui_end:

su_sel:		db	0
su_menu:	ds	22 * 4		; меню для draw_shop: категория, номер, количество (слово)
su_i:		db	0			; счётчик позиций меню
