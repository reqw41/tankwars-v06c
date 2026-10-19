; Tank Wars / Вектор-06Ц — игра (v06c/build/game.bin). В файле game.rom она лежит сжатой: загрузчик loader.asm
; показывает заставку, по клавише распаковывает игру на 0100h и запускает. Собирается из тех же модулей, что и стенд tw.asm; отличие — главный цикл и прерывание кадра.
; Клавиши: стрелки влево/вправо — угол, вверх/вниз — мощность (держать — быстрее), ТАБ или W — оружие вперёд,
; Q — оружие назад, I — разворот, пробел или ВК — огонь, АР2 — прервать раунд ничьей, СТР — прервать и отдать
; победу случайному живому.
; Для проверок (v06c/test/game.mjs): g_fixed <> 0 — начальное число берётся из g_seed как есть; g_phase — что
; сейчас делает игра; kb_taken — сколько нажатий принято.
	device	noslot64k
	define	GAME
	org	0x0100

STACK		equ	0xA000
JOY_IDLE_CELL	equ	0x00F0		; значение покоя джойстика «П» от загрузчика (loader.asm)
RESULT		equ	g_palshadow	; pal_out пишет сюда копию 16 регистров палитры

PH_TITLE	equ	0
PH_INPUT	equ	1
PH_BUSY		equ	2
PH_RESULTS	equ	3
PH_READY	equ	4
PH_SHOP		equ	5
PH_SPLASH	equ	6

K_ABORT		equ	11
K_ABORT_RND	equ	12
K_TARGET	equ	13

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
	call	lcg_init		; таблицы генератора случайных чисел (9A00h..9DFFh, вне образа)
	; джойстик «П» (ВВ55 №2: порт B — вход, опрос обоих джойстиков). Значение покоя замерил загрузчик ДО заставки:
	; здесь огонь, которым её закрыли, может быть ещё нажат, и замер принял бы его за покой.
	ld	a, 0x83
	out	(4), a
	ld	a, 0x9F
	out	(5), a
	ld	a, (JOY_IDLE_CELL)
	ld	(joy_idle), a
	ei
	; клавиша, которой закрыли заставку (loader.asm), не считается: ждём, пока отпустят
gm_rel:
	halt
	call	kb_code
	or	a
	jp	nz, gm_rel
	; --- экран настройки матча ---
gm_setup:
	call	setup
	ld	a, PH_BUSY
	ld	(g_phase), a
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
	ld	(g_seed), hl		; следующий матч начнётся с другого числа

; --- матч: игроки заново ---
gm_match:
	ld	a, (g_n)
	ld	(n_players), a
	xor	a
	ld	(g_round), a
	ld	(gm_i), a
	ld	(g_anyhuman), a
gm_np:
	call	gm_newplayer
	ld	a, (n_players)
	ld	b, a
	ld	a, (gm_i)
	inc	a
	ld	(gm_i), a
	cp	b
	jp	nz, gm_np
	ld	a, (g_anyhuman)
	xor	1
	ld	(g_allai), a

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
	ld	a, (g_round)		; небо и земля раунда — парой цветов палитры, по кругу
	call	gm_scene
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
	ld	a, (g_cur)
	call	dt_ptr
	ld	de, PL_CTRL
	add	hl, de
	ld	a, (hl)
	cp	3
	jp	nz, gm_show
	; --- компьютер: шаги до кода 5 ---
	ld	a, (g_cur)
	call	show_panel
	ld	a, (rs_rebound)
	ld	(ap_rebound), a
	ld	hl, 5000		; не больше 5000 шагов, как в эталоне: без запасов компьютер стреляет впустую
	ld	(gm_steps), hl
gm_ai:
	ld	a, (g_cur)
	call	computer_step
	ld	(gm_code), a
	cp	5
	jp	z, gm_ai_fire
	ld	a, (g_cur)
	ld	(ac_place), a
	ld	a, (gm_code)
	call	apply_code
	ld	hl, (gm_steps)
	dec	hl
	ld	(gm_steps), hl
	ld	a, h
	or	l
	jp	nz, gm_ai
