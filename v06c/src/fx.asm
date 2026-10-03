; Арифметика Q16.16 (знаковая, 32 бита, значение = raw / 65536) — web/fixmath.js на 8080.
; Операнды и результат — в ячейках: fx_a (первый операнд и результат), fx_b (второй операнд). Младший байт первым.
; Все подпрограммы портят AF, BC, DE, HL.
;   fx_mul    fx_a = fx_a · fx_b               округление до ближайшего, середина от нуля
;   fx_div    fx_a = fx_a / fx_b               то же; деление на 0 даёт 0
;   fx_idiv   fx_a = fx_a / DE (целое 1..65535) то же
;   fx_sqrt   fx_a = sqrt(fx_a), fx_a >= 0     округление до ближайшего
;   fx_hypot  fx_a = sqrt(fx_a² + fx_b²)
;   fx_trunc  HL = целая часть fx_a, усечение к нулю
;   fx_neg_a  fx_a = -fx_a
;   fx_sincos HL = градусы -> fx_cos, fx_sin (Q16.16)
;   fx_atan   A = арктангенс fx_a в целых градусах (-89..89), усечение к нулю
; Умножение и деление — общие 64-битные циклы (просто и коротко, но медленно); для шага полёта нужны будут быстрые
; частные случаи (деление на 10, аккумуляторы тяжести и ветра).

; --- работа с многобайтными числами в памяти ---
; сдвиг влево через перенос: HL — младший байт, B — число байт; CF входит в бит 0, старший бит выходит в CF
fx_shl:
	ld	a, (hl)
	rla
	ld	(hl), a
	inc	hl
	dec	b
	jp	nz, fx_shl
	ret
; (HL) += (DE), B байт; на выходе CF — перенос
fx_addm:
	or	a
fx_addm_l:
	ld	a, (de)
	adc	a, (hl)
	ld	(hl), a
	inc	hl
	inc	de
	dec	b
	jp	nz, fx_addm_l
	ret
; (HL) -= (DE), B байт; на выходе CF — заём
fx_subm:
	or	a
fx_subm_l:
	ld	a, (de)
	ld	c, a
	ld	a, (hl)
	sbc	a, c
	ld	(hl), a
	inc	hl
	inc	de
	dec	b
	jp	nz, fx_subm_l
	ret
; (HL) = -(HL), B байт
fx_negm:
	scf
fx_negm_l:
	ld	a, (hl)
	cpl
	adc	a, 0
	ld	(hl), a
	inc	hl
	dec	b
	jp	nz, fx_negm_l
	ret
; обнулить B байт с HL
fx_zero:
	xor	a
fx_zero_l:
	ld	(hl), a
	inc	hl
	dec	b
	jp	nz, fx_zero_l
	ret
; копия B байт: (DE) -> (HL)
fx_copy:
	ld	a, (de)
	ld	(hl), a
	inc	hl
	inc	de
	dec	b
	jp	nz, fx_copy
	ret

fx_neg_a:
	ld	hl, fx_a
	ld	b, 4
	jp	fx_negm

; модули операндов; в fx_sg — 1, если знаки разные
fx_abs_ab:
	xor	a
	ld	(fx_sg), a
	ld	a, (fx_a + 3)
	or	a
	jp	p, fx_abs_b
	call	fx_neg_a
	ld	a, 1
	ld	(fx_sg), a
fx_abs_b:
	ld	a, (fx_b + 3)
	or	a
	ret	p
	ld	hl, fx_b
	ld	b, 4
	call	fx_negm
	ld	a, (fx_sg)
	xor	1
	ld	(fx_sg), a
	ret
; модуль одного fx_a; fx_sg = 1, если был отрицательный
fx_abs_a:
	xor	a
	ld	(fx_sg), a
	ld	a, (fx_a + 3)
	or	a
	ret	p
	ld	a, 1
	ld	(fx_sg), a
	jp	fx_neg_a
; вернуть знак результату
fx_sign:
	ld	a, (fx_sg)
	or	a
	ret	z
	jp	fx_neg_a

; fx_w (64 бита) = fx_a · fx_b, беззнаковые 32 бита. Портит fx_b.
fx_mulu:
	ld	hl, fx_w
	ld	b, 8
	call	fx_zero
	ld	c, 32
