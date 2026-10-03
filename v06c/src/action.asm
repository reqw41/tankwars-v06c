; Действия хода — applyCode(), autoSwitchWeapon(), needsWeaponSwitch() эталона web/tankwars.js (PROFILE_V06C).
; Игрок — запись в players с местом ac_place (1..n).
;   apply_code:   вход A = код действия 1..10, ac_place.
;   auto_switch:  вход ac_place. Если у текущего оружия запас ровно 0 — перейти к следующему с запасом > 0.
;   needs_switch: вход ac_place. Выход CF = 1, если оружие надо менять (запас <= 0, или лазер с запасом <= 100).
; ЗАГЛУШКА: задача Q6 (docs/tasks/Q6-action.md).

apply_code:
	ret

auto_switch:
	ret

needs_switch:
	or	a
	ret
action_end:

ac_place:	db	0
