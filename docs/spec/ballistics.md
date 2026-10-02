# Ballistics — Tank Wars 2.5 shot flight (`2583:01c0`)

Procedure: `TW_FireShot` = `FUN_2583_01c0` (player index on stack).  
Reference: unicorn traces `scripts/probe/flight_trace.py` → `work/T02/traces/`.  
Model: `scripts/ref/ballistics.py`. Wind round setup: `scripts/ref/wind.py` (`2583:2567`).

## 1. Shot inputs

| Field | DS offset (player `p`, stride `0x61`) | Range / notes |
|---|---|---|
| X | `p*0x61 + 0x3efc` | int, tank centre |
| Y | `+0x3efe` | int, screen Y down |
| Power | `+0x3f0a` | 0 … **10×Men** (clamp); step 1 / Pg±100 (DOC) |
| Angle | `+0x3f0c` | **0..90** degrees (UI); not a full 0..180 counter |
| Facing | `+0x3f0e` | `+1` right / `−1` left — second half of the semicircle |
| Men | `+0x3f10` | health/crew (round start = **100** @ `2eef:0f48`); max power = **10×Men** |
| Weapon | `+0x3f13` | 1..18 |
| Guided | `+0x3f15` | >0 → seek / special (Herb's/Vick's etc.) |

**Angle system:** the gun covers 180° as **angle ∈ [0,90] plus facing ±1**.  
0° = horizon toward `facing`; 90° = straight up (facing only mirrors Cos for near-vertical).  
There is no stored “180°” angle — left horizon is `angle=0, facing=−1` (scenario `a0_facem1_p200`).

**Maximum Power** (proven): binary clamps power to **`10 × Men`**, not DOC’s `100*MEN`.

| Site | Role |
|---|---|
| `2583:2925..2957` | pre-fire clamp in `TW_StartRound` before AI / `TW_FireShot` |
| `2b39:0425` | keyboard ±power / Pg± also clamp to `men*10` |
| `30b8:08a1` | HUD string «Maximum Power:» prints `men*10` |

With round-start men=100 → max power **1000**. Execution: `scripts/probe/max_power_probe.py` → `work/T02/max_power_probe.json` (gamerun, computer players).

Muzzle (flight barrel length **10** px — draw path uses **8**):

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

### Wind (round setup — `FUN_2583_2531` @ `2583:2567`)

Proven by unicorn execution of original code (`scripts/ref/wind.py`).  
Menu mode `DS:81f6` (None/Low/Norm/High/Gale/RND = 0..5); effective mode in `81f8`.

| mode | name | span `3eae` |
|---|---|---|
| 0 | None | 0 |
| 1 | Low | 20 |
| 2 | Norm | 100 |
| 3 | High | 300 |
| 4 | Gale | 4000 |
| 5 | RND | `RandomWord(5)` picks 0..4 |

```
r = RandomWord(span)           # 0 if span=0
wind = span/2 − r              # signed IDIV
for p in (0.1, 0.1, 0.05, 0.05):
    if RandomReal() < p: wind ← wind * 4   # two SHL
clamp wind to [-30000, +30000]
```

Distributions (n=1000 seeds each): see `work/T02/wind_dist.json` (Gale min/max ≈ −29184 / +28960).  
Flight only reads finished `DS:3ede`.

## 4. Pixel rounding

`SYSTEM_Trunc` (toward 0) of Real48 `x`,`y` for draw and collision.  
Model/traces record Trunc after each integration step (hook `2583:0b91`).

## 5. Collisions & end

**Collision band** (approx.): `11 < x < 309` and `33 < y < 189`.  
Else → wall logic.

**Sample** diamond `|dx|+|dy|≤1` around Trunc(x,y) via `TW_GetPixelVGA` (`1691:0b0a`).

Hit if color `== 2` (dirt) or `20..29` (tanks). Then (`2583:0cfd..0d6c`):

Local at shot entry (`2583:01ce`):  
`thresh = 1000 − 2*Men`  (`Men` = word at player+`0x3f10`; stored `[bp-2]`).

`DS:3eac` — subframe counter in the flight loop (`2583:05c8..05d7`): each physics step does
`3eac++`; if `3eac > 3eb0` (10) then `3eac ← 0`. After palette with `3edc=1`, starts at 1
(so first step uses 3eac=2; values cycle `…,10,0,1,…`).

```
# when diamond finds color 2 or 20..29:
stop = (color in 20..29) OR (3eac == 3eb0) OR (power < thresh)
if color == 2 AND power == thresh:
    stop = false   # only exact threshold flies through dirt
```

Consequences:

- `power < thresh`: stop on first dirt contact.
- `power > thresh`: keep integrating **inside dirt until subframe 3eac==10**, then stop
  (finishes the current 10-step “frame”, does not tunnel forever).