fx_mulu_l:
	push	bc
	or	a
	ld	hl, fx_w
	ld	b, 8
	call	fx_shl
	or	a
	ld	hl, fx_b
	ld	b, 4
	call	fx_shl			; старший бит множителя -> CF
	jp	nc, fx_mulu_n
	ld	hl, fx_w
	ld	de, fx_a
	ld	b, 4
	call	fx_addm
	jp	nc, fx_mulu_n
	ld	hl, fx_w + 4		; перенос в старшую половину
fx_mulu_c:
	inc	(hl)
	jp	nz, fx_mulu_n
	inc	hl
	jp	fx_mulu_c
fx_mulu_n:
	pop	bc
	dec	c
	jp	nz, fx_mulu_l
	ret

fx_mul:
	call	fx_abs_ab
	call	fx_mulu
	ld	hl, fx_w + 1		; + 0x8000: округление
	ld	a, (hl)
	add	a, 0x80
	ld	(hl), a
	jp	nc, fx_mul_r
fx_mul_c:
	inc	hl
	inc	(hl)
	jp	z, fx_mul_c
fx_mul_r:
	ld	hl, fx_a
	ld	de, fx_w + 2
	ld	b, 4
	call	fx_copy
	jp	fx_sign

; fx_w (64 бита) / fx_d (32 бита, старший бит 0) -> частное в fx_w, остаток в fx_rm
fx_divu:
	ld	hl, fx_rm
	ld	b, 5
	call	fx_zero
	xor	a
	ld	(fx_d + 4), a
	ld	c, 64
fx_divu_l:
	push	bc
	or	a
	ld	hl, fx_w
	ld	b, 8
	call	fx_shl
	ld	hl, fx_rm
	ld	b, 5
	call	fx_shl
	ld	hl, fx_rm
	ld	de, fx_d
	ld	b, 5
	call	fx_subm
	jp	nc, fx_divu_1
	ld	hl, fx_rm		; не поместилось — вернуть
	ld	de, fx_d
	ld	b, 5
	call	fx_addm
	jp	fx_divu_n
fx_divu_1:
	ld	hl, fx_w
	inc	(hl)
fx_divu_n:
	pop	bc
	dec	c
	jp	nz, fx_divu_l
	ret

fx_div:
	ld	hl, fx_b
	ld	a, (hl)
	inc	hl
	or	(hl)
	inc	hl
	or	(hl)
	inc	hl
	or	(hl)
	jp	nz, fx_div_go
	ld	hl, fx_a		; деление на 0 -> 0
	ld	b, 4
	jp	fx_zero
fx_div_go:
	call	fx_abs_ab
	ld	hl, fx_d
	ld	de, fx_b
	ld	b, 4
	call	fx_copy
	ld	hl, fx_w
	ld	b, 8
	call	fx_zero
	ld	hl, fx_w + 2
	ld	de, fx_a
	ld	b, 4
	call	fx_copy			; делимое = |a| << 16
fx_div_rnd:
	; + половина делителя (округление до ближайшего)
	ld	hl, fx_t
	ld	de, fx_d
	ld	b, 4
	call	fx_copy
	ld	hl, fx_t + 3		; fx_t = делитель >> 1
	ld	b, 4
	or	a
fx_div_h:
	ld	a, (hl)
	rra
	ld	(hl), a
	dec	hl
	dec	b
	jp	nz, fx_div_h
	ld	hl, fx_w
	ld	de, fx_t
	ld	b, 4
	call	fx_addm
	jp	nc, fx_div_q
	ld	hl, fx_w + 4
fx_div_c:
	inc	(hl)
	jp	nz, fx_div_q
	inc	hl
	jp	fx_div_c
fx_div_q:
	call	fx_divu
	ld	hl, fx_a
	ld	de, fx_w
	ld	b, 4
	call	fx_copy
	jp	fx_sign

; fx_a = fx_a / DE
fx_idiv:
	ex	de, hl
	ld	(fx_d), hl
	ld	hl, 0
	ld	(fx_d + 2), hl
	call	fx_abs_a
	ld	hl, fx_w
	ld	b, 8
	call	fx_zero
	ld	hl, fx_w
	ld	de, fx_a
	ld	b, 4
	call	fx_copy
	jp	fx_div_rnd

