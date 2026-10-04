; Заставка оригинала (только игровой образ): картинка 256×160 в 8 цветах своей палитры, сжата ZX0
; (v06c/tools/title2planes.py из кадра настоящей игры docs/img/orig-title.png). Распаковывается прямо на экран.

splash:
	ld	a, PH_SPLASH
	ld	(g_phase), a
	call	clear_screen
	ld	hl, sp_pal		; палитра картинки: цвета 0..7
	ld	de, pal_byte
	ld	b, 8
	call	gm_copy
	ld	a, 1
	ld	(pal_dirty), a
	ld	de, sp_zx0
	ld	bc, 0xA000
	call	dzx0
	ld	de, s_anykey
	ld	hl, 0x091B
	ld	bc, 0x0D03
	call	gm_text
	; клавиша, нажатая до заставки (ВК после команды в CP/M), не считается: сначала ждём, пока отпустят
spl_rel:
	halt
	call	kb_code
	or	a
	jp	nz, spl_rel
	xor	a
	ld	(gk_last), a
	jp	get_key
sp_pal:
	include	"title_pal.inc"
sp_zx0:
	incbin	"v06c/build/title.zx0"
splash_end:
