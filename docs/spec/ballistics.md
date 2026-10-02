# Ballistics — Tank Wars 2.5 shot flight (`2583:01c0`)

Procedure: `TW_FireShot` = `FUN_2583_01c0` (player index on stack).  
Reference: unicorn traces `scripts/probe/flight_trace.py` → `work/T02/traces/`.  
Model: `scripts/ref/ballistics.py`.

## 1. Shot inputs

| Field | DS offset (player `p`, stride `0x61`) | Range / notes |
|---|---|---|
| X | `p*0x61 + 0x3efc` | int, tank centre |
| Y | `+0x3efe` | int, screen Y down |
| Power | `+0x3f0a` | 1 … `100*Men` (DOC); step 1 / Pg±10 |
| Angle | `+0x3f0c` | degrees; with facing covers 180° |
| Facing | `+0x3f0e` | `+1` right / `−1` left |
| Men | `+0x3f10` | health; max power = 100×Men |
| Weapon | `+0x3f13` | 1..18 |
| Guided | `+0x3f15` | >0 → seek / special (Herb's/Vick's etc.) |

0° = horizon toward `facing` (Cos=+facing, Sin=0). 90° = straight up.

Muzzle (barrel tip used for flight, length **10** px — draw path uses **8**):

```
θ = DegToRad(angle)
x0 = tank_x + Cos(θ) * 10 * facing
y0 = tank_y − Sin(θ) * 10
```

## 2. Initial velocity

```
speed = power / 50
vx = speed * Cos(θ) * facing
vy = − speed * Sin(θ)     # non-zero Sin result is negated (screen Y↓)
```

Constants: Real48 `50.0` (`86 00 00 00 00 48`), barrel `10.0` (`84 00 00 00 00 20`).

## 3. Integration step (`2583:05c8` loop)

At shot start `DS:3eb0 ← 10` (step divisor; also palette period).

Each iteration (Real48):

```
x  ← x + vx / 10
y  ← y + vy / 10
vy ← vy + 0.1 / 10          # gravity +0.01 per tick
vx ← vx + wind / 5000 / 10  # wind = int16 DS:3ede
```

No drag. Order: positions from velocity, then gravity on `vy`, then wind on `vx`.

### Wind (round setup, not this proc)

Menu force None/Norm/High/Gale sets span `DS:3eae` (e.g. Gale path uses 4000).  
`wind = 3eae/2 − RandomWord(3eae)`, then occasional `×4` jitter, clamp ±30000.  
Displayed as `|wind|`. Flight only reads `3ede`.

## 4. Pixel rounding

`SYSTEM_Trunc` (toward 0) of Real48 `x`,`y` for draw and collision.  
Model/traces record Trunc after each integration step (hook `2583:0b91`).

## 5. Collisions & end

**Collision band** (approx.): `11 < x < 309` and `33 < y < 189`.  
Else → wall logic.

**Sample** diamond `|dx|+|dy|≤1` around Trunc(x,y) via `TW_GetPixelVGA` (`1691:0b0a`).

Hit if color `== 2` (dirt) or `20..29` (tanks). Then:

- if `power < 1000−2*men` **or** tank color → `done=1` (unless `power == fuse` and dirt → cancel);
- weapons **12..16** on tank colors: `vy ← −vy * 1.2`, clear guided, continue.

**Walls** (`DS:8200`):

- Rebound on: if `vx<0 & x<10` or `vx>0 & x>310` → `vx ← −vx`; if `vy<0 & y<30` or `vy>0 & y>190` → `vy ← −vy`.
- Rebound off: if unguided and blown past side with wind (`vx>1 & x>310 & wind>0` or `vx<1 & x<10 & wind<0`) → `y ← 200`.

**Kill**: `y < −5000` or `y > 193` → done.

## 6. Drawing during flight

| Flag | Meaning |
|---|---|
| `8201==0` | Ball Visible: erase prev (`1062:0213`) / draw (`1062:01e3`) |
| `8202!=0` | Trail Visible (`1062:0352`) |
| Cycle Delay | `CRT_Delay(3)` when flying (`8201` path) |

Palette animation via `1057:0000`; sound gated by `81ff`.

## 7. Weapons that alter flight (branch only)

| Weapon / flag | Where | Effect (summary) |
|---|---|---|
| Guided `3f15>0` | `2583:06cf` | Steer vx/vy toward target player `3f17` |
| Weapons 12..16 | `2583:0d71` | Bounce on tank colors ×1.2 |
| Dirt-ball fuse | power vs `1000−2*men` | Special dirt cancel |
| Laser / Sonic / etc. | other overlays / post-hit `1054:0020` | **Outside T02** — explosion dispatch |

## 8. DS globals (flight)

See `re/game/names_T02.csv` (`TW_ShotX/Y/VX/VY`, `TW_Wind`, `TW_ReboundWalls`, …).

## 9. Real ranges & fixed-point

From `work/T02/traces/` + model sweeps (script-owned): typical `|x|,|y| ≲ 3000`, `|vx|,|vy| ≲ 30` for normal shots; extreme power can send `|x|` past 2000 before `y>193`.

**Proposal:** signed **16.16** (or 24.8) for x/y/vx/vy.  
`scripts/ref/ballistics.py` `fixed_point=True`: impact pixel matched **18/25** cached scenarios (`work/T02/fp_impact_matches.txt`).

## Pseudocode

```
fire(player):
  (x,y,vx,vy) = muzzle_and_velocity(player)
  step = 10; done = 0
  while not done:
    x += vx/step; y += vy/step
    vy += 0.1/step; vx += wind/(5000*step)
    px,py = Trunc(x), Trunc(y)
    if in_band(x,y):
      for (dx,dy) in diamond:
        c = GetPixel(px+dx, py+dy)
        if hit(c): handle_hit(...); break
    else:
      apply_walls_or_wind_snap(...)
    if y < -5000 or y > 193: done = 1
    draw/erase/delay...
  explode(hit_color, x, y, player)
```