; HL = trunc(fx_a) к нулю. fx_a не меняется.
fx_trunc:
	ld	hl, (fx_a + 2)
	ld	a, h
	or	a
	ret	p
	ld	a, (fx_a)		; отрицательное: дробная часть не ноль -> +1
	ld	b, a
	ld	a, (fx_a + 1)
	or	b
	ret	z
	inc	hl
	ret

; корень из fx_n (64 бита) -> fx_rt (32 бита), округление до ближайшего
fx_isqrt:
	ld	hl, fx_rt
	ld	b, 5
	call	fx_zero
	ld	hl, fx_rm
	ld	b, 5
	call	fx_zero
	ld	c, 32
fx_isq_l:
	push	bc
	or	a
	ld	hl, fx_n
	ld	b, 8
	call	fx_shl
	ld	hl, fx_rm
	ld	b, 5
	call	fx_shl
	or	a
	ld	hl, fx_n
	ld	b, 8
	call	fx_shl
	ld	hl, fx_rm
	ld	b, 5
	call	fx_shl			; rem = rem·4 + два старших бита n
	or	a
	ld	hl, fx_rt
	ld	b, 5
	call	fx_shl			; root <<= 1
	ld	hl, fx_tr
	ld	de, fx_rt
	ld	b, 5
	call	fx_copy
	scf
	ld	hl, fx_tr
	ld	b, 5
	call	fx_shl			; trial = root·2 + 1
	ld	hl, fx_rm
	ld	de, fx_tr
	ld	b, 5
	call	fx_subm
	jp	nc, fx_isq_1
	ld	hl, fx_rm
	ld	de, fx_tr
	ld	b, 5
	call	fx_addm
	jp	fx_isq_n
fx_isq_1:
	ld	hl, fx_rt
	inc	(hl)
fx_isq_n:
	pop	bc
	dec	c
	jp	nz, fx_isq_l
	; округление: если остаток > корня, корень + 1
	ld	hl, fx_tr
	ld	de, fx_rt
	ld	b, 5
	call	fx_copy
	ld	hl, fx_tr
	ld	de, fx_rm
	ld	b, 5
	call	fx_subm			; root - rem: заём, если rem > root
	ret	nc
	ld	hl, fx_rt
fx_isq_i:
	inc	(hl)
	ret	nz
	inc	hl
	jp	fx_isq_i

fx_sqrt:
	ld	hl, fx_n
	ld	b, 8
	call	fx_zero
	ld	hl, fx_n + 2
	ld	de, fx_a
	ld	b, 4
	call	fx_copy
	call	fx_isqrt
fx_sqrt_r:
	ld	hl, fx_a
	ld	de, fx_rt
	ld	b, 4
	jp	fx_copy

fx_hypot:
	ld	hl, fx_t		; сохранить b
	ld	de, fx_b
	ld	b, 4
	call	fx_copy
	ld	hl, fx_b
	ld	de, fx_a
	ld	b, 4
	call	fx_copy
	call	fx_abs_ab		; |a|, |a|
	call	fx_mulu			; a²
	ld	hl, fx_n
	ld	de, fx_w
	ld	b, 8
	call	fx_copy
	ld	hl, fx_a
	ld	de, fx_t
	ld	b, 4
	call	fx_copy
	ld	hl, fx_b
	ld	de, fx_t
	ld	b, 4
	call	fx_copy
	call	fx_abs_ab
	call	fx_mulu			; b²
	ld	hl, fx_n
	ld	de, fx_w
	ld	b, 8
	call	fx_addm
	call	fx_isqrt
	jp	fx_sqrt_r

; HL = угол в градусах (любой, со знаком) -> fx_cos, fx_sin
fx_sincos:
fx_sc_neg:
	ld	a, h
	or	a
	jp	p, fx_sc_big
	ld	de, 360
	add	hl, de
	jp	fx_sc_neg
fx_sc_big:
	ld	d, h
	ld	e, l			; DE = последнее неотрицательное
	ld	bc, -360
	add	hl, bc
	ld	a, h
	or	a
	jp	p, fx_sc_big
	ex	de, hl			; HL = 0..359
	xor	a
	ld	(fx_q), a
fx_sc_q:
	ld	d, h
	ld	e, l
	ld	bc, -90
	add	hl, bc
	ld	a, h
	or	a
	jp	m, fx_sc_r
	ld	a, (fx_q)
	inc	a
	ld	(fx_q), a
	jp	fx_sc_q