gm_ai_fire:
	ld	a, (g_cur)
	call	show_panel_nc
	call	kb_code			; прервать раунд можно и на ходу компьютера
	cp	K_ABORT
	jp	z, gm_abort
	cp	K_ABORT_RND
	jp	z, gm_abort_rnd
	ld	a, (g_step)		; пошаговый режим (проверки): ждать клавишу перед выстрелом
	or	a
	jp	z, gm_fire
	ld	a, PH_READY
	ld	(g_phase), a
	call	get_key
	ld	b, a
	ld	a, PH_BUSY
	ld	(g_phase), a
	ld	a, b
	cp	K_ABORT
	jp	z, gm_abort
	cp	K_ABORT_RND
	jp	z, gm_abort_rnd
	jp	gm_fire
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
	cp	K_TARGET
	jp	nz, gm_nt
	call	gm_target
	jp	gm_input
gm_nt:
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
	; панель не очищается: угол, мощность, разворот — только строка ANG/POW; оружие и наведение — вся поверх
	ld	a, (gm_code)
	cp	7
	ld	a, (g_cur)
	jp	nc, gm_upd
	call	show_panel_r1
	jp	gm_input
gm_upd:
	call	show_panel_nc
	jp	gm_input

; цель наведения игрока g_cur: следующий живой чужой после нынешней цели
gm_target:
	ld	a, (g_cur)
	call	dt_ptr
	ld	de, PL_TARGET
	add	hl, de
	ld	(gm_p), hl
	ld	a, (n_players)
	ld	(gm_i), a		; не больше n попыток
	ld	a, (hl)
gmt_l:
	ld	b, a
	ld	a, (n_players)
	cp	b
	jp	z, gmt_w
	jp	nc, gmt_n
gmt_w:
	ld	b, 0
gmt_n:
	ld	a, b
	inc	a
	ld	(gm_k), a
	ld	b, a
	ld	a, (g_cur)
	cp	b
	jp	z, gmt_x
	ld	a, b
	call	dt_ptr
	ld	de, PL_ALIVE
	add	hl, de
	ld	a, (hl)
	or	a
	jp	z, gmt_x
	ld	hl, (gm_p)
	ld	a, (gm_k)
	ld	(hl), a
	ret
gmt_x:
	ld	hl, gm_i
	dec	(hl)
	ret	z
	ld	a, (gm_k)
	jp	gmt_l

gm_fire:
	; наведение включено, а цель не выбрана, мертва или сам стрелок — взять следующую живую
	ld	a, (g_cur)
	call	dt_ptr
	ld	de, PL_GUIDED
	add	hl, de
	ld	a, (hl)
	or	a
	jp	z, gm_f1
	inc	hl
	ld	a, (hl)			; PL_TARGET
	or	a
	jp	z, gm_f0
	ld	b, a
	ld	a, (n_players)
	cp	b
	jp	c, gm_f0
	ld	a, (g_cur)
	cp	b
	jp	z, gm_f0
	ld	a, b
	call	dt_ptr
	ld	de, PL_ALIVE
	add	hl, de
	ld	a, (hl)
	or	a
	jp	nz, gm_f1
gm_f0:
	call	gm_target
gm_f1:
	ld	a, (g_cur)
	ld	(tn_shooter), a
	ld	a, (g_xkill)
	ld	(tn_xkill), a
	ld	a, (g_crumble)
	ld	(as_crumble), a
	ld	a, (g_fall)
	ld	(as_fall), a
	call	turn
	ld	a, (tn_w)
	cp	5
	ld	a, (g_cur)
	call	nz, record_shot		; история выстрелов (лазер не пишется)
	call	gm_pal
	call	round_winner
	jp	nc, gm_turn
	; --- конец раунда: A = победитель или 0 ---
gm_end:
	or	a
	call	nz, winner_bonus
	ld	hl, sfx_win
	call	sfx_play
	ld	a, (g_allai)
	call	results_sort
	ld	a, 1			; результаты и магазин — на чёрном
	call	gm_scene
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
	jp	nc, gm_setup		; матч окончен — снова настройка
	; магазин: по порядку мест; компьютеры закупаются сами
	ld	a, 1
