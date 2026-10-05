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
	; поля записи -> блок
	ld	a, PL_NAME
	ld	c, 0
	ld	b, 14
	call	hd_cp
	ld	a, PL_FACING
	ld	c, 17
	ld	b, 1
	call	hd_cp
	ld	a, PL_ANGLE
	ld	c, 18
	ld	b, 1
	call	hd_cp		; старший байт угла уже 0
	ld	a, PL_POWER
	ld	c, 20
	ld	b, 2
	call	hd_cp
	ld	a, PL_MEN
	ld	c, 22
	ld	b, 2
	call	hd_cp
	ld	a, PL_WEAPON
	ld	c, 24
	ld	b, 1
	call	hd_cp
	ld	a, PL_GUIDED
	ld	c, 25
	ld	b, 1
	call	hd_cp
	ld	a, PL_HERB
	ld	c, 26
	ld	b, 2
	call	hd_cp
	ld	a, PL_VICK
	ld	c, 28
	ld	b, 2
	call	hd_cp
	ld	a, PL_WINS
	ld	c, 30
	ld	b, 2
	call	hd_cp
	ld	a, PL_SCORE
	ld	c, 32
	ld	b, 4
	call	hd_cp
	ld	a, PL_SPENT
	ld	c, 36
	ld	b, 4
	call	hd_cp
	ld	a, PL_SHIELD
	ld	c, 40
	ld	b, 2
	call	hd_cp		; младшие 2 байта
	ld	a, PL_DAMP
	ld	c, 42
	ld	b, 2
	call	hd_cp		; младшие 2 байта
	ld	a, PL_AMMO
	ld	c, 44
	ld	b, 36
	call	hd_cp
	ret

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
