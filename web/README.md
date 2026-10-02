# Tank Wars 2.5 — эталон на JS

- `tankwars.js` — перенос моделей `scripts/ref/*.py` (ГСЧ TP6, Real48, рельеф, танки, полёт, ветер, взрыв, CRI, грязь,
  Explosive Dirt, Sonic, лазер, осыпание, падение). Тригонометрия и ствол — таблицы RTL из `data/`.
- `node web/test/run_fixtures.mjs` — сверка со всеми эталонами настоящей игры из `tests/fixtures` (423/423).
- `index.html` — игра вдвоём на одном экране + вкладка «Сверка» (данные `data/verify.json`, сборка `build_verify.py`).
  Локально: `python3 -m http.server -d web` и открыть http://localhost:8000.
- Не разобрано: ИИ, магазин, гибель танков (анимации), варианты фона кроме 6, звук.
