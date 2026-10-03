; Матч: перетасовка игроков, бонус победителю, сортировка результатов — shufflePlayers(), winnerBonus(), results()
; эталона web/tankwars.js. Записи игроков — таблица players (player.inc), число игроков — n_players.
;
; shuffle_players: вход — n_players, RandSeed в rand_seed.
; winner_bonus:    вход A = место победителя 1..n.
; results_sort:    вход A = 1, если все игроки — компьютеры (тогда тратятся случайные числа), иначе 0.
; ЗАГЛУШКА: задача Q3 (docs/tasks/Q3-match.md).

shuffle_players:
	ret

winner_bonus:
	ret

results_sort:
	ret
match_end:

n_players:	db	0
players:	ds	MAX_PLAYERS * PL_SIZE
