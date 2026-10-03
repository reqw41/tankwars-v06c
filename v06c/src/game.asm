; Tank Wars / Вектор-06Ц — игровой образ (рубеж М1: раунды людей с клавиатуры).
; Грузится с 0100h. Собирается из тех же модулей, что и стенд tw.asm; отличие — главный цикл и прерывание кадра.
; Клавиши: стрелки влево/вправо — угол, вверх/вниз — мощность (держать — быстрее), ТАБ или W — оружие вперёд,
; Q — оружие назад, I — разворот, пробел или ВК — огонь, АР2 — прервать раунд ничьей, СТР — прервать и отдать
; победу случайному живому.
; Для проверок (v06c/test/game.mjs): g_fixed <> 0 — начальное число берётся из g_seed как есть; g_phase — что
; сейчас делает игра; kb_taken — сколько нажатий принято.
	device	noslot64k
	define	GAME
	org	0x0100

STACK		equ	0xA000
RESULT		equ	g_palshadow	; pal_out пишет сюда копию 16 регистров палитры

PH_TITLE	equ	0
PH_INPUT	equ	1
PH_BUSY		equ	2
PH_RESULTS	equ	3

K_ABORT		equ	11
K_ABORT_RND	equ	12

entry:
	di
	ld	sp, STACK
	ld	a, 0xC3			; JP isr в векторе RST 7
	ld	(0x38), a
	ld	hl, isr
	ld	(0x39), hl
	xor	a
	ld	(g_phase), a
	ld	(gk_last), a
	call	clear_screen
	call	gm_pal_title
	ei
	; --- заставка ---
	ld	de, s_gtitle
	ld	hl, 0x0B0C		; H = столбец, L = строка
	ld	bc, 0x0902		; B = длина, C = цвет
	call	gm_text
	ld	de, s_anykey
	ld	hl, 0x0910
	ld	bc, 0x0D02
	call	gm_text
	call	get_key
	; --- начальное число ---
	ld	hl, g_seed
	ld	de, rand_seed
	ld	b, 4
	call	gm_copy
	ld	a, (g_fixed)
	or	a
	jp	nz, gm_match
	ld	hl, (g_frames)		; время до нажатия — в начальное число
	ld	(rand_seed), hl

; --- матч: игроки заново ---
gm_match:
	ld	a, (g_n)
	ld	(n_players), a
	xor	a
	ld	(g_round), a
	ld	(gm_i), a
gm_np:
	call	gm_newplayer
	ld	a, (n_players)
	ld	b, a
	ld	a, (gm_i)
	inc	a
	ld	(gm_i), a
	cp	b
	jp	nz, gm_np

; --- раунд ---
gm_round:
	ld	a, PH_BUSY
	ld	(g_phase), a
	ld	hl, g_round
	inc	(hl)
	call	shuffle_players
	ld	a, (g_walls)
	ld	(rs_walls), a
	ld	a, (g_windmode)
	ld	(rs_windmode), a
	call	round_start
	call	gm_pal
	ld	a, (rs_first)
	ld	(g_cur), a

; --- ход ---
gm_turn:
	ld	a, (g_cur)
	call	next_alive
	ld	(g_cur), a
	ld	(ac_place), a
	call	turn_begin
	call	auto_switch
gm_show:
	ld	a, (g_cur)
	call	show_panel
gm_input:
	ld	a, PH_INPUT
	ld	(g_phase), a
	call	get_key
	ld	(gm_code), a
	ld	a, PH_BUSY
	ld	(g_phase), a
	ld	a, (gm_code)
	cp	K_ABORT
	jp	z, gm_abort
	cp	K_ABORT_RND
	jp	z, gm_abort_rnd
	ld	a, (g_cur)
	ld	(ac_place), a
	call	needs_switch		; пустое оружие — можно только менять
	jp	nc, gm_code_ok
	ld	a, (gm_code)
	cp	7
	jp	z, gm_code_ok
	ld	a, 8
	ld	(gm_code), a
gm_code_ok:
	ld	a, (gm_code)
	cp	5
	jp	z, gm_fire
	; держат стрелку мощности давно — шаг по 10
	ld	b, 1
	cp	3
	jp	c, gm_ap
	cp	5
	jp	nc, gm_ap
	ld	a, (gk_rep)
	cp	20
	jp	c, gm_ap
	ld	b, 10
gm_ap:
	ld	a, b
	ld	(gm_i), a
