; Рельеф раунда — generateTerrain() эталона web/tankwars.js в профиле PROFILE_V06C (ветка fixed).
; Вход:  A = число игроков (2..4); RandSeed — в rand_seed (random.asm).
; Выход: terr_top[x], x = 0..255 — верхняя строка земли в столбце x (байт); 0xFF — столбца нет.
;        Если col(x, h) вызывается для одного x несколько раз, остаётся наименьшее значение top = 253 - h.
;        terr_h — итоговая высота h (слово). RandSeed продвинут ровно так же, как в эталоне.
; Подпрограммы: random (DE = n -> HL = Random(n)), rnd_hi (HL = старшие 16 бит следующего RandSeed).
; ЗАГЛУШКА: задача Q1 (docs/tasks/Q1-terrain.md).

gen_terrain:
	ret
gen_terrain_end:

terr_top:	ds	256
terr_h:		dw	0
