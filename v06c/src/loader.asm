; Tank Wars / Вектор-06Ц — загрузчик (v06c/build/game.rom, грузится с 0100h).
; Показывает заставку оригинала в 16 цветах (все четыре плоскости экрана, v06c/tools/title2planes.py), ждёт любую
; клавишу, затем распаковывает игру (game.bin, сжата ZX0) на 0100h и запускает её.
; Пока идёт заставка, весь файл лежит ниже 8000h — экран свободен целиком. Перед распаковкой игры сжатые данные
; и второй экземпляр распаковщика переносятся в самый верх памяти (в экран, палитра в это время чёрная).
	device	noslot64k
	org	0x0100

L_STACK		equ	0x8000		; стек загрузчика — под экраном
S2_STACK	equ	0xA000		; стек на время распаковки игры: выше игры, ниже перенесённых данных
S2_SIZE		equ	0x80		; место под вторую ступень в конце памяти
JOY_IDLE_CELL	equ	0x00F0		; значение покоя джойстика «П» для игры (game.asm), ниже её образа

ld_entry:
	di
	ld	sp, L_STACK
	ld	a, 0xC3			; JP ld_isr в векторе RST 7
	ld	(0x38), a
	ld	hl, ld_isr
	ld	(0x39), hl
	ld	a, 0x88			; порты ВВ55 на выход, прокрутка FFh, бордюр 0
	out	(0), a
	ld	a, 0xFF
	out	(3), a
	xor	a
	out	(2), a
	out	(1), a
	ld	a, 0x83			; джойстик «П»: ВВ55 №2, порт B — вход, опрос обоих; значение покоя — в ld_jidle
	out	(4), a
	ld	a, 0x9F
	out	(5), a
	in	a, (6)
	ld	(ld_jidle), a
	ld	(JOY_IDLE_CELL), a	; передать игре: она замерить не может (огонь, закрывший заставку, ещё нажат)
	ei
	call	ld_black
	ld	de, ld_zpic
	ld	bc, 0x8000
	call	lo.dzx0
	ld	hl, ld_pal + 15
	call	ld_palout
ld_rel:					; клавиша, нажатая до заставки (ВК после команды в CP/M), не считается
	call	ld_keys
	jp	nz, ld_rel
ld_wait:
	call	ld_keys
	jp	z, ld_wait
	call	ld_black
	di
	ld	hl, ld_end - 1		; сжатая игра и вторая ступень — в конец памяти, с последнего байта
	ld	de, 0xFFFF
	ld	bc, ld_end - ld_zgame
ld_mv:
	ld	a, (hl)
	ld	(de), a
	dec	hl
	dec	de
	dec	bc
	ld	a, b
	or	c
	jp	nz, ld_mv
	jp	s2_entry

ld_isr:
	ei
	ret

; все 16 регистров палитры — чёрные; запись идёт сразу после прерывания кадра, пока луч в бордюре
ld_black:
	halt
	ld	b, 15
ldb_lp:
	ld	a, b
	out	(2), a
	xor	a
	out	(0x0C), a
	out	(0x0C), a
	dec	b
	jp	p, ldb_lp
	jp	ldp_end
; палитра заставки: HL = последний из 16 байт. От 15 к 0, как в pal_out игры.
ld_palout:
	halt
	ld	b, 15
ldp_lp:
	ld	a, b
	out	(2), a
	ld	a, (hl)
	out	(0x0C), a
	out	(0x0C), a
	dec	hl
	dec	b
	jp	p, ldp_lp
ldp_end:
	xor	a
	out	(2), a
	ret

; клавиатура раз в кадр: ZF = 0, если нажата хоть одна клавиша матрицы
ld_keys:
	halt
	ld	a, 0x8A			; порт A — выход (выбор строки), порт B — вход
	out	(0), a
	xor	a
	out	(3), a			; все восемь строк сразу
	in	a, (2)
	cpl
	ld	b, a
	ld	a, 0x88			; назад: все порты на выход, прокрутка FFh, бордюр 0
	out	(0), a
	ld	a, 0xFF
	out	(3), a
	xor	a
	out	(2), a
	out	(1), a
	in	a, (6)			; джойстик «П»: любой бит, отличный от покоя, — нажатие
	ld	hl, ld_jidle
	xor	(hl)
	or	b
	ret
ld_jidle:	db	0xFF

	module	lo
	include	"dzx0.asm"
	endmodule
ld_pal:
	include	"title_pal.inc"
ld_zpic:
	incbin	"v06c/build/title.zx0"
ld_zgame:
	incbin	"v06c/build/game.zx0"
ld_zgame_end:
; вторая ступень: работает из конца памяти
	disp	0x10000 - S2_SIZE
s2_entry:
	ld	sp, S2_STACK
	ld	de, 0x10000 - S2_SIZE - (ld_zgame_end - ld_zgame)
	ld	bc, 0x0100
	call	hi.dzx0
	jp	0x0100
	module	hi
	include	"dzx0.asm"
	endmodule
s2_end:
	ds	0x10000 - $
	ent
ld_end:
	assert	ld_end <= L_STACK - 0x40, загрузчик с данными достаёт до стека и экрана
	assert	0x10000 - S2_SIZE - (ld_zgame_end - ld_zgame) >= S2_STACK + 0x100, сжатая игра не помещается над стеком распаковки
	savebin	"v06c/build/game.rom", 0x0100, ld_end - 0x0100