fx_sc_r:
	ex	de, hl			; L = r (0..89)
	ld	a, l
	push	af
	call	fx_sinv			; sin(r) -> fx_sin
	ld	hl, fx_sin
	ld	de, fx_t
	ld	b, 4
	call	fx_copy
	pop	af
	ld	b, a
	ld	a, 90
	sub	b
	call	fx_sinv			; sin(90 - r) = cos(r) -> fx_t
	ld	hl, fx_cos
	ld	de, fx_t
	ld	b, 4
	call	fx_copy
	ld	a, (fx_q)
	or	a
	ret	z			; квадрант 0: [c, s]
	dec	a
	jp	z, fx_sc_q1
	dec	a
	jp	z, fx_sc_q2
	; квадрант 3: [s, -c]
	call	fx_sc_swap
	ld	hl, fx_sin
	ld	b, 4
	jp	fx_negm
fx_sc_q1:				; [-s, c]
	call	fx_sc_swap
	ld	hl, fx_cos
	ld	b, 4
	jp	fx_negm
fx_sc_q2:				; [-c, -s]
	ld	hl, fx_cos
	ld	b, 4
	call	fx_negm
	ld	hl, fx_sin
	ld	b, 4
	jp	fx_negm
fx_sc_swap:
	ld	hl, fx_t
	ld	de, fx_cos
	ld	b, 4
	call	fx_copy
	ld	hl, fx_cos
	ld	de, fx_sin
	ld	b, 4
	call	fx_copy
	ld	hl, fx_sin
	ld	de, fx_t
	ld	b, 4
	jp	fx_copy
; A = градусы 0..90 -> fx_t = sin (Q16.16)
fx_sinv:
	ld	l, a
	ld	h, 0
	add	hl, hl
	ld	de, fx_sin_tab
	add	hl, de
	ld	e, (hl)
	inc	hl
	ld	d, (hl)
	ex	de, hl
	ld	(fx_t), hl
	ld	hl, 0
	cp	90
	jp	nz, fx_sinv_s
	inc	hl			; sin 90° = 65536
fx_sinv_s:
	ld	(fx_t + 2), hl
	ret

; A = atan(fx_a) в градусах, усечение к нулю. Наибольшее d (0..89), для которого tan(d) <= |fx_a|.
fx_atan:
	call	fx_abs_a
	xor	a
	ld	(fx_lo), a
	ld	a, 89
	ld	(fx_hi), a
fx_at_l:
	ld	a, (fx_lo)
	ld	b, a
	ld	a, (fx_hi)
	cp	b
	jp	z, fx_at_e
	add	a, b
	inc	a
	rra				; mid = (lo + hi + 1) / 2 (сумма < 256, CF = 0 после inc? — см. ниже)
	ld	(fx_mid), a
	ld	l, a
	ld	h, 0
	add	hl, hl
	add	hl, hl
	ld	de, fx_tan_tab
	add	hl, de
	ex	de, hl			; DE -> tan(mid)
	ld	hl, fx_t
	ld	b, 4
	call	fx_copy
	ld	hl, fx_w		; fx_w = |a| - tan(mid)
	ld	de, fx_a
	ld	b, 4
	call	fx_copy
	ld	hl, fx_w
	ld	de, fx_t
	ld	b, 4
	call	fx_subm
	jp	c, fx_at_hi		; tan(mid) > |a|
	ld	a, (fx_mid)
	ld	(fx_lo), a
	jp	fx_at_l
fx_at_hi:
	ld	a, (fx_mid)
	dec	a
	ld	(fx_hi), a
	jp	fx_at_l
fx_at_e:
	ld	a, (fx_sg)
	or	a
	ld	a, (fx_lo)
	ret	z
	cpl
	inc	a
	ret

	include	"fx_tab.inc"
fx_end:

fx_a:		ds	4
fx_b:		ds	4
fx_cos:		ds	4
fx_sin:		ds	4
fx_w:		ds	8
fx_n:		ds	8
fx_d:		ds	5
fx_rm:		ds	5
fx_rt:		ds	5
fx_tr:		ds	5
fx_t:		ds	4
fx_sg:		db	0
fx_lo:		db	0
fx_hi:		db	0
fx_mid:		db	0
fx_q:		db	0