gm_ap_lp:
	ld	a, (g_cur)
	ld	(ac_place), a
	ld	a, (gm_code)
	call	apply_code
	ld	hl, gm_i
	dec	(hl)
	jp	nz, gm_ap_lp
	jp	gm_show

gm_fire:
	ld	a, (g_cur)
	ld	(tn_shooter), a
	ld	a, (g_xkill)
	ld	(tn_xkill), a
	ld	a, (g_crumble)
	ld	(as_crumble), a
	ld	a, (g_fall)
	ld	(as_fall), a
	call	turn
	call	gm_pal
	call	round_winner
	jp	nc, gm_turn
	; --- конец раунда: A = победитель или 0 ---
gm_end:
	or	a
	call	nz, winner_bonus
	xor	a			; не все компьютеры
	call	results_sort
	call	clear_screen
	call	gm_pal
	ld	a, (g_round)
	ld	(hd_round), a
	ld	a, (g_rounds)
	ld	(hd_rounds), a
	call	show_results
	ld	a, PH_RESULTS
	ld	(g_phase), a
	call	get_key			; любая клавиша
	ld	a, (g_rounds)
	ld	b, a
	ld	a, (g_round)
	cp	b
	jp	c, gm_round
	jp	gm_match

; прерывание раунда: ничья
gm_abort:
	xor	a
	jp	gm_end
; прерывание раунда: победа случайному живому — abortRound(rng, ps, true)
gm_abort_rnd:
	xor	a
	ld	(gm_i), a		; живых
	ld	a, 1
gar_cnt:
	ld	(gm_k), a
	call	dt_ptr
	ld	de, PL_ALIVE
	add	hl, de
	ld	a, (hl)
	or	a
	jp	z, gar_c2
	ld	hl, gm_i
	inc	(hl)
gar_c2:
	ld	a, (n_players)
	ld	b, a
	ld	a, (gm_k)
	cp	b
	jp	z, gar_pick
	inc	a
	jp	gar_cnt
gar_pick:
	ld	a, (gm_i)
	or	a
	jp	z, gm_end		; живых нет — ничья
	ld	e, a
	ld	d, 0
	call	random
	ld	a, l
	inc	a
	ld	(gm_i), a		; какой по счёту живой
	xor	a
gar_find:
	inc	a
	ld	(gm_k), a
	call	dt_ptr
	ld	de, PL_ALIVE
	add	hl, de
	ld	a, (hl)
	or	a
	ld	a, (gm_k)
	jp	z, gar_find
	ld	hl, gm_i
	dec	(hl)
	jp	nz, gar_find
	jp	gm_end

; новый игрок на месте gm_i (0..n-1) — newPlayer() эталона, человек «PLAYER n»
gm_newplayer:
	ld	a, (gm_i)
	inc	a
	call	dt_ptr
	ld	(gm_p), hl
	ld	b, PL_SIZE
	xor	a
gnp_z:
	ld	(hl), a
	inc	hl
	dec	b
	jp	nz, gnp_z
	ld	hl, (gm_p)
	ld	de, PL_ANGLE
	add	hl, de
	ld	(hl), 90
	inc	hl
	ld	(hl), 1			; facing
	inc	hl
	ld	(hl), 200		; power
	inc	hl
	inc	hl
	ld	(hl), 100		; men
	inc	hl
	inc	hl
	ld	(hl), 1			; alive
	inc	hl
	ld	(hl), 1			; weapon
	ld	hl, (gm_p)
	ld	de, PL_CTRL
	add	hl, de
	ld	(hl), 1
	; цвета: gm_colors[место]
	ld	a, (gm_i)
	ld	e, a
	add	a, a
	add	a, e
	ld	e, a
	ld	d, 0
	ld	hl, gm_colors
	add	hl, de
	ex	de, hl
	push	de
	ld	hl, (gm_p)
	ld	de, PL_COLORS
	add	hl, de
	pop	de
	ex	de, hl
	ld	b, 3
	call	gm_copy
	; запасы: оружие 0 — 100, оружие 1 — раундов·3, оружие 11 — min(999, раундов·10)
	ld	hl, (gm_p)
	ld	de, PL_AMMO
	add	hl, de
	ld	(hl), 100
	inc	hl
	inc	hl
	ld	a, (g_rounds)
	ld	b, a
	add	a, a
	add	a, b
	ld	(hl), a
	ld	hl, (gm_p)
	ld	de, PL_AMMO + 22
	add	hl, de
	push	hl
	ld	a, (g_rounds)
	ld	l, a
	ld	h, 0
	add	hl, hl
	ld	d, h
	ld	e, l
	add	hl, hl
	add	hl, hl
	add	hl, de			; ·10 (раундов не больше 99 — до 999 не доходит)
	ex	de, hl
	pop	hl
	ld	(hl), e
	inc	hl
	ld	(hl), d
	; имя
	ld	hl, (gm_p)
	ld	de, PL_NAME
	add	hl, de
	ex	de, hl
	ld	hl, s_player
	ld	b, 7
	call	gm_copy
	ld	a, (gm_i)
	add	a, '1'
	ld	(de), a
	ret

