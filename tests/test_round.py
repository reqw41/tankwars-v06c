"""T05: ход целиком (scripts/ref/game.py turn) и начало раунда (round_start) против настоящей игры.

turns_ai2/, turns_ai6/ — по 40 ходов (ИИ Lobber / Twanger), от решения игрока (2583:2976) до конца обработки смертей
(2583:2cee): поле экрана (x 8..312, y 28..192), буфер фона, записи игроков, RandSeed.
rstart/ — 10 начал раунда (2eef:0909 -> 2583:2783): фон 0..6, стены 0/1/2, ветер 0..5.
"""
import json, os, sys, zlib
from pathlib import Path
import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT / 'scripts' / 'ref'), str(ROOT / 'scripts' / 't03'), str(ROOT / 'scripts')]
import check_turns  # noqa: E402
from game import P, round_start  # noqa: E402
from tprandom import TPRandom  # noqa: E402

FX = ROOT / 'tests/fixtures/t05'
TURNS = [(d, c) for d in ('turns_ai2', 'turns_ai6') for c in json.loads((FX / d / 'index.json').read_text())]


@pytest.mark.parametrize('d,c', TURNS, ids=[f"{d}-{c['name']}" for d, c in TURNS])
def test_turn_matches_original(d, c):
    check_turns.D = FX / d
    err, pl, sd, bad, ps, want = check_turns.run(c)
    assert err is None, err
    assert pl and sd
    assert not bad, f'{len(bad)} px, {bad[:3]}'


RS = json.loads((FX / 'rstart/index.json').read_text())


@pytest.mark.parametrize('c', RS, ids=[c['name'] for c in RS])
def test_round_start_matches_original(c):
    ps = [P.from_rec(i + 1, bytes.fromhex(h)) for i, h in enumerate(c['pre']['players'])]
    cfg = c['pre']['cfg']
    rng = TPRandom(c['pre']['seed'])
    v, bg, reb, wind, first = round_start(rng, ps, cfg['walls_cfg'], cfg['bg_cfg'], cfg['wind_mode'])
    post = zlib.decompress((FX / 'rstart' / f"{c['name']}.post.z").read_bytes())
    bgo = zlib.decompress((FX / 'rstart' / f"{c['name']}.bg.z").read_bytes())
    assert bytes(bg) == bgo
    assert all(post[k] == v[k] for k in range(64000) if 28 <= k // 320 <= 192 and 8 <= k % 320 <= 312)
    want = [P.from_rec(i + 1, bytes.fromhex(h)) for i, h in enumerate(c['post']['players'])]
    key = lambda p: (p.x, p.y, p.angle, p.power, p.facing, p.men, p.alive)  # noqa: E731
    assert [key(p) for p in ps] == [key(p) for p in want]
    assert (rng.seed, wind, int(reb), first) == (c['post']['seed'], c['post']['wind'], c['post']['rebound'], c['post']['first_raw'])


def test_round_start_covers_all_backgrounds_walls_winds():
    assert {c['pre']['cfg']['bg_cfg'] for c in RS} == set(range(7))
    assert {c['pre']['cfg']['walls_cfg'] for c in RS} == {0, 1, 2}
    assert {c['pre']['cfg']['wind_mode'] for c in RS} == set(range(6))
