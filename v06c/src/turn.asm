; Ход целиком — turn() эталона web/tankwars.js (PROFILE_V06C): выстрел, последствия, гибель.
; Вход: tn_shooter (место 1..n), tn_xkill (0/1); состояние раунда: rs_rebound, rs_wind (round.asm),
;       as_crumble, as_fall (after.asm); n_players, players, RandSeed.
; Выход: изменённые записи и экран; fl_stop, fl_x, fl_y — чем кончился выстрел (для истории ИИ).
; Наведение: PL_GUIDED и PL_TARGET стрелка.

turn:
	call	fire
	; --- после выстрела: перерисовка, осыпание, падение ---
	ld	a, (rs_rebound)
	ld	(as_rebound), a
	call	after_shot
	; --- гибель, пока она случается ---
tn_pass:
	xor	a
	ld	(tn_died), a
	ld	a, 1
tn_pl:
	ld	(tn_i), a
	call	dt_ptr
	ld	(tn_p), hl
	ld	de, PL_ALIVE
	add	hl, de
	ld	a, (hl)
	or	a
	jp	z, tn_nx		; уже мёртв
	ld	hl, (tn_p)
	ld	de, PL_MEN + 1
	add	hl, de
	ld	a, (hl)
	or	a
	jp	m, tn_die		; men < 0
	jp	nz, tn_nx		; men >= 256
	dec	hl
	ld	a, (hl)
	or	a
	jp	nz, tn_nx		; men > 0
tn_die:
	ld	a, 1
	ld	(tn_died), a
	ld	hl, (tn_p)
	ld	de, PL_ALIVE
	add	hl, de
	ld	(hl), 0
	ld	de, 7
	call	random
	ld	a, l
	ld	(dt_variant), a
	ld	a, (tn_i)
	ld	(dt_victim), a
	ld	hl, (rs_wind)
	ld	(dt_wind), hl
	ld	a, (tn_xkill)
	ld	(dt_xkill), a
	ld	hl, sfx_death
	call	sfx_play
	call	death
	; стрелку +1500, если погиб не он
	ld	a, (tn_shooter)
	ld	b, a
	ld	a, (tn_i)
	cp	b
	jp	z, tn_ns
	ld	a, b
	call	dt_ptr
	ld	de, PL_SCORE
	add	hl, de
	ld	a, (hl)
	add	a, 1500 & 255
	ld	(hl), a
	inc	hl
	ld	a, (hl)
	adc	a, 1500 >> 8
	ld	(hl), a
	inc	hl
	ld	a, (hl)
	adc	a, 0
	ld	(hl), a
	inc	hl
	ld	a, (hl)
	adc	a, 0
	ld	(hl), a
tn_ns:
	ld	a, (rs_rebound)
	call	draw_frame
	ld	a, (as_crumble)
	call	rnd_lt_pct
	jp	nc, tn_nc
	call	crumble
tn_nc:
	call	af_fall_chk		; падение танков, если включено
tn_nx:
	ld	a, (n_players)
	ld	b, a
	ld	a, (tn_i)
	cp	b
	jp	z, tn_pe
	inc	a
	jp	tn_pl
tn_pe:
	ld	a, (tn_died)
	or	a
	jp	nz, tn_pass
	ret

; выстрел игрока tn_shooter
fire:
	xor	a
	ld	(fl_stop), a
	ld	a, (tn_shooter)
	call	dt_ptr
	ld	(tn_p), hl
	ld	de, PL_WEAPON
	add	hl, de
	ld	a, (hl)
	ld	(tn_w), a
	cp	5
	jp	nz, fr_ball
	ld	hl, sfx_laser
	call	sfx_play
	ld	a, (tn_shooter)	; лазер: запас не тратится, выстрел без снаряда
	jp	laser
fr_ball:
	; запас оружия − 1
	add	a, a
	add	a, PL_AMMO
	ld	e, a
	ld	d, 0
	ld	hl, (tn_p)
	add	hl, de
	call	tn_dec16
	; запас наведения
	ld	hl, (tn_p)
	ld	de, PL_GUIDED
	add	hl, de
	ld	a, (hl)
	ld	(tn_g), a
	and	1
	jp	z, fr_g2
	ld	hl, (tn_p)
	ld	de, PL_HERB
	add	hl, de
	call	tn_dec16