; палитра по записям игроков: здоровье и цвета мест 1..4; пишет её прерывание
gm_pal:
	xor	a
gp_lp:
	ld	(gm_k), a
	inc	a
	call	dt_ptr
	ld	(gm_p), hl
	ld	de, PL_MEN
	add	hl, de
	ld	e, (hl)
	inc	hl
	ld	d, (hl)
	ld	a, (n_players)
	ld	b, a
	ld	a, (gm_k)
	cp	b
	jp	c, gp_m
	ld	de, 0			; места без игрока — чёрные
gp_m:
	ld	hl, pal_men
	call	gp_put
	ld	hl, (gm_p)
	ld	bc, PL_COLORS
	add	hl, bc
	ld	e, (hl)
	ld	d, 0
	push	hl
	ld	hl, pal_divr
	call	gp_put
	pop	hl
	inc	hl
	ld	e, (hl)
	push	hl
	ld	hl, pal_divg
	call	gp_put
	pop	hl
	inc	hl
	ld	e, (hl)
	ld	hl, pal_divb
	call	gp_put
	ld	a, (gm_k)
	inc	a
	cp	MAX_PLAYERS
	jp	nz, gp_lp
	xor	a
	ld	(pal_dirty), a
	call	pal_prepare
	ld	a, 1
	ld	(pal_dirty), a
	ret
gp_put:					; (HL + 2·gm_k) := DE
	ld	a, (gm_k)
	add	a, a
	add	a, l
	ld	l, a
	ld	a, h
	adc	a, 0
	ld	h, a
	ld	(hl), e
	inc	hl
	ld	(hl), d
	ret
; палитра заставки: игроков нет, только цвета страницы
gm_pal_title:
	ld	hl, pal_men
	ld	b, 8
	xor	a
gpt:
	ld	(hl), a
	inc	hl
	dec	b
	jp	nz, gpt
	call	pal_prepare
	ld	a, 1
	ld	(pal_dirty), a
	ret

; строка: DE = текст, H = столбец, L = строка, B = длина, C = цвет
gm_text:
	ld	a, h
	ld	(ch_col), a
	ld	a, l
	ld	(ch_row), a
	ld	a, c
	ld	(ch_c), a
	jp	draw_text

gm_copy:				; B байт из HL в DE
	ld	a, (hl)
	ld	(de), a
	inc	hl
	inc	de
	dec	b
	jp	nz, gm_copy
	ret

; ---------------------------------------------------------------------------------------------------
; Клавиатура. Прерывание читает строки матрицы в kb_rows; get_key ждёт нажатия и возвращает код действия.
; Стрелки повторяются, пока держат: первая пауза 15 кадров, дальше каждые 2 кадра; gk_rep — счётчик повторов.
; ---------------------------------------------------------------------------------------------------
get_key:
	halt
	call	kb_code
	ld	b, a
	ld	a, (gk_last)
	cp	b
	jp	nz, gk_new
	or	a
	jp	z, get_key
	cp	5
	jp	nc, get_key		; повторяются только стрелки (коды 1..4)
	ld	hl, gk_tmr
	dec	(hl)
	jp	nz, get_key
	ld	(hl), 2
	ld	hl, gk_rep
	ld	a, (hl)
	cp	255
	jp	z, gk_ret
	inc	(hl)
gk_ret:
	ld	a, b
	ret
gk_new:
	ld	a, b
	ld	(gk_last), a
	ld	a, 15
	ld	(gk_tmr), a
	xor	a
	ld	(gk_rep), a
	ld	a, b
	or	a
	jp	z, get_key
	ld	hl, kb_taken
	inc	(hl)
	ret

; код действия по нажатым клавишам: A = 0, если ничего. Таблица: строка матрицы, маска, код.
kb_code:
	ld	hl, kb_map
