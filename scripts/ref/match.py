"""Межраундовый цикл Tank Wars 2.5 (224b:327c): перетасовка игроков, бонус победителю, магазин.

Цикл: для раунда r = 1..DS:3EE8: перетасовка (224b:25a7) -> раунд (2583:2531) -> победителю DS:3EEC: wins+1 и
+1000*N очков -> экран результатов (224b:2641) -> магазин (224b:0e51), кроме последнего раунда.
Деньги игрока = score (+4) - spent (+8). Записи — 0x61 байт от DS:3EFC+0x61*i (как в game.P.rec).
"""
from __future__ import annotations

import struct
from typing import List

# DS:2B20 / DS:2B68 — цена и размер пачки оружия 0..17 (пачка 0 = не продаётся)
W_PRICE = (-1, 3000, 4000, 7000, 10000, 10000, 5000, 5000, 10000, 10000, 15000, -1, 4500, 4000, 6000, 8000, 10000, 4500)
W_PACK = (0, 100, 10, 2, 1, 1000, 5, 10, 3, 3, 1, 0, 10, 10, 7, 3, 1, 10)
G_PRICE, G_PACK = (20000, 20000), (5, 5)            # DS:2F8C / 2F94 — наведение (Herb's, Vick's), слова +0x1D+2i
D_PRICE, D_PACK = (20000, 10000), (1000, 100)       # DS:3398 / 33A0 — защита (щит, демпфер), LongInt +0x45+4i
PRICE = (W_PRICE, G_PRICE, D_PRICE)
PACK = (W_PACK, G_PACK, D_PACK)
MAX_QTY = 9
# стратегии закупки ИИ (DS:8896+0x802*p+0x800), выбираются Random(4)+1 при создании игрока (32ec:0139)
STRATEGY_SETS = {b'Mr. Stupid': (1, 2, 4), b'Lobber': (1, 2, 4), b'Windless Wit': (1, 2, 4),
                 b'Rifleman': (1, 2, 3, 4), b'Lob & Shoot': (1, 2, 3, 4), b'Twanger': (1, 2, 3, 4)}


def pick_strategy(name: bytes, rng) -> int:
    """32ec:0139: Random(4)+1, пока не попадёт в набор, разрешённый этому ИИ (прочим — любое)."""
    allowed = STRATEGY_SETS.get(name)
    while True:
        s = rng.word(4) + 1
        if allowed is None or s in allowed:
            return s


def min_price() -> int:
    """224b:0e6f..0f6e: наименьшая цена среди всего продаваемого (нач. 0x7FFF)."""
    m = 0x7FFF
    for prices, packs in zip(PRICE, PACK):
        for pr, pk in zip(prices, packs):
            if pk != 0 and m > pr:
                m = pr
    return m


def shuffle(rng, recs: List[bytes], hists: List[bytes], ctrl: List[int]):
    """224b:25a7: Random(20)+10 обменов двух разных игроков (запись, структура ИИ, тип управления). Списки с 1."""
    n = len(recs) - 1
    for _ in range(rng.word(20) + 10):
        a = rng.word(n)
        while True:
            b = rng.word(n)
            if a != b:
                break
        a, b = a + 1, b + 1
        for lst in (recs, hists, ctrl):
            lst[a], lst[b] = lst[b], lst[a]


def winner_bonus(rec: bytearray, n_players: int):
    """224b:32f6..: победителю раунда +1 победа и +1000*N очков."""
    struct.pack_into('<h', rec, 0x0C, struct.unpack_from('<h', rec, 0x0C)[0] + 1)
    bonus = ((n_players * 1000 + 0x8000) & 0xFFFF) - 0x8000
    struct.pack_into('<i', rec, 4, struct.unpack_from('<i', rec, 4)[0] + bonus)


def results(rng, recs: List[bytes], hists: List[bytes], ctrl: List[int], auto: bool):
    """224b:2641, часть с состоянием: сортировка «пузырьком» (224b:0000) по победам, затем при равных победах по очкам,
    всем men (+0x14 от DS:3EFC) = 100. При DS:8864 != 0 (ожидания клавиши нет) — заставка из 200 случайных линий:
    по 5 вызовов Random на линию. Записи здесь — сырые 0x61 байт от DS:3EEE (wins +0x1A, score +0x12, men +0x22)."""
    n = len(recs) - 1

    def swap(a, b):
        for lst in (recs, hists, ctrl):
            lst[a], lst[b] = lst[b], lst[a]
    wins = lambda i: struct.unpack_from('<h', recs[i], 0x1A)[0]
    score = lambda i: struct.unpack_from('<i', recs[i], 0x12)[0]
    for _ in range(n):
        for e in range(1, n):
            if wins(e) < wins(e + 1):
                swap(e + 1, e)
    for _ in range(n):
        for e in range(1, n):
            if wins(e) == wins(e + 1) and score(e) < score(e + 1):
                swap(e + 1, e)
    for i in range(1, n + 1):
        r = bytearray(recs[i])
        struct.pack_into('<h', r, 0x22, 100)
        recs[i] = bytes(r)
    if auto:
        for _ in range(200):
            for m in (319, 199, 319, 199, 16):
                rng.word(m)


