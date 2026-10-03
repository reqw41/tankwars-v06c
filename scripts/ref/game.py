"""Ход Tank Wars 2.5 целиком: от решения игрока (2583:2976) до конца обработки смертей (2583:2cee).

Порядок как в цикле раунда 2583:2531:
  выстрел: Laser (оружие 5, 2583:140f) или FireShot (2583:01c0):
      боезапас[w] -= 1; наведение Herb/Vick -= 1; Random < 0.2 -> men -= 1; полёт (ballistics);
      при попадании (земля/танк) -> эффект оружия 318e:00e0 (explosion / weapons)
  перерисовать все танки (1062:059f); если Crumble% > 0 -> 2b39:03da; если Tanks Fall -> 2b39:0020
  смерти, пока они случаются (2583:2b04..2ce9): men <= 0 и alive -> alive = 0; вариант Random(7) (death.py);
      стрелку +1500 очков, если погиб не он; рамка; Random*100 < Crumble% -> осыпание; Tanks Fall -> падение
"""
from __future__ import annotations

import struct
from dataclasses import dataclass, field
from typing import List

try:
    from tanks import Tank, draw_tank_with_barrel, draw_frame
    from ballistics import FlightInput, Terrain, simulate, StopReason
    from explosion import explode, Player, RADIUS
    from crumble import crumble_gate, tanks_fall, crumble
    import weapons as W
    import death as D
except ImportError:  # pragma: no cover
    from .tanks import Tank, draw_tank_with_barrel, draw_frame
    from .ballistics import FlightInput, Terrain, simulate, StopReason
    from .explosion import explode, Player, RADIUS
    from .crumble import crumble_gate, tanks_fall, crumble
    from . import weapons as W
    from . import death as D

STRIDE = 0x61
# смещения в записи игрока (от DS:3EFC + 0x61*i)
OFF = {'x': (0x00, 'h'), 'y': (0x02, 'h'), 'score': (0x04, 'i'), 'power': (0x0E, 'h'), 'angle': (0x10, 'h'),
       'facing': (0x12, 'h'), 'men': (0x14, 'h'), 'alive': (0x16, 'B'), 'weapon': (0x17, 'h'), 'guided': (0x19, 'h'),
       'target': (0x1B, 'h'), 'herb': (0x1D, 'h'), 'vick': (0x1F, 'h'), 'energy': (0x2B, 'h'), 'shield': (0x45, 'i'),
       'damp': (0x49, 'i')}
AMMO = 0x21          # слово на оружие 0..17


@dataclass
class P(Tank):
    rec: bytearray = field(default_factory=bytearray)
    score: int = 0
    shield: int = 0
    damp: int = 0
    energy: int = 0
    weapon: int = 0
    guided: int = 0
    target: int = 0
    herb: int = 0
    vick: int = 0

    @classmethod
    def from_rec(cls, idx: int, raw: bytes) -> 'P':
        d = {k: struct.unpack_from('<' + f, raw, o)[0] for k, (o, f) in OFF.items()}
        p = cls(idx=idx, x=d['x'], y=d['y'], angle=d['angle'], power=d['power'], facing=d['facing'], men=d['men'],
                alive=bool(d['alive']), rec=bytearray(raw))
        for k in ('score', 'shield', 'damp', 'energy', 'weapon', 'guided', 'target', 'herb', 'vick'):
            setattr(p, k, d[k])
        return p

    def ammo(self, w: int) -> int:
        return struct.unpack_from('<h', self.rec, AMMO + 2 * w)[0]

    def set_ammo(self, w: int, n: int):
        struct.pack_into('<h', self.rec, AMMO + 2 * w, ((n + 0x8000) & 0xFFFF) - 0x8000)

    def to_rec(self) -> bytes:
        for k, (o, f) in OFF.items():
            val = getattr(self, k)
            if k == 'alive':
                val = 1 if val else 0
            if f == 'h':
                val = ((val + 0x8000) & 0xFFFF) - 0x8000
            elif f == 'i':
                val = ((val + 0x80000000) & 0xFFFFFFFF) - 0x80000000
            struct.pack_into('<' + f, self.rec, o, val)
        return bytes(self.rec)


@dataclass
class Flags:
    rebound: bool
    crumble: int
    fall: bool
    xkill: bool
    sound: bool
    wind: int
    ball_visible: bool = True
    trail: bool = False