kc_lp:
	ld	a, (hl)
	cp	0xFF
	jp	z, kc_none
	ld	e, a
	ld	d, 0
	inc	hl
	ld	b, (hl)
	inc	hl
	ld	c, (hl)
	inc	hl
	push	hl
	ld	hl, kb_rows
	add	hl, de
	ld	a, (hl)
	pop	hl
	and	b
	jp	z, kc_lp
	ld	a, c
	ret
kc_none:
	xor	a
	ret
kb_map:					; строка матрицы, бит, код действия
	db	0, 0x10, 1		; влево
	db	0, 0x40, 2		; вправо
	db	0, 0x80, 3		; вниз
	db	0, 0x20, 4		; вверх
	db	7, 0x80, 5		; пробел
	db	0, 0x04, 5		; ВК
	db	5, 0x02, 6		; I
	db	6, 0x02, 7		; Q
	db	6, 0x80, 8		; W
	db	0, 0x01, 8		; ТАБ
	db	1, 0x04, K_ABORT	; АР2
	db	1, 0x02, K_ABORT_RND	; СТР
	db	0xFF

; ---------------------------------------------------------------------------------------------------
; Прерывание кадра: палитра (пока луч в бордюре), клавиатура, счётчик кадров.
; ---------------------------------------------------------------------------------------------------
isr:
	push	af
	push	bc
	push	de
	push	hl
	ld	a, (pal_dirty)
	or	a
	jp	z, isr_kb
	xor	a
	ld	(pal_dirty), a
	call	pal_out
isr_kb:
	ld	a, 0x8A			; порт A — выход (выбор строки), порт B — вход
	out	(0), a
	ld	hl, kb_rows
	ld	c, 0xFE
isr_row:
	ld	a, c
	out	(3), a
	in	a, (2)
	cpl
	ld	(hl), a
	inc	hl
	ld	a, c
	rlca
	ld	c, a
	jp	c, isr_row		; восемь строк: ноль выходит из бита 7 последним
	ld	a, 0x88			; назад: все порты на выход, прокрутка FFh, бордюр 0
	out	(0), a
	ld	a, 0xFF
	out	(3), a
	xor	a
	out	(2), a
	out	(1), a
	ld	hl, (g_frames)
	inc	hl
	ld	(g_frames), hl
	pop	hl
	pop	de
	pop	bc
	pop	af
	ei
	ret

s_gtitle:	db	"TANK WARS"
s_anykey:	db	"PRESS ANY KEY"
s_player:	db	"PLAYER "
gm_colors:				; делители R, G, B: красный, жёлтый, голубой, пурпурный
	db	1, 0xFF, 0xFF
	db	1, 1, 0xFF
	db	0xFF, 1, 1
	db	1, 0xFF, 1

; настройки матча (значения по умолчанию эталона)
g_n:		db	2		; игроков
g_rounds:	db	10
g_walls:	db	1		; стены: 0 обычные, 1 случайно, 2 отражают
g_windmode:	db	2		; ветер: 0 None .. 4 Gale, 5 Random
g_crumble:	db	50		; осыпание, %
g_fall:		db	1		; танки падают
g_xkill:	db	1		; обломки ранят
g_seed:		db	0x39, 0x30, 0x00, 0x00
g_fixed:	db	0

g_phase:	db	0
g_round:	db	0
g_cur:		db	0
g_frames:	dw	0
g_palshadow:	ds	16
pal_dirty:	db	0
kb_rows:	ds	8
kb_taken:	db	0
gk_last:	db	0
gk_tmr:		db	0
gk_rep:		db	0
gm_code:	db	0
gm_i:		db	0
gm_k:		db	0
gm_p:		dw	0

	include	"player.inc"
	include	"random.asm"
	include	"pixel.asm"
	include	"line.asm"
	include	"frame.asm"
	include	"sprite.asm"
	include	"fill.asm"
	include	"disc.asm"
	include	"terrain.asm"
	include	"place.asm"
	include	"match.asm"
	include	"round.asm"
	include	"fx.asm"
	include	"flight.asm"
	include	"explode.asm"
	include	"after.asm"
	include	"action.asm"
	include	"death.asm"
	include	"turn.asm"
	include	"aistep.asm"
	include	"hud.asm"
	include	"aiplan.asm"
	include	"ailob.asm"
	include	"aiwit.asm"
	include	"airifle.asm"
	include	"barrel.asm"
	include	"text.asm"
	include	"crumble.asm"
	include	"pal.asm"
	include	"ui.asm"
game_end:
	savebin	"v06c/build/game.rom", 0x0100, game_end - 0x0100