class _Rec:
    def __init__(self, rec: bytearray):
        self.r = rec
    score = property(lambda s: struct.unpack_from('<i', s.r, 4)[0])
    spent = property(lambda s: struct.unpack_from('<i', s.r, 8)[0],
                     lambda s, v: struct.pack_into('<i', s.r, 8, v))

    def have(self, cat: int, i: int) -> int:
        if cat == 0:
            return struct.unpack_from('<h', self.r, 0x21 + 2 * i)[0]
        if cat == 1:
            return struct.unpack_from('<h', self.r, 0x1D + 2 * i)[0]
        return struct.unpack_from('<i', self.r, 0x45 + 4 * i)[0]

    def add(self, cat: int, i: int, n: int):
        if cat == 0:
            struct.pack_into('<h', self.r, 0x21 + 2 * i, ((self.have(0, i) + n + 0x8000) & 0xFFFF) - 0x8000)
        elif cat == 1:
            struct.pack_into('<h', self.r, 0x1D + 2 * i, ((self.have(1, i) + n + 0x8000) & 0xFFFF) - 0x8000)
        else:
            struct.pack_into('<i', self.r, 0x45 + 4 * i, self.have(2, i) + n)


def build_menu(rec: bytearray):
    """224b:0118: позиции магазина по порядку — [(категория, номер)], нумерация позиций с 1.
    Оружие: пачка != 0 и (есть в запасе или по карману); наведение/защита: есть в запасе или (по карману и пачка != 0).
    «По карману» здесь — score - spent (без корзины)."""
    r = _Rec(rec)
    money = r.score - r.spent
    menu = []
    for w in range(18):
        if (r.have(0, w) > 0 or W_PRICE[w] <= money) and W_PACK[w] != 0:
            menu.append((0, w))
    for cat in (1, 2):
        for i in range(2):
            if r.have(cat, i) > 0 or (PRICE[cat][i] <= money and PACK[cat][i] != 0):
                menu.append((cat, i))
    return menu


def ai_choice(rec: bytearray, strategy: int, menu, qty, cart: int):
    """224b:173d..1ab8: номер позиции (с 1), которую ИИ «плюсует», или None = «Done»."""
    r = _Rec(rec)
    money = r.score - r.spent - cart
    count = len(menu)
    sel = None
    if strategy == 1:
        for c in range(count, 0, -1):
            cat, i = menu[c - 1]
            if cat == 0 and i in (1, 2, 3, 4) and r.have(0, i) + W_PACK[i] * qty[c] < 20 and W_PRICE[i] <= money:
                sel = c
        return sel
    if strategy in (2, 3):
        allowed = (1, 2, 3, 4) if strategy == 2 else (1, 2, 3, 4, 5)
        for c in range(1, count + 1):
            cat, i = menu[c - 1]
            if cat == 0 and i in allowed and W_PRICE[i] <= money:
                sel = c
    elif strategy == 4:
        for c in range(count, 0, -1):
            cat, i = menu[c - 1]
            if cat == 2 and i in (0, 1) and D_PRICE[i] <= money:
                sel = c
    else:
        return None
    if r.have(0, 1) + W_PACK[1] * qty.get(1, 0) < 20:        # Incinerator всегда держать >= 20 (позиция 1!)
        sel = 1
    return sel


def ai_shop(rec: bytearray, strategy: int, max_steps: int = 10000) -> bool:
    """Закупка одного компьютерного игрока (224b:0f86..2598). True — заходил в магазин."""
    r = _Rec(rec)
    if r.score - r.spent < min_price() or strategy == 0:
        return False
    menu = build_menu(rec)
    qty = {c: 0 for c in range(1, len(menu) + 1)}
    cart = 0
    for _ in range(max_steps):
        sel = ai_choice(rec, strategy, menu, qty, cart)
        if sel is None:
            break
        cat, i = menu[sel - 1]
        price = PRICE[cat][i]
        if qty[sel] < MAX_QTY and price <= r.score - r.spent - cart:
            cart += price
            qty[sel] += 1
    else:
        raise RuntimeError('ИИ в магазине зациклился (в оригинале — тоже: позиция с 9 штуками остаётся по карману)')
    spent = r.spent
    for c, (cat, i) in enumerate(menu, 1):                    # «Done»: 224b:2250..23f0
        if qty[c] > 0:
            spent += PRICE[cat][i] * qty[c]
            r.add(cat, i, PACK[cat][i] * qty[c])
    r.spent = spent
    return True