- `power == thresh` + dirt: never stop on dirt (full pass-through until y-bounds / tank).

Then weapons **12..16** on tank colors: `vy ← −vy * 1.2`, clear guided, continue (no explode).

**Semantics for real men (0..100):** `thresh = 1000 − 2·men`.

| men | thresh | legal max `10×men` | dirt behaviour |
|---|---|---|---|
| 100 | 800 | 1000 | `<800` immediate stop; `>800` stop at subframe 10; `==800` pass-through |
| 50 | 900 | 500 | all legal powers `<900` → immediate stop |

Traces: `fuse_m100_p*` / `fuse_m50_p*` in `flight_trace.SCENARIOS` (dirt wall, pixel-matched).

**Walls** (`DS:8200`):

- Rebound on: if `vx<0 & x<10` or `vx>0 & x>310` → `vx ← −vx`; if `vy<0 & y<30` or `vy>0 & y>190` → `vy ← −vy`.
- Rebound off: if unguided and blown past side with wind (`vx>1 & x>310 & wind>0` or `vx<1 & x<10 & wind<0`) → `y ← 200`.

**Kill**: `y < −5000` or `y > 193` → done.

## 6. Drawing during flight

| Flag | Meaning |
|---|---|
| `8201==0` | Ball Visible: erase prev (`1062:0213`) / draw (`1062:01e3`) |
| `8202!=0` | Trail Visible (`1062:0352`) |
| Cycle Delay | `CRT_Delay(3)` when flying (`8201` path) — 3 ms/step |

Palette animation via `1057:0000`; sound gated by `81ff`.

## 7. Weapons that alter flight (branch only)

| Weapon / flag | Where | Effect (summary) |
|---|---|---|
| Guided `3f15>0` | `2583:06cf` | Steer vx/vy toward target player `3f17` |
| Weapons 12..16 | `2583:0d71` | Bounce on tank colors ×1.2 |
| High power vs thresh | `2583:0d2d` / `0d6c` + `3eac` | dirt: stop at subframe 10 if power>thresh; pass only if power==thresh |

| Laser (weapon 5) | `2583:140f` (`TW_LaserTurn`) | **Outside T02 flight** — set `2583:2511` |
| Sonic / CRI / dirt balls | other overlays / post-hit | **Outside T02** |

## 8. DS globals (flight)

See `re/game/names_T02.csv` (`TW_ShotX/Y/VX/VY`, `TW_Wind`, `TW_ReboundWalls`, …).  
Wind mode: `DS:81f6` / `81f8`; span temp `3eae`.

## 9. Real ranges & fixed-point

Script: `scripts/ref/fp_compare.py` → `work/T02/fp_compare.txt` / `.json`.

From ballistics ranges (`work/T02/ranges.json`) and Gale winds ±~30k: positions need headroom past ±3000; velocities tens of units.

**Formats compared** (vs Real48 reference on all flight scenarios):

See `fp_compare` output for per-scenario `max_pixel_dev` and impact `(dx,dy)`.

**Error sources (script-measured):**

- `1/5000` is not exact in coarse fractions → wind bias per step.
- `0.01` gravity step accumulates over ≤1619 steps.
- Trig/init quantization differs when vel/pos fractions are short.

**8080 timing:** `CRT_Delay(3)` ⇒ ≥ ~333 steps/s; longest trace 1619 steps ≈ 4.9 s.  
At 3 MHz ≈ 9000 cycles/step budget; 16.16 software mul/div ~OK; 8.8 cheaper.

**Recommendation:** prefer full **16.16** (impact 30/38 after Addendum 3 scenarios). Large max path-dev comes from fuse cases where missing subframe 10 tunnels the shot — Real48 remains the accuracy reference. Avoid pos16.8+vel8.8. Numbers from `fp_compare` — see `T02-report.md` Addendum 3.

## Pseudocode

```
fire(player):
  thresh = 1000 - 2*Men
  (x,y,vx,vy) = muzzle_and_velocity(player)
  step = 10; done = 0
  # 3eac left at 1 after palette when 3edc=1
  while not done:
    3eac++; if 3eac > step: 3eac = 0
    x += vx/step; y += vy/step
    vy += 0.1/step; vx += wind/(5000*step)
    px,py = Trunc(x), Trunc(y)
    if in_band(x,y):
      for (dx,dy) in diamond:
        c = GetPixel(px+dx, py+dy)
        if hit(c):
          done = (c in 20..29) or (3eac == step) or (power < thresh)
          if c == 2 and power == thresh: done = 0
          ...
    else:
      apply_walls_or_wind_snap(...)
    if y < -5000 or y > 193: done = 1
    draw/erase/delay(3)...
  explode(hit_color, x, y, player)
```
