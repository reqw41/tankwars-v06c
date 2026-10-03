; Запись игрока на 8080 (docs/spec/v06c-memory.md). Игрок на месте i (1..4) — запись i-1 в таблице players.
; Номер места и цвет танка на экране (3 + i) задаются положением записи; при перетасовке записи меняются целиком.
PL_X		equ	0	; байт
PL_Y		equ	1	; байт
PL_ANGLE	equ	2	; байт 0..90
PL_FACING	equ	3	; байт: 1 или 0xFF (-1)
PL_POWER	equ	4	; слово
PL_MEN		equ	6	; слово со знаком
PL_ALIVE	equ	8	; байт 0/1
PL_WEAPON	equ	9	; байт 0..17
PL_GUIDED	equ	10	; байт: бит 0 Herb, бит 1 Vick
PL_TARGET	equ	11	; байт: место цели
PL_HERB		equ	12	; слово
PL_VICK		equ	14	; слово
PL_SCORE	equ	16	; 4 байта со знаком
PL_SPENT	equ	20	; 4 байта со знаком
PL_WINS		equ	24	; слово
PL_CTRL		equ	26	; байт: 1 клавиатура, 3 компьютер
PL_STRAT	equ	27	; байт: стратегия закупки 0..4
PL_COLORS	equ	28	; 3 байта: делители R, G, B (1 или 0xFF — компоненты нет)
PL_SHIELD	equ	32	; 4 байта
PL_DAMP		equ	36	; 4 байта
PL_AMMO		equ	40	; 18 слов
PL_NAME		equ	76	; 14 байт: до 13 знаков и 0
PL_AI_N		equ	90	; байт: счётчик истории
PL_AI_PLAN	equ	91	; байт: план готов
PL_AI_POWER	equ	92	; слово
PL_AI_ANGLE	equ	94	; байт
PL_AI_FACING	equ	95	; байт
PL_AI_WEAPON	equ	96	; байт
PL_AI_TARGET	equ	97	; байт
PL_AI_S1	equ	98	; последний выстрел: мощность (слово), x (слово)
PL_AI_S2	equ	102	; предпоследний выстрел: мощность (слово), x (слово)
PL_SIZE		equ	108
MAX_PLAYERS	equ	4
