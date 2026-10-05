; Панель хода и экран результатов по записям игроков (player.inc) — drawPanel(), drawResults() эталона.
; Готовые draw_panel и draw_results (ui.asm) читают игрока в «упакованном» виде по 80 байт; здесь — переходник:
; запись игрока -> упакованный вид -> вызов готовой подпрограммы.
;   show_panel:   вход A = место игрока 1..n; ветер берётся из rs_wind. show_panel_nc, show_panel_r1 — обновление.
;   show_results: вход hd_round, hd_rounds (байты); рисует всех n_players игроков по порядку мест.
; Только команды 8080 (без ld (nn),r для r<>a). Свои ячейки — после hud_end, имена с hd_.

show_panel:
	call	hd_prep
	jp	draw_panel
; то же поверх уже нарисованной панели этого игрока — без очистки и мигания
show_panel_nc:
	call	hd_prep
	jp	draw_panel_nc
; только строка ANG/POW/MEN (угол, мощность, разворот)
show_panel_r1:
	call	hd_prep
	jp	dp_row1
hd_prep:
	ld	(hd_place), a
	xor	a
	ld	(hd_blk), a		; панель рисует первый блок hd_pack
	call	hd_pack1
	ld	hl, (rs_wind)
	ld	(ui_wind), hl
	ld	hl, hd_pack
	ld	(ui_p), hl
	ret

show_results:
	ld	a, 1
	ld	(hd_place), a
hd_r_lp:
	ld	a, (hd_place)
	dec	a
	ld	(hd_blk), a		; игрок i -> блок i-1
	ld	a, (hd_place)
	call	hd_pack1
	ld	a, (n_players)
	ld	c, a
	ld	a, (hd_place)
	cp	c
	jp	z, hd_r_go
	inc	a
	ld	(hd_place), a
	jp	hd_r_lp
hd_r_go:
	ld	a, (hd_round)
	ld	(ui_round), a
	ld	a, (hd_rounds)
	ld	(ui_rounds), a
	ld	a, (n_players)
	ld	(ui_n), a
	ld	hl, hd_pack
	ld	(ui_ps), hl
	call	draw_results
	ret

; Упаковать запись игрока hd_place (1..n) в блок с номером hd_blk (0..3) массива hd_pack.
; Имя 14 байт + нули, место, направление, угол (младший PL_ANGLE, старший 0), мощность, здоровье,
; оружие, наведение, herb, vick, победы, очки, потрачено, младшие 2 байта щита и демпфера, 18 слов запаса.
; Портит все регистры.
hd_pack1:
	; hd_src = players + (место-1)*PL_SIZE
	ld	a, (hd_place)
	ld	hl, players
	ld	c, a
	dec	c			; C = место-1 (0..3)
hd_p_rec:
	ld	a, c
	or	a
	jp	z, hd_p_rec_ok
	ld	de, PL_SIZE
	add	hl, de
	dec	c
	jp	hd_p_rec
hd_p_rec_ok:
	ld	(hd_src), hl
	; hd_dst = hd_pack + hd_blk*80
	ld	a, (hd_blk)
	ld	e, a
	rlca
	rlca
	rlca
	rlca
	rlca
	rlca			; a = (место-1)*64 (место<=4, переноса нет)
	ld	c, a
	ld	a, e
	rlca
	rlca
	rlca
	rlca			; a = (место-1)*16
	add	a, c		; hd_blk*80, <=240
	ld	c, a
	xor	a
	ld	b, a
	ld	hl, hd_pack
	add	hl, bc
	ld	(hd_dst), hl
	; блок обнулить целиком, потом заполнить поля
	ld	b, 80
	call	fx_zero
	ld	hl, (hd_dst)
	ld	de, 16
	add	hl, de
	ld	a, (hd_place)
	ld	(hl), a		; место игрока
	; поля записи -> блок, по таблице
	ld	hl, hd_tab
hd_p_f:
	ld	a, (hl)
	inc	hl
	ld	c, (hl)
	inc	hl
	ld	b, (hl)
	inc	hl
	call	hd_cp
	ld	a, (hl)
	inc	a
	jp	nz, hd_p_f
	ret
; смещение в записи, смещение в блоке, длина (старший байт угла остаётся 0; щит и демпфер — младшие 2 байта)
hd_tab:
	db	PL_NAME, 0, 14
	db	PL_FACING, 17, 1
	db	PL_ANGLE, 18, 1
	db	PL_POWER, 20, 2
	db	PL_MEN, 22, 2
	db	PL_WEAPON, 24, 1
	db	PL_GUIDED, 25, 1
	db	PL_HERB, 26, 2
	db	PL_VICK, 28, 2
	db	PL_WINS, 30, 2
	db	PL_SCORE, 32, 4
	db	PL_SPENT, 36, 4
	db	PL_SHIELD, 40, 2
	db	PL_DAMP, 42, 2
	db	PL_AMMO, 44, 36
	db	0xFF

; Копия B байт: запись+(A) -> блок+(C); адреса записи/блока в hd_src/hd_dst. HL, DE сохраняет.
hd_cp:
	push	hl
	push	de
	push	bc			; B = длина, C = смещение в блоке
	ld	c, a
	xor	a
	ld	b, a
	ld	hl, (hd_src)
	add	hl, bc
	ex	de, hl			; DE = запись + A
	pop	bc
	ld	a, b
	ld	(hd_flen), a
	ld	b, 0			; C = смещение в блоке
	ld	hl, (hd_dst)
	add	hl, bc			; HL = блок + C
	ld	a, (hd_flen)
	ld	b, a
	call	fx_copy
	pop	de
	pop	hl
	ret

hud_end:

hd_round:	db	0
hd_rounds:	db	0
hd_pack:	ds	4 * 80		; упакованные игроки
hd_src:		dw	0		; адрес записи игрока
hd_dst:		dw	0		; адрес текущего блока
hd_place:	db	0		; место игрока / счётчик цикла
hd_blk:		db	0		; номер блока в hd_pack
hd_flen:	db	0		; длина копирования в hd_cp