fr_g2:
	ld	a, (tn_g)
	and	2
	jp	z, fr_g3
	ld	hl, (tn_p)
	ld	de, PL_VICK
	add	hl, de
	call	tn_dec16
fr_g3:
	; с вероятностью 0.2 стрелок теряет единицу здоровья
	call	rnd_hi
	ld	de, -13107
	add	hl, de
	jp	c, fr_m			; hi >= 13107
	ld	hl, (tn_p)
	ld	de, PL_MEN
	add	hl, de
	call	tn_dec16
fr_m:
	ld	hl, (tn_p)
	ld	a, (hl)
	ld	(fl_tx), a
	inc	hl
	ld	a, (hl)
	ld	(fl_ty), a
	inc	hl
	ld	a, (hl)
	ld	(fl_angle), a
	inc	hl
	ld	a, (hl)
	ld	(fl_facing), a
	inc	hl
	ld	e, (hl)
	inc	hl
	ld	d, (hl)
	inc	hl
	ex	de, hl
	ld	(fl_power), hl
	ex	de, hl
	ld	e, (hl)
	inc	hl
	ld	d, (hl)
	ex	de, hl
	ld	(fl_men), hl
	ld	hl, (rs_wind)
	ld	(fl_wind), hl
	ld	a, (rs_rebound)
	ld	(fl_rebound), a
	ld	a, (tn_w)
	ld	(fl_weapon), a
	ld	a, (n_players)
	ld	(fl_players), a
	; наведение: цель — игрок PL_TARGET, если такой есть
	xor	a
	ld	(fl_guided), a
	ld	a, (tn_g)
	or	a
	jp	z, fr_ng
	ld	hl, (tn_p)
	ld	de, PL_TARGET
	add	hl, de
	ld	a, (hl)
	or	a
	jp	z, fr_ng
	ld	b, a
	ld	a, (n_players)
	cp	b
	jp	c, fr_ng
	ld	a, b
	call	dt_ptr
	ld	a, (hl)
	ld	(fl_gtx), a
	inc	hl
	ld	a, (hl)
	ld	(fl_gty), a
	ld	a, (tn_g)
	ld	(fl_guided), a
fr_ng:
	ld	a, 1
	ld	(fl_ball), a
	ld	hl, sfx_shot
	call	sfx_play
	call	flight
	ld	a, (fl_stop)
	cp	1
	jp	z, fr_hit
	cp	2
	ret	nz
fr_hit:
	ld	hl, sfx_boom
	call	sfx_play
	ld	hl, ex_x
	ld	de, fl_x
	ld	b, 8
	call	fx_copy			; fl_x и fl_y подряд -> ex_x, ex_y
	ld	a, (fl_hit)
	ld	(ex_hit), a
	ld	a, (tn_shooter)
	ld	(ex_shooter), a
	ld	a, (tn_w)
	ld	(ex_weapon), a
	jp	explode

; слово по адресу HL уменьшить на 1
tn_dec16:
	ld	a, (hl)
	sub	1
	ld	(hl), a
	ret	nc
	inc	hl
	dec	(hl)
	ret
; CF = 1, если Random·100 < A (строго): FX.rndLtRatio(rng, A, 100). Один шаг генератора.
rnd_lt_pct:
	ld	(tn_pct), a
	call	rnd_hi
	ex	de, hl
	ld	hl, 0
	ld	c, 0
	ld	b, 100
tn_m1:
	add	hl, de
	jp	nc, tn_m2
	inc	c
tn_m2:
	dec	b
	jp	nz, tn_m1
	ld	a, (tn_pct)
	ld	b, a
	ld	a, c
	cp	b			; CF = 1, если старший байт произведения < процента
	ret
turn_end:

tn_shooter:	db	0
tn_xkill:	db	0
tn_i:		db	0
tn_died:	db	0
tn_w:		db	0
tn_g:		db	0
tn_pct:		db	0
tn_p:		dw	0