def _effect(v, bg, ps: List[P], shooter: int, x: float, y: float, hit: int, rng, fl: Flags):
    """318e:00e0 — диспетчер по оружию стрелка."""
    w = ps[shooter - 1].weapon
    if w in RADIUS:
        pls = [Player(p.idx, p.x, p.y, p.men, p.shield, p.score, p.alive) for p in ps]
        explode(v, bg, pls, x, y, hit, shooter, w, rng, fl.sound)
        for p, q in zip(ps, pls):
            p.men, p.shield, p.score = q.men, q.shield, q.score
    elif 6 <= w <= 10:
        recs = [bytearray(p.to_rec()) for p in ps]
        W.cri(v, bg, recs, x, y, hit, shooter, w, rng, fl.sound)
        for p, r in zip(ps, recs):
            q = P.from_rec(p.idx, r)
            p.men, p.shield, p.score = q.men, q.shield, q.score
    elif w == 12:
        W.sonic(v, bg, x, y, rng, fl.sound)
    elif 13 <= w <= 16:
        W.dirt_ball(v, x, y, w)
    elif w == 17:
        W.explosive_dirt(v, bg, x, y, rng, fl.sound, fl.crumble)


CROSS = ((0, 0), (0, 1), (0, -1), (1, 0), (-1, 0))     # 1062:01e3 / 0213


def _k12():
    import struct
    from real48 import real48_to_float
    return real48_to_float(struct.pack('<3H', 0x9A81, 0x9999, 0x1999))


K12 = _k12()                                             # 2583:0dd0, Real48 1.2


def _cross(v, src, x, y, color=None):
    b = (y * 320 + x) & 0xFFFF
    for dx, dy in CROSS:
        o = (b + dy * 320 + dx) & 0xFFFF
        if o < len(v):
            v[o] = color if color is not None else (src[o] if o < len(src) else 0)


