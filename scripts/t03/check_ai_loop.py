"""Проверка цикла кодов ИИ с планом из эталона (hist1 — структура после первого вызова, план уже готов)."""
import sys, json, zlib, glob
from pathlib import Path
sys.path[:0] = ['scripts/ref', 'scripts']
from game import P
from ai import Hist, computer_turn

tot = ok = 0
for d in sorted(x for x in glob.glob('work/T05/ai_*') if Path(x).is_dir()):
    for c in json.loads((Path(d) / 'index.json').read_text()):
        tot += 1
        p = P.from_rec(c['player'], bytes.fromhex(c['recs'][c['player']])[0x0E:] + bytes(0x0E))
        h1 = Hist(bytes.fromhex(c['hist1']))
        v = bytearray(zlib.decompress((Path(d) / f"{c['name']}.v1.z").read_bytes()))
        bg = zlib.decompress((Path(d) / f"{c['name']}.bg.z").read_bytes())
        # первый вызов уже сделан в оригинале: применить его код и продолжать с планом h1
        first = c['codes'][0]
        from ai import apply_code
        # мощность могла измениться внутри первого вызова (шаги 90/9): берём запись после первого вызова нельзя — нет;
        # поэтому моделируем первый вызов кодом choose_code с планом h1 и проверяем совпадение кода
        h = Hist(bytes(h1.b)); h.planned = 1
        codes = computer_turn(v, bg, p, h, lambda hh: None)
        end = P.from_rec(c['player'], bytes.fromhex(c['rec_end'])[0x0E:] + bytes(0x0E))
        good = codes == c['codes'] and (p.angle, p.power, p.facing, p.weapon) == (end.angle, end.power, end.facing, end.weapon)
        ok += good
        if not good:
            print(d, c['name'], 'коды', codes[:10], c['codes'][:10], len(codes), len(c['codes']), (p.angle, p.power, p.facing, p.weapon), (end.angle, end.power, end.facing, end.weapon))
print('match', ok, '/', tot)
