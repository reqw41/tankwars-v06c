; Планировщики компьютерных игроков, простая часть — planStupid(), planBirdy(), recordShot() эталона web/tankwars.js.
;   plan_stupid: вход A = место игрока 1..n, ap_rebound (0/1 — стены отражают). План — в поля PL_AI_* записи.
;   plan_birdy:  вход A = место игрока.
;   record_shot: вход A = место игрока, fl_x (4 байта Q16.16, flight.asm) — где кончился выстрел.
; ЗАГЛУШКА: задача Q10 (docs/tasks/Q10-aiplan.md).

plan_stupid:
	ret

plan_birdy:
	ret

record_shot:
	ret
aiplan_end:

ap_rebound:	db	0
