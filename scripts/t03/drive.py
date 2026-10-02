"""Пошаговое управление игрой: drive(steps) где steps — список (keys, label); сохраняет кадры."""
import sys, time
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from gamerun import Game, key, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT

def boot(g=None, max_steps=20):
    g = g or Game()
    for _ in range(max_steps):
        r = g.run(100_000_000)
        if r == 'key':
            return g
    raise RuntimeError('menu not reached')

def feed(g, keys, label=None, outdir='work/T03/frames', budget=400_000_000):
    g.keys.extend(keys)
    used = 0
    while True:
        r = g.run(100_000_000)
        used += 100_000_000
        if r == 'key' and not g.keys:
            break
        if r in ('exit',) or r.startswith('error') or used >= budget:
            break
    if label:
        g.save_png(f'{outdir}/{label}.png')
    return r
