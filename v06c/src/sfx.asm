; Звуковые эффекты игры: таблицы для snd_play (sound.asm). Нота — делитель ВИ53 (1 500 000 / частота) и длительность
; в кадрах; делитель 1 — пауза; конец — слово 0. Играет прерывание кадра (snd_tick), игра не ждёт.
; В оригинале звук тратил случайные числа; здесь — нет: эталон сверяется при выключенном звуке.

; запуск эффекта HL; в игре — с запретом прерываний, чтобы snd_tick не застал таблицу наполовину сменённой
sfx_play:
	ifdef	GAME
	di
	endif
	call	snd_play
	ifdef	GAME
	ei
	endif
	ret

	macro	NOTE div, frames
	dw	div
	db	frames
	endm

sfx_shot:				; выстрел: короткий взлёт тона
	NOTE	1875, 1
	NOTE	1500, 1
	NOTE	1250, 1
	NOTE	1070, 1
	NOTE	940, 2
	dw	0
sfx_boom:				; взрыв: низкий спадающий гул
	NOTE	9000, 2
	NOTE	12000, 2
	NOTE	16000, 2
	NOTE	21000, 3
	NOTE	28000, 3
	NOTE	36000, 4
	dw	0
sfx_death:				; гибель танка: вой с перебивами
	NOTE	3000, 3
	NOTE	6000, 3
	NOTE	3500, 3
	NOTE	7000, 3
	NOTE	4000, 3
	NOTE	9000, 3
	NOTE	5000, 3
	NOTE	12000, 6
	dw	0
sfx_click:				; клавиша в меню
	NOTE	1500, 1
	dw	0
sfx_win:				; конец раунда
	NOTE	2867, 4
	NOTE	2273, 4
	NOTE	1911, 4
	NOTE	1433, 10
	dw	0
sfx_laser:				; лазер: высокий дрожащий тон
	NOTE	500, 2
	NOTE	560, 2
	NOTE	500, 2
	NOTE	560, 2
	NOTE	500, 2
	NOTE	560, 2
	dw	0
