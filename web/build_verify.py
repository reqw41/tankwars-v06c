#!/usr/bin/env python3
"""Собирает web/data/verify.json — подборку эталонов настоящей игры для вкладки «Сверка».
Картинки — zlib (deflate) в base64, браузер распаковывает DecompressionStream('deflate')."""
import base64, json
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
FX = ROOT / 'tests' / 'fixtures'
b64 = lambda p: base64.b64encode(p.read_bytes()).decode()
out = {'placement': [], 'explosion': [], 'crumble': [], 'laser': [], 'cri': []}
for c in json.loads((FX / 't03/placement/index.json').read_text()):
    d = FX / 't03/placement'
    out['placement'].append({**c, 'bg': b64(d / f"{c['name']}.bg.z"), 'orig': b64(d / f"{c['name']}.vram.z")})
def ev(kind, dirpath, pick, extra=lambda c: {}):
    d = FX / dirpath
    for c in json.loads((d / 'index.json').read_text()):
        if not pick(c):
            continue
        out[kind].append({**{k: v for k, v in c.items()}, **extra(c),
                          'pre_img': b64(d / f"{c['name']}.pre.z"), 'bg': b64(d / f"{c['name']}.bg.z"),
                          'post_img': b64(d / f"{c['name']}.post.z")})
ev('explosion', 't03/explosion', lambda c: c['name'] in ('e00', 'e03', 'e06', 'e08', 'e13'))
ev('explosion', 't03/explosion_direct', lambda c: c['name'] in ('e01', 'e03', 'e08'), lambda c: {'name': 'd' + c['name'][1:]})
ev('crumble', 't03/crumble', lambda c: c['vram_changed'] > 50)
ev('laser', 't04/laser2', lambda c: c['ndiff'] > 0)
ev('cri', 't04/cri', lambda c: c['name'].endswith('_ground') or c['name'] == 'w10_direct')
(ROOT / 'web/data/verify.json').write_text(json.dumps(out))
print({k: len(v) for k, v in out.items()}, (ROOT / 'web/data/verify.json').stat().st_size // 1024, 'KB')
