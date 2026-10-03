; Матч: перетасовка игроков, бонус победителю, сортировка результатов — shufflePlayers(), winnerBonus(), results()
; эталона web/tankwars.js. Записи игроков — таблица players (player.inc), число игроков — n_players.
;
; shuffle_players: вход — n_players, RandSeed в rand_seed.
; winner_bonus:    вход A = место победителя 1..n.
; results_sort:    вход A = 1, если все игроки — компьютеры (тогда тратятся случайные числа), иначе 0.
; Все вызовы random портят AF, BC, DE — счётчики, номера и указатели храним в ячейках памяти.

shuffle_players:
	; cnt = Random(20) + 10
	ld	de, 20
	call	random
	ld	a, l
	add	a, 10
	ld	(mt_cnt), a
mt_sh_loop:
	ld	a, (mt_cnt)
	or	a
	ret	z
	dec	a
	ld	(mt_cnt), a
	; a = Random(n)
	ld	a, (n_players)
	ld	e, a
	ld	d, 0
	call	random
	ld	a, l
	ld	(mt_i1), a
	; b = Random(n), пока b == a
mt_sh_b:
	ld	a, (n_players)
	ld	e, a
	ld	d, 0
	call	random
	ld	a, (mt_i1)
	ld	c, a
	ld	a, l
	cp	c
	jp	z, mt_sh_b
	ld	(mt_i2), a
	call	mt_swap
	jp	mt_sh_loop

winner_bonus:
	; A = место победителя w (1..n): запись w-1: победы+1, очки + n*1000
	ld	(mt_tmp), a
	dec	a
	call	mt_entry
	ld	de, PL_WINS
	add	hl, de			; HL = младший байт слова побед
	ld	a, (hl)
	inc	a
	ld	(hl), a
	jp	nz, wb_sc
	inc	hl
	inc	(hl)			; перенос в старший байт
wb_sc:
	; mt_val = n * 1000 (32 бита, сложением)
	ld	a, (n_players)
	ld	(mt_nc), a
	xor	a
	ld	(mt_val), a
	ld	(mt_val + 1), a
	ld	(mt_val + 2), a
	ld	(mt_val + 3), a
wb_mul:
	ld	a, (mt_nc)
	dec	a
	jp	m, wb_add
	ld	(mt_nc), a
	ld	hl, mt_val
	ld	a, (hl)
	add	a, 0xE8			; +1000
	ld	(hl), a
	inc	hl
	ld	a, (hl)
	adc	a, 0x03
	ld	(hl), a
	inc	hl
	ld	a, (hl)
	adc	a, 0
	ld	(hl), a
	inc	hl
	ld	a, (hl)
	adc	a, 0
	ld	(hl), a
	jp	wb_mul
wb_add:
	ld	a, (mt_tmp)
	dec	a
	call	mt_entry
	ld	de, PL_SCORE
	add	hl, de			; HL = очки записи w-1
	ld	de, mt_val
	ld	a, (de)
	add	a, (hl)
	ld	(hl), a
	inc	hl
	inc	de
	ld	a, (de)
	adc	a, (hl)
	ld	(hl), a
	inc	hl
	inc	de
	ld	a, (de)
	adc	a, (hl)
	ld	(hl), a
	inc	hl
	inc	de
	ld	a, (de)
	adc	a, (hl)
	ld	(hl), a
	ret

results_sort:
	; A = auto (0/1). Сортировка пузырьком: сначала по победам, затем по очкам при равных победах.
	ld	(mt_auto), a
	ld	a, (n_players)
	ld	(mt_k), a
rs_p1:
	ld	a, (mt_k)
	or	a
	jp	z, rs_p2_start
	dec	a
	ld	(mt_k), a
	xor	a
	ld	(mt_e), a
rs_p1_e:
	ld	a, (mt_e)
	inc	a
	ld	hl, n_players
	cp	(hl)
	jp	nc, rs_p1_next		; e + 1 >= n — проход окончен
	call	rs_ptrs			; HL = &wins[e], DE = &wins[e+1]
	call	mt_lt16			; перенос ест, если wins[e] < wins[e+1]
	jp	nc, rs_no1
	call	rs_swap
rs_no1:
	call	rs_next_e
	jp	rs_p1_e
rs_p1_next:
	jp	rs_p1

rs_p2_start:
	ld	a, (n_players)
	ld	(mt_k), a
rs_p2:
	ld	a, (mt_k)
	or	a
	jp	z, rs_men
	dec	a
	ld	(mt_k), a
	xor	a
	ld	(mt_e), a
rs_p2_e:
	ld	a, (mt_e)
	inc	a
	ld	hl, n_players
	cp	(hl)
	jp	nc, rs_p2_next
	call	rs_ptrs			; HL = &wins[e], DE = &wins[e+1]
	ld	a, (hl)			; равны ли победы (слово)
	ld	c, a
	ld	a, (de)
	cp	c
	jp	nz, rs_no2
	inc	hl
	inc	de
	ld	a, (hl)
	ld	c, a
	ld	a, (de)
	cp	c
	jp	nz, rs_no2
	call	rs_sc_ptrs		; HL = &score[e], DE = &score[e+1]
	call	mt_lt32			; перенос ест, если score[e] < score[e+1] (со знаком)
	jp	nc, rs_no2
	call	rs_swap
rs_no2:
	call	rs_next_e
	jp	rs_p2_e
rs_p2_next:
	jp	rs_p2

rs_men:					; у каждой записи здоровье = 100
	xor	a
	ld	(mt_e), a
