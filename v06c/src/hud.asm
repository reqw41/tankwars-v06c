; Панель хода и экран результатов по записям игроков (player.inc) — drawPanel(), drawResults() эталона.
; Готовые draw_panel и draw_results (ui.asm) читают игрока в «упакованном» виде по 80 байт; здесь — переходник:
; запись игрока -> упакованный вид -> вызов готовой подпрограммы.
;   show_panel:   вход A = место игрока 1..n; ветер берётся из rs_wind.
;   show_results: вход hd_round, hd_rounds (байты); рисует всех n_players игроков по порядку мест.
; ЗАГЛУШКА: задача Q9 (docs/tasks/Q9-hud.md).

show_panel:
	ret

show_results:
	ret
hud_end:

hd_round:	db	0
hd_rounds:	db	0
hd_pack:	ds	4 * 80		; упакованные игроки