gm_shop:
	ld	(gm_sh), a
	call	dt_ptr
	ld	de, PL_CTRL
	add	hl, de
	ld	a, (hl)
	cp	3
	ld	a, (gm_sh)
	jp	nz, gm_sh_h
	call	ai_shop
	jp	gm_sh_n
gm_sh_h:
	call	human_shop
gm_sh_n:
	ld	a, (n_players)
	ld	b, a
	ld	a, (gm_sh)
	cp	b
	jp	z, gm_round
	inc	a
	jp	gm_shop

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

; новый игрок на месте gm_i (0..n-1) — newPlayer() эталона, человек «ИГРОК n»
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
	; тип: 0 — человек, 1..7 — компьютер (имя из таблицы)
	ld	a, (gm_i)
	ld	e, a
	ld	d, 0
	ld	hl, g_types
	add	hl, de
	ld	a, (hl)
	ld	(gm_k), a
	ld	hl, (gm_p)
	ld	de, PL_CTRL
	add	hl, de
	or	a
	ld	(hl), 1
	jp	z, gnp_c
	ld	(hl), 3
gnp_c:
	call	gnp_colors
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
	ld	a, (gm_k)
	or	a
	jp	nz, gnp_ai
	ld	hl, s_player
	ld	b, 6
	call	gm_copy
	ld	a, (gm_i)
	add	a, '1'
	ld	(de), a
	ld	a, 1
	ld	(g_anyhuman), a
	jp	gnp_st
gnp_ai:
	ld	hl, s_ainames - 13
	ld	bc, 13
gnp_nm:
	add	hl, bc
	dec	a
	jp	nz, gnp_nm
	ld	b, 13
	call	gm_copy
gnp_st:
	ld	a, (gm_i)
	inc	a
	jp	pick_strategy

; цвета игрока gm_p на месте gm_i: gm_colors[место]
gnp_colors:
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
	jp	gm_copy

; цвета неба и земли по номеру A (1 — чёрное небо и зелёная земля, как в оригинале; дальше по кругу из gm_scenes).
; Меняются только два регистра палитры — на игру и сверку с эталоном это не влияет.
gm_scene:
	dec	a
gsc_m:
	cp	GM_NSCENES
	jp	c, gsc_1
	sub	GM_NSCENES
	jp	gsc_m
gsc_1:
	add	a, a
	ld	e, a
	ld	d, 0
	ld	hl, gm_scenes
	add	hl, de
	ld	a, (hl)
	ld	(pal_page), a
	inc	hl
	ld	a, (hl)
	ld	(pal_page + 1), a
	ret
GM_NSCENES	equ	6
gm_scenes:				; небо, земля — байты палитры BBGGGRRR
	db	0x00, 0x29		; чёрное небо, зелёная земля
	db	0x40, 0x29		; тёмно-синее небо, зелёная земля
	db	0x42, 0x14		; закат: багровое небо, бурая земля
	db	0x48, 0x65		; сумерки: сине-зелёное небо, песок
	db	0x40, 0xF6		; ночь: тёмно-синее небо, снег
	db	0x00, 0x5B		; чёрное небо, серый камень

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
	call	pal_expand
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
	call	pal_expand
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
	push	af
	ld	a, (g_phase)		; щелчок клавиши — в меню и магазине, не на ходу
	or	a
	jp	z, gk_clk
	cp	PH_SHOP
	jp	nz, gk_nc
gk_clk:
	ld	hl, sfx_click
	call	sfx_play
gk_nc:
	pop	af
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
	db	5, 0x01, 9		; H — Herb's Guide
	db	6, 0x40, 10		; V — Vick's Guide
	db	6, 0x10, K_TARGET	; T — следующая цель наведения
	db	1, 0x04, K_ABORT	; АР2
	db	1, 0x02, K_ABORT_RND	; СТР
	db	8, 0x02, 1		; джойстик «П»: влево — угол
	db	8, 0x01, 2		; вправо
	db	8, 0x08, 3		; вниз — сила
	db	8, 0x04, 4		; вверх
	db	8, 0x40, 5		; огонь 1 — выстрел, как пробел
	db	8, 0x80, 8		; огонь 2 — следующее оружие, как ТАБ
	db	0xFF

