"""T03: генерация рельефа — модель scripts/ref/terrain.py против оригинала (2eef:0a5a..0dbc).

Эталоны сняты полным запуском игры (scripts/probe/terrain_probe.py) и лежат в tests/fixtures/t03/terrain_orig.json:
сид RandSeed на входе генератора, число игроков, итоговая высота и SHA1 маски «пиксель == 2» на всём экране.
"""
import hashlib, json, os, struct, sys
from pathlib import Path
import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts' / 'ref'))
from tprandom import TPRandom  # noqa: E402
from terrain import generate, render  # noqa: E402

FX = json.loads((ROOT / 'tests' / 'fixtures' / 't03' / 'terrain_orig.json').read_text())


@pytest.mark.parametrize('case', FX, ids=lambda c: f"seed{c['seed']:08x}_p{c['players']}")
def test_terrain_matches_original(case):
    res = generate(TPRandom(case['seed']), case['players'])
    v = render(res)
    # в оригинале перед рельефом цвет 2 на экране не встречается (проверено в пробе), сравниваем маску целиком
    mask = bytes(1 if b == 2 else 0 for b in v)
    assert hashlib.sha1(mask).hexdigest() == case['dirt_mask_sha1']
    assert res.h_final == case['h_final']
    tops = [min((y for y in range(30, 191) if v[y * 320 + x] == 2), default=None) for x in range(320)]
    assert tops == case['top_by_x']


def test_fixture_covers_players_2_to_6():
    assert {c['players'] for c in FX} == {2, 3, 4, 5, 6}
    assert len(FX) >= 10


def test_tprandom_matches_rtl():
    sys.path.insert(0, str(ROOT / 'scripts'))
    from emu16 import Emu16, DS_SEG, call_far, result_real
    for seed in (1, 0x12345678, 0xFFFFFFFF):
        e = Emu16(); e.write_bytes(DS_SEG, 0x3774, struct.pack('<I', seed)); r = TPRandom(seed)
        for n in (2, 150, 7):
            assert call_far(e, 0x1C5B, 0x15EA, stack_args=[n])['ax'] == r.word(n)
        assert result_real(call_far(e, 0x1C5B, 0x1600)) == r.real()


@pytest.mark.skipif(not os.environ.get('T03_LIVE'), reason='живой прогон оригинала ~15 с; T03_LIVE=1')
def test_terrain_live_original():
    sys.path.insert(0, str(ROOT / 'scripts' / 'probe'))
    from terrain_probe import probe
    p = probe((0x1111, 0x2222), players=3)
    res = generate(TPRandom(p['seed']), p['players'])
    v = render(res)
    a = p['after']
    assert all((a[i] == 2) == (v[i] == 2) for i in range(64000) if 10 <= i % 320 <= 310 and 30 <= i // 320 <= 190)
