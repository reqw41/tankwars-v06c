; Шаг компьютерного игрока и служебное для цикла раунда — chooseCode(), turnBegin(), nextAlive() эталона и
; определение конца раунда. Игрок — запись в players (player.inc).
;   choose_code:  вход A = место игрока; выход A = код действия 1..8 (план — в полях PL_AI_*).
;   turn_begin:   вход A = место игрока: счётчик истории PL_AI_N += 1.
;   next_alive:   вход A = текущее место (0..n); выход A = следующее живое место по кругу.
;   round_winner: выход CF = 1, если раунд окончен (живых не больше одного); тогда A = место победителя или 0.
; ЗАГЛУШКА: задача Q8 (docs/tasks/Q8-aistep.md).

choose_code:
	ld	a, 5
	ret

turn_begin:
	ret

next_alive:
	ret

round_winner:
	or	a
	ret
aistep_end:
