"""Общие функции проб T03: загрузка игры до раунда, остановка на адресе Ghidra."""
import sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts' / 't03'))
sys.path.insert(0, str(ROOT / 'scripts' / 'ref'))
sys.path.insert(0, str(ROOT / 'scripts'))
from gamerun import Game, key, KEY_DOWN  # noqa: E402


def computer_keys(players: int, ai: int = 2):
    """Клавиши экрана игроков: всех сделать компьютерами типа ai (0 Random, 1 Mr. Stupid, 2 Lobber,
    3 Rifleman, 4 Lob & Shoot, 5 Windless Wit, 6 Twanger)."""
    from gamerun import KEY_RIGHT
    ks = []
    for i in range(players):
        ks += [key('C')] + [KEY_DOWN] * ai + [key('\r')]
        if i < players - 1:
            ks.append(KEY_RIGHT)
    return ks


def run_to(g: Game, gseg: int, off: int, budget: int = 2_000_000_000) -> None:
    """Исполнять до адреса Ghidra gseg:off (резидентный или оверлейный сегмент)."""
    target = (g.ghidra_abs(gseg), off)
    used = 0
    while used < budget:
        r = g.run(100_000_000, until=target)
        used += 100_000_000
        if r == 'until':
            return
        if r in ('exit',) or r.startswith('error'):
            raise RuntimeError(f'{r} at {g.where()}')
        if r == 'key':
            raise RuntimeError(f'game waits for key at {g.where()}')
    raise RuntimeError(f'budget exhausted at {g.where()}')


def boot_to_round(dos_time=(0x0C1E, 0x0F32), players_keys=None, players=2) -> Game:
    """Заставка -> меню -> START -> экран игроков -> 'S'. Игроки по умолчанию: 2 компьютера."""
    g = Game(dos_time=dos_time)
    for _ in range(30):
        if g.run(100_000_000) == 'key':
            break
    from gamerun import KEY_RIGHT, KEY_LEFT
    adj = [KEY_RIGHT] * (players - 2) if players >= 2 else [KEY_LEFT] * (2 - players)
    g.keys += [KEY_DOWN] * 2 + adj + [KEY_DOWN] * 2 + [key('\r')]
    for _ in range(30):
        r = g.run(100_000_000)
        if r == 'key' and not g.keys:
            break
    g.keys += (players_keys or []) + [key('S')]
    return g