; ---------------------------------------------------------------------------------------------------
; Прерывание кадра: клавиатура, палитра (обе — в гашении кадра), звук, счётчик кадров.
; ---------------------------------------------------------------------------------------------------
isr:
	push	af
	push	bc
	push	de
	push	hl
	; Клавиатура — первой, сразу после прерывания: пока порт B ВВ55 стоит на вводе, машина видит на нём FFh —
	; белый бордюр и режим 512 точек. В гашении кадра (25 строк после прерывания) этого не видно, а позже ядро
	; MiSTer выводит из-за этого целый кадр в режиме 512.
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
	; девятая «строка» — джойстик «П»: биты, отличные от покоя, — нажатые (0 вправо, 1 влево, 2 вверх, 3 вниз,
	; 6 огонь 1, 7 огонь 2). Покой до замера — FFh, как у отпущенного джойстика: ранний кадр не даёт «нажато всё».
	in	a, (6)
	ld	hl, joy_idle
	xor	(hl)
	ld	(kb_rows + 8), a
	ld	a, 0x88			; назад: все порты на выход, прокрутка FFh, бордюр 0
	out	(0), a
	ld	a, 0xFF
	out	(3), a
	xor	a
	out	(2), a
	out	(1), a
	; палитра — готовые 16 регистров, тоже в гашении
	ld	a, (pal_dirty)
	or	a
	jp	z, isr_snd
	xor	a
	ld	(pal_dirty), a
	call	pal_write
isr_snd:
	call	snd_tick
	ld	hl, (g_frames)
	inc	hl
	ld	(g_frames), hl
	pop	hl
	pop	de
	pop	bc
	pop	af
	ei
	ret

	include	"strings_game.inc"
gm_colors:				; делители R, G, B: красный, жёлтый, голубой, пурпурный
	db	1, 0xFF, 0xFF
	db	1, 1, 0xFF
	db	0xFF, 1, 1
	db	1, 0xFF, 1

; настройки матча (значения по умолчанию эталона)
g_n:		db	2		; игроков
g_types:	db	0, 2, 3, 5	; игроки по местам: 0 — человек, 1..7 — компьютер (номер имени); второй по умолчанию — Навесник
g_step:		db	0		; 1 — компьютер ждёт клавишу перед выстрелом
g_rounds:	db	10
g_walls:	db	1		; стены: 0 не отражают, 1 случайно, 2 отражают
g_windmode:	db	2		; ветер: 0 None .. 4 Gale, 5 Random
g_crumble:	db	50		; осыпание, % (на экране настройки — шагом 10)
g_fall:		db	1		; танки падают
g_xkill:	db	1		; обломки ранят
g_seed:		db	0x39, 0x30, 0x00, 0x00
g_fixed:	db	0

g_phase:	db	0
g_allai:	db	0
g_anyhuman:	db	0
g_round:	db	0
g_cur:		db	0
g_frames:	dw	0
g_palshadow:	ds	16
pal_dirty:	db	0
kb_rows:	ds	9			; восемь строк матрицы и джойстик «П»
joy_idle:	db	0xFF
kb_taken:	db	0
gk_last:	db	0
gk_tmr:		db	0
gk_rep:		db	0
gm_code:	db	0
gm_i:		db	0
gm_sh:		db	0
gm_steps:	dw	0
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
	include	"laser.asm"
	include	"special.asm"
	include	"sound.asm"
	include	"sfx.asm"
	include	"aistep.asm"
	include	"hud.asm"
	include	"aiplan.asm"
	include	"ailob.asm"
	include	"aiwit.asm"
	include	"airifle.asm"
	include	"aitwang.asm"
	include	"aimain.asm"
	include	"shop.asm"
	include	"shopui.asm"
	include	"hshop.asm"
	include	"setup.asm"
	include	"barrel.asm"
	include	"text.asm"
	include	"crumble.asm"
	include	"pal.asm"
	include	"ui.asm"
game_end:
	savebin	"v06c/build/game.bin", 0x0100, game_end - 0x0100
