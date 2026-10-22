; Точка: запись и чтение в трёх плоскостях экрана A000h/C000h/E000h. Эталон — poke/peek и off16 в web/tankwars.js
; (экран там — массив 256×256 байт, индекс y·256 + x, цвет 0..7).
;
; Раскладка экрана Вектора: байт — 8 точек по горизонтали, бит 7 — левая. Плоскость — 32 столбца байтов по 256 байт;
; адрес байта = плоскость + (x>>3)·256 + (255 − y): младший байт адреса растёт снизу вверх, а прокрутка FFh
; (pal.asm, set_palette) ставит строку y = 0 наверх экрана. Цвет 0..7 раскладывается по битам: бит 0 — плоскость
; A000h, бит 1 — C000h, бит 2 — E000h (четвёртая плоскость 8000h в картинку не входит, docs/spec/v06c.md).
;
;   putpixel:   D = x, E = y, A = цвет 0..7. Портит все регистры.
;   getpixel:   D = x, E = y -> A = цвет. Портит A, B, C, E, HL.
;   putpixel16: BC = x, DE = y — слова со знаком; точка вне 0..255 не пишется (правило clip эталона: на Векторе
;               координата обрезается, а не заворачивается — docs/spec/v06c-screen.md, «Края экрана»).
;   plot_hlc:   точка по готовому адресу и маске — для циклов, которые сами шагают по экрану (линия, рамка, спрайты).

putpixel:
	ld	b, a
	ld	a, d
	rrca
	rrca
	rrca
	and	0x1F
	or	0xA0
	ld	h, a
	ld	a, e
	cpl		; 255 − y: младший байт адреса растёт снизу вверх
	ld	l, a
	ld	a, d
	and	7
	ld	c, 0x80
	jp	z, pp_mask
	ld	e, a
pp_sh:
	ld	a, c
	rrca
	ld	c, a
	dec	e
	jp	nz, pp_sh
; C = маска точки (80h, сдвинутая вправо на x&7), HL = адрес в плоскости A000h
pp_mask:
	ld	a, b
	cp	3		; цвет 3 (временный цвет эффектов) — отдельный короткий путь без разбора бит
	jp	nz, pp_other
	ld	de, 0x2000		; шаг к следующей плоскости; A000h и C000h — 1, E000h — 0
	ld	a, (hl)
	or	c
	ld	(hl), a
	add	hl, de
	ld	a, (hl)
	or	c
	ld	(hl), a
	add	hl, de
	ld	a, c
	cpl
	and	(hl)
	ld	(hl), a
	ret
; общий путь: три плоскости по очереди, D — цвет, сдвигаемый вправо (очередной бит — в CY), E — обратная маска
pp_other:
	ld	a, c
	cpl
	ld	e, a
	ld	d, b
	call	pp_plane
	ld	a, h
	add	a, 0x20
	ld	h, a
	call	pp_plane
	ld	a, h
	add	a, 0x20
	ld	h, a
; одна плоскость: очередной бит цвета 1 — поставить точку, 0 — снять. Портит A, D.
pp_plane:
	ld	a, d
	rrca
	ld	d, a
	jp	nc, pp_clr
	ld	a, (hl)
	or	c
	ld	(hl), a
	ret
pp_clr:
	ld	a, e
	and	(hl)
	ld	(hl), a
	ret
putpixel_end:

; Цвет точки: биты собираются из трёх плоскостей в B.
getpixel:
	ld	a, d
	rrca
	rrca
	rrca
	and	0x1F
	or	0xA0
	ld	h, a
	ld	a, e
	cpl
	ld	l, a
	ld	a, d
	and	7
	ld	c, 0x80
	jp	z, gp_mask
	ld	e, a
gp_sh:
	ld	a, c
	rrca
	ld	c, a
	dec	e
	jp	nz, gp_sh
gp_mask:
	xor	a
	ld	b, a
	ld	a, (hl)
	and	c
	jp	z, gp1
	ld	b, 1
gp1:
	ld	a, h
	add	a, 0x20
	ld	h, a
	ld	a, (hl)
	and	c
	jp	z, gp2
	ld	a, b
	or	2
	ld	b, a
gp2:
	ld	a, h
	add	a, 0x20
	ld	h, a
	ld	a, (hl)
	and	c
	jp	z, gp3
	ld	a, b
	or	4
	ld	b, a
gp3:
	ld	a, b
	ret
getpixel_end:

; Точка с координатами-словами (линия, ствол, крестик за краем поля). Старший байт не 0 — точка за экраном.
putpixel16:
	ld	(pix_c), a
	ld	a, b
	or	a
	ret	nz
	ld	a, d
	or	a
	ret	nz
	ld	d, c
	ld	a, (pix_c)
	jp	putpixel

; HL = адрес плоскости A, C = маска, A = цвет. Портит A,B,D,E; HL возвращается на A.
plot_hlc:
	ld	b, a
	ld	a, c
	cpl
	ld	e, a
	ld	d, b
	call	pp_plane
	ld	a, h
	add	a, 0x20
	ld	h, a
	call	pp_plane
	ld	a, h
	add	a, 0x20
	ld	h, a
	call	pp_plane
	ld	a, h
	sub	0x40
	ld	h, a
	ret

pixel_end:

; Маски точек по x&7. Таблица выровнена на 8 байт, чтобы low(pix_mask) + (x&7) не давало переноса в старший
; байт адреса (так её читает sprite.asm).
pix_c:	db	0
	ds	(8 - ($ & 7)) & 7
pix_mask:
	db	0x80, 0x40, 0x20, 0x10, 0x08, 0x04, 0x02, 0x01