def flight_draw(v, bg, inp, shooter: int, ball_visible: bool, trail: bool, players: int = 1):
    """Полёт 2583:01c0 с отрисовкой мяча и следа (VRAM и фон меняются по ходу, как в оригинале).

    Цикл тот же, что ballistics._simulate_real48 (T02); добавлено:
      до проверки столкновения — в предыдущей точке (если 11 < X < 309 и Y > 31): стереть мяч из фона (видимый мяч),
          след цветом 100-стрелок в экран и фон (2583:0986..09f4);
      после проверки, если полёт продолжается и точка в поле — мяч-крестик цветом 19 (2583:11a9);
      при остановке — стереть крестик из фона, если 0 < X < 320 и 0 < Y < 200 (2583:12f7..13a1, всегда).
    Возвращает (stop, x, y, hit_color).
    """
    from ballistics import (q, deg_to_rad, trunc0, BARREL, POWER_DIV, STEP_DIV, GRAVITY, WIND_DIV, DIAMOND,
                            _advance_substep, _hit_should_stop, _is_hit_color, TANK_COLOR_LO, TANK_COLOR_HI,
                            BOUNCE_SCALE, WALL_LEFT, WALL_RIGHT, WALL_TOP, WALL_BOTTOM, SNAP_Y, Y_KILL_LO, Y_KILL_HI)
    from real48 import float_to_real48
    import math
    rad = deg_to_rad(inp.angle)
    c, s = W._trig(inp.angle) if hasattr(W, '_trig') else (q(math.cos(rad)), q(math.sin(rad)))
    x = q(q(float(inp.tank_x)) + q(q(c * BARREL) * float(inp.facing)))
    y = q(q(float(inp.tank_y)) - q(s * BARREL))
    vx = q(q(q(float(inp.power) / POWER_DIV) * c) * float(inp.facing))
    vy = q(q(float(inp.power) / POWER_DIV) * s)
    if float_to_real48(vy)[0] != 0:
        vy = q(-vy)
    # DS:3EAC (номер подшага) перед полётом = число игроков: его оставляет цикл палитры 2583:054b..05a3
    step, fuse, sub = STEP_DIV, 1000 - 2 * inp.men, players
    px_prev, py_prev = -99.0, -99.0
    tcol = (100 - shooter) & 0xFF
    get = lambda X, Y: v[Y * 320 + X] if 0 <= X < 320 and 0 <= Y < 200 else 0
    for _ in range(inp.max_steps):
        sub = _advance_substep(sub, step)
        x = q(x + q(vx / step)); y = q(y + q(vy / step))
        vy = q(vy + q(GRAVITY / step)); vx = q(vx + q(q(float(inp.wind) / WIND_DIV) / step))
        if px_prev < 309.0 and py_prev > 31.0 and px_prev > 11.0:
            ix, iy = trunc0(px_prev), trunc0(py_prev)
            if ball_visible:
                _cross(v, bg, ix, iy)
            if trail:
                o = (iy * 320 + ix) & 0xFFFF
                v[o] = tcol
                bg[o] = tcol
        px_prev, py_prev = x, y
        px, py = trunc0(x), trunc0(y)
        stop, hit = None, 0
        if (y < 189.0) and (x < 309.0) and (y > 33.0) and (x > 11.0):
            # 2583:0c52..0e1d: все 5 точек ромба без прерывания; 3EE4 = последний «цветной» пиксель
            done = False
            for dx, dy in DIAMOND:
                cp = get(px + dx, py + dy)
                if cp == 2 or TANK_COLOR_LO <= cp <= TANK_COLOR_HI:
                    hit = cp
                    tank = TANK_COLOR_LO <= cp <= TANK_COLOR_HI
                    if tank or sub == step or inp.power < fuse:
                        done = True
                    if cp == 2 and inp.power == fuse:
                        done = False
                    if tank and 12 <= inp.weapon <= 16:          # 2583:0d71: отскок грязи от танка
                        done = False
                        vy = q(q(-vy) * K12)
                        inp.guided = 0
            if done:
                stop = 'tank' if TANK_COLOR_LO <= hit <= TANK_COLOR_HI else 'terrain'
        else:
            if inp.rebound:
                if vx < 0 and x < WALL_LEFT: vx = q(-vx)
                if vx > 0 and x > WALL_RIGHT: vx = q(-vx)
                if vy < 0 and y < WALL_TOP: vy = q(-vy)
                if vy > 0 and y > WALL_BOTTOM: vy = q(-vy)
            elif inp.guided == 0:
                if vx > 1.0 and x > WALL_RIGHT and inp.wind > 0: y = SNAP_Y
                if vx < 1.0 and x < WALL_LEFT and inp.wind < 0: y = SNAP_Y
        if stop is None and (y < Y_KILL_LO or y > Y_KILL_HI):
            stop = 'bounds'
        if stop is not None:
            if 0.0 < y < 200.0 and 0.0 < x < 320.0:
                _cross(v, bg, trunc0(x), trunc0(y))
            return stop, x, y, hit
        if ball_visible and x < 309.0 and y > 31.0 and x > 11.0:
            _cross(v, None, px, py, 19)
    return 'max', x, y, 0


def fire(v, bg, ps: List[P], shooter: int, rng, fl: Flags):
    s = ps[shooter - 1]
    if s.weapon == 5:                                  # Laser
        recs = [bytearray(p.to_rec()) for p in ps]
        W.laser(v, bg, recs, shooter, rng, fl.sound, fl.rebound)
        for p, r in zip(ps, recs):
            q = P.from_rec(p.idx, r)
            p.men, p.shield, p.energy, p.power = q.men, q.shield, q.energy, q.power
        return
    s.set_ammo(s.weapon, s.ammo(s.weapon) - 1)         # 2583:02f1
    if s.guided in (1, 3):
        s.herb -= 1
    if s.guided in (2, 3):
        s.vick -= 1
    if rng.real() < W._LASER_P:                        # 2583:0348: 0.2 -> men - 1
        s.men -= 1
    terr = Terrain(v)
    if s.guided:
        t = ps[s.target - 1] if 1 <= s.target <= len(ps) else s
        positions = W.guided_positions(bytes(v), s.x, s.y, s.angle, s.power, s.facing, s.men, s.guided, t.x, t.y, fl.wind)
        raise NotImplementedError('наведение в модели хода ещё не подключено')
    stop, x, y, hit = flight_draw(v, bg, FlightInput(angle=s.angle, power=s.power, facing=s.facing, tank_x=s.x,
                                  tank_y=s.y, wind=fl.wind, rebound=fl.rebound, weapon=s.weapon, guided=0, men=s.men),
                                  shooter, fl.ball_visible, fl.trail, len(ps))
    if stop in ('terrain', 'tank'):
        _effect(v, bg, ps, shooter, x, y, hit, rng, fl)