rs_men_lp:
	ld	a, (mt_e)
	ld	hl, n_players
	cp	(hl)
	jp	nc, rs_auto
	call	mt_entry
	ld	de, PL_MEN
	add	hl, de
	ld	a, 100
	ld	(hl), a
	inc	hl
	xor	a
	ld	(hl), a
	call	rs_next_e
	jp	rs_men_lp

rs_auto:				; auto: 200 раз Random(319), Random(199), Random(319), Random(199), Random(16)
	ld	a, (mt_auto)
	or	a
	jp	z, rs_ret
	ld	a, 200
	ld	(mt_k), a
rs_auto_lp:
	ld	de, 319
	call	random
	ld	de, 199
	call	random
	ld	de, 319
	call	random
	ld	de, 199
	call	random
	ld	de, 16
	call	random
	ld	a, (mt_k)
	dec	a
	jp	z, rs_ret
	ld	(mt_k), a
	jp	rs_auto_lp
rs_ret:
	ret

; --- вспомогательные ---

rs_swap:				; поменять местами записи e и e+1
	ld	a, (mt_e)
	ld	(mt_i1), a
	inc	a
	ld	(mt_i2), a
	jp	mt_swap

rs_next_e:				; mt_e = mt_e + 1
	ld	a, (mt_e)
	inc	a
	ld	(mt_e), a
	ret

mt_entry:				; вход A = номер записи (0..3), выход HL = адрес записи
	ld	c, a
	ld	hl, players
	ld	de, PL_SIZE
mt_ep_lp:
	dec	c
	ret	m
	add	hl, de
	jp	mt_ep_lp

mt_swap:				; обмен записей mt_i1 и mt_i2 целиком (PL_SIZE байт)
	ld	a, (mt_i1)
	call	mt_entry
	ld	(mt_p1), hl		; mt_entry грузит DE — адрес первой записи храним в ячейке
	ld	a, (mt_i2)
	call	mt_entry
	ld	a, (mt_p1)
	ld	e, a
	ld	a, (mt_p1 + 1)
	ld	d, a
	ld	b, PL_SIZE
mt_sw_lp:
	ld	a, (de)
	ld	c, (hl)
	ld	(hl), a
	ld	a, c
	ld	(de), a
	inc	hl
	inc	de
	dec	b
	jp	nz, mt_sw_lp
	ret

rs_ptrs:				; HL = &wins[e], DE = &wins[e+1]
	ld	a, (mt_e)
	inc	a
	call	mt_entry
	ld	de, PL_WINS
	add	hl, de
	ex	de, hl			; DE = &wins[e+1]
	ld	a, (mt_e)
	push	de
	call	mt_entry
	ld	de, PL_WINS
	add	hl, de
	pop	de			; HL = &wins[e]
	ret

rs_sc_ptrs:				; HL = &score[e], DE = &score[e+1]
	ld	a, (mt_e)
	inc	a
	call	mt_entry
	ld	de, PL_SCORE
	add	hl, de
	ex	de, hl			; DE = &score[e+1]
	ld	a, (mt_e)
	push	de
	call	mt_entry
	ld	de, PL_SCORE
	add	hl, de
	pop	de			; HL = &score[e]
	ret

mt_lt16:				; HL -> слово 1, DE -> слово 2; перенос ест, если слово 1 < слова 2 (со знаком)
	ld	a, (de)
	ld	c, a
	ld	a, (hl)
	sub	c			; младшие байты: перенос = заём
	sbc	a, a			; A = FF при заёме, 0 без заёма
	ld	(mt_bw), a
	inc	hl
	inc	de
	ld	a, (de)
	xor	0x80
	ld	c, a			; старший байт числа 2 со знакомым сдвигом
	ld	a, (hl)
	xor	0x80
	ld	b, a
	ld	a, (mt_bw)
	rlca				; бит 7 (FF/00) = заём от младших байтов -> перенос
	ld	a, b
	sbc	a, c			; заём ест, если слово 1 < слова 2
	ret

mt_lt32:				; HL -> число 1, DE -> число 2 (4 байта, от младшего); перенос ест, если 1 < 2 (со знаком)
	ld	a, e
	add	a, 3
	ld	e, a
	ld	a, d
	adc	a, 0
	ld	d, a			; DE = старший байт числа 2
	ld	a, l
	add	a, 3
	ld	l, a
	ld	a, h
	adc	a, 0
	ld	h, a			; HL = старший байт числа 1
	ld	a, (de)
	xor	0x80			; s xor 0x80: беззнаковый порядок = знаковый порядок s
	ld	c, a
	ld	a, (hl)
	xor	0x80
	cp	c
	jp	c, lt32_yes
	jp	nz, lt32_no
	dec	hl
	dec	de
	ld	a, (hl)
	ld	c, a
	ld	a, (de)
	cp	c
	jp	c, lt32_no		; байт 2: s2 < s1
	jp	nz, lt32_yes		; s2 > s1
	dec	hl
	dec	de
	ld	a, (hl)
	ld	c, a
	ld	a, (de)
	cp	c
	jp	c, lt32_no
	jp	nz, lt32_yes
	dec	hl
	dec	de
	ld	a, (hl)
	ld	c, a
	ld	a, (de)
	cp	c
	jp	c, lt32_no
	jp	nz, lt32_yes
lt32_no:
	or	a				; сброс переноса (равенство или s1 > s2)
	ret
lt32_yes:
	scf
	ret

mt_cnt:		db 0
mt_k:		db 0
mt_e:		db 0
mt_i1:		db 0
mt_i2:		db 0
mt_auto:	db 0
mt_tmp:		db 0
mt_nc:		db 0
mt_p1:		ds 2
mt_bw:		db 0
mt_val:		ds 4
match_end:

n_players:	db	0
players:	ds	MAX_PLAYERS * PL_SIZE
