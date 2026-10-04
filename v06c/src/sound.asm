; Звук на таймере ВИ53 (канал 0): тон, тишина, мелодия-эффект по таблице, шаг раз в кадр.
;   snd_tone: вход HL = делитель (частота = 1 500 000 / делитель).
;   snd_off:  тишина.
;   snd_play: вход HL = адрес таблицы эффекта; первая нота звучит сразу.
;   snd_tick: вызывать раз в кадр; отсчитывает длительность ноты и берёт следующую.
; Только команды 8080. Таблица: ноты по 3 байта (делитель словом, младший первым; длительность в кадрах),
; конец — слово 0; делитель 1 — пауза. Свои ячейки — после sound_end, метки с snd_.

snd_tone:
	push	af
	ld	a, 0x36		; канал 0, меандр, делитель двумя байтами
	out	(0x08), a
	ld	a, l		; младший байт делителя
	out	(0x0B), a
	ld	a, h		; старший байт делителя
	out	(0x0B), a
	pop	af
	ret

snd_off:
	ld	a, 0x36		; счётчик без делителя молчит
	out	(0x08), a
	ret

snd_play:
	ld	(snd_ptr), hl
	jp	snd_next		; первая нота звучит сразу

snd_tick:
	ld	hl, (snd_ptr)
	ld	a, l
	or	a, h
	ret	z			; эффект не играет — в порты не пишем
	ld	a, (snd_cnt)
	dec	a
	ld	(snd_cnt), a
	ret	nz			; текущая нота ещё звучит
	jp	snd_next

; Взять следующую ноту по snd_ptr: делитель 0 — конец эффекта, 1 — пауза, иначе тон.
; Портит все регистры.
snd_next:
	ld	hl, (snd_ptr)
	ld	a, (hl)
	ld	e, a
	inc	hl
	ld	a, (hl)
	ld	d, a			; DE = делитель D следующей ноты
	inc	hl			; HL = адрес байта длительности
	ld	a, e
	or	a, d
	jp	z, snd_n_end		; слово 0 — эффект кончился
	ld	a, d
	or	a, a
	jp	nz, snd_n_go
	ld	a, e
	cp	1
	jp	z, snd_n_pause		; делитель 1 — пауза
snd_n_go:
	ld	a, (hl)
	ld	(snd_cnt), a		; кадров для текущей ноты
	inc	hl
	ld	(snd_ptr), hl		; следующая нота
	ex	de, hl
	jp	snd_tone
snd_n_pause:
	ld	a, (hl)
	ld	(snd_cnt), a
	inc	hl
	ld	(snd_ptr), hl
	jp	snd_off
snd_n_end:
	call	snd_off
	ld	hl, 0
	ld	(snd_ptr), hl		; эффект не играет
	ret
sound_end:

snd_ptr:	dw	0		; адрес следующей ноты; 0 — эффект не играет
snd_cnt:	db	0		; сколько кадров осталось текущей ноте