DEATH = {0: D.death0, 1: D.death1, 2: D.death2, 3: D.death3, 4: D.death4, 5: D.death5, 6: D.death6}


def turn(v: bytearray, bg: bytes, ps: List[P], shooter: int, rng, fl: Flags):
    fire(v, bg, ps, shooter, rng, fl)
    for p in ps:
        draw_tank_with_barrel(v, p)                    # 2583:29c5
    if fl.crumble > 0:
        crumble_gate(v, bg, rng, fl.crumble, fl.rebound)
    if fl.fall:
        _fall(v, bg, ps, rng, fl)
    while True:                                        # 2583:2b04..2ce9
        died = False
        for p in ps:
            if p.men > 0 or not p.alive:
                continue
            died = True
            p.alive = False
            variant = rng.word(7)
            kw = {'wind': fl.wind, 'explosions_kill': fl.xkill} if variant in (0, 1, 2, 3) else {}
            DEATH[variant](v, bg, ps, p.idx, rng, fl.sound, **kw)
            if shooter != p.idx:
                ps[shooter - 1].score += 1500
            draw_frame(v, fl.rebound)                  # 1045:0025
            if rng.real() * 100.0 < fl.crumble:        # 2583:2ca0 jae: строго меньше
                crumble(v, bg)
            if fl.fall:
                _fall(v, bg, ps, rng, fl)
        if not died:
            break


def _fall(v, bg, ps, rng, fl):
    damp = {p.idx: p.damp for p in ps}
    tanks_fall(v, bg, ps, rng, fl.rebound, damp)
    for p in ps:
        p.damp = damp[p.idx]


# ---------- начало раунда: 2eef:0909 + 2583:2531..2675 ----------
def round_start(rng, ps: List['P'], walls_cfg: int, bg_cfg: int, wind_mode: int):
    """Возвращает (v, bg, rebound, wind, first_raw). ps — записи игроков (меняются: x, y, угол, мощность...).

    2eef:0922  Random <= 0.5 -> стены отражают; DS:820C: 0 — всегда нет, 2 — всегда да
    2eef:0999  фон: DS:8860 (0..5) или Random(6) при 6 — background.draw_background (экран = буфер фона)
    2eef:0a4f  рельеф, 2eef:0dbc расстановка/посадка танков (terrain.py, tanks.py)
    2583:255f  Random(N) — с какого игрока начать (первым ходит следующий живой после него)
    2583:2567  ветер (wind.py): DS:81F6, 5 = Random(5)
    """
    try:
        from background import draw_background
        from terrain import generate, render
        from tanks import place_tanks
    except ImportError:  # pragma: no cover
        from .background import draw_background
        from .terrain import generate, render
        from .tanks import place_tanks
    rebound = not (rng.real() > 0.5)
    if walls_cfg == 0:
        rebound = False
    if walls_cfg == 2:
        rebound = True
    kind = bg_cfg if bg_cfg <= 5 else rng.word(6)
    bg = draw_background(kind, rng)
    v = bytearray(bg)
    n = len(ps)
    render(generate(rng, n), v)
    tanks = place_tanks(rng, n, v, bg, rebound)
    for p, t in zip(ps, tanks):
        p.x, p.y, p.angle, p.power, p.facing, p.men, p.alive = t.x, t.y, t.angle, t.power, t.facing, t.men, True
    first_raw = rng.word(n)
    eff = rng.word(5) if wind_mode == 5 else wind_mode
    span = {0: 0, 1: 20, 2: 100, 3: 300, 4: 4000}.get(eff, 0)
    r = rng.word(span)
    w = ((int(span / 2) - r + 0x8000) & 0xFFFF) - 0x8000
    for th in (0.10000000000002274, 0.10000000000002274, 0.05000000000001137, 0.05000000000001137):
        if rng.real() < th:
            w = (((w << 2) & 0xFFFF) + 0x8000 & 0xFFFF) - 0x8000
    w = max(-30000, min(30000, w))
    return v, bg, rebound, w, first_raw
