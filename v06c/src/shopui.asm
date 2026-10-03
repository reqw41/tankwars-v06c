; Экран магазина по записи игрока и спискам магазина — drawShop() эталона web/tankwars.js.
; Готовая draw_shop (ui.asm) читает игрока в «упакованном» виде (80 байт) и меню по 4 байта на позицию; здесь —
; переходник: запись игрока + списки sh_cat/sh_num/sh_qty (shop.asm) -> упакованный вид -> draw_shop.
;   show_shop: вход A = место игрока 1..n, su_sel (байт: выбранная строка, 0xFF — ничего).
;              Меню: sh_count позиций, sh_cat[i], sh_num[i], sh_qty[i] (байты); корзина — sh_cart (берутся младшие 2 байта).
; ЗАГЛУШКА: задача Q11 (docs/tasks/Q11-shopui.md).

show_shop:
	ret
shopui_end:

su_sel:		db	0
su_menu:	ds	22 * 4		; меню для draw_shop: категория, номер, количество (слово)
