// Дымовой тест страницы без браузера: скрипт index.html исполняется на заглушке DOM, матч компьютеров играется до конца.
import { readFileSync, writeFileSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
const WEB = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const html = readFileSync(path.join(WEB, 'index.html'), 'utf8');
let src = html.slice(html.indexOf('<script type="module">') + 22, html.lastIndexOf('</script>'));
src = src.replace("'./tankwars.js'", JSON.stringify(pathToFileURL(path.join(WEB, 'tankwars.js')).href));
const els = new Map(), created = [];
const defaults = { profile: process.env.TW_PROFILE || 'v06c', seed: '487264648', nplayers: '4', rounds: '3', windmode: '2', walls: '1', bgkind: '6', crumble: '50', speed: '40' };
const mkEl = (id) => {
  const el = { id, value: defaults[id] ?? '', checked: true, hidden: false, disabled: false, textContent: '', style: {}, dataset: {}, children: [], _html: '', options: [], selectedOptions: [], width: 0, height: 0,
    getContext: () => new Proxy({}, { get: (t, k) => (k === 'createImageData' ? () => ({ data: new Uint8ClampedArray(256000) }) : () => {}), set: () => true }),
    setAttribute() {}, removeAttribute() {}, prepend(c) { this.children.unshift(c); }, append() {}, remove() {}, matches: () => false,
    querySelector: (q) => (q === '.case' ? created.find((e) => e.className === 'case') : mkEl('q')), querySelectorAll: () => [], click() { return this.onclick && this.onclick(); },
    get lastChild() { return { remove: () => this.children.pop() }; },
    set innerHTML(v) { this._html = v; if (id === 'log') this.children = []; }, get innerHTML() { return this._html; } };
  return el;
};
const kinds = (process.argv[2] || 'Lobber,Rifleman,Twanger,Windless Wit').split(',');
globalThis.document = { getElementById: (id) => { if (!els.has(id)) els.set(id, mkEl(id)); return els.get(id); }, createElement: () => { const e = mkEl('new'); created.push(e); return e; },
  addEventListener() {}, querySelectorAll: (q) => (q === '#plist select' ? kinds.map((value) => ({ value })) : q === '.case' ? created.filter((e) => e.className === 'case') : []) };
globalThis.requestAnimationFrame = (f) => setImmediate(f);
globalThis.matchMedia = () => ({ matches: true });
globalThis.location = { hash: '' };
globalThis.localStorage = { setItem() {}, getItem() { return null; } };
globalThis.fetch = async (u) => ({ json: async () => JSON.parse(readFileSync(path.join(WEB, u), 'utf8')) });
const dir = mkdtempSync(path.join(tmpdir(), 'tw-')); const f = path.join(dir, 'page.mjs'); writeFileSync(f, src);
await import(pathToFileURL(f).href);
document.getElementById('nplayers').value = String(kinds.length);
document.getElementById('b-new').onclick();
const t0 = Date.now();
const E = (id) => document.getElementById(id);
let shots = 0;
while (!/Итог матча/.test(E('sheet').innerHTML)) {
  await new Promise((r) => setTimeout(r, 5));
  // «человек»: пара нажатий и огонь; на листах результатов и магазина — «дальше»/«готово»
  if (!E('b-fire').disabled && E('turn').textContent.startsWith('Игрок')) { E('b-al').onclick(); E('b-pu').onclick(); E('b-p100').onclick(); E('b-fire').onclick(); shots++; }
  for (const id of ['b-next', 'b-done']) { const b = E(id); if (b.onclick && new RegExp(`id="${id}"`).test(E('sheet').innerHTML)) { const f = b.onclick; b.onclick = null; f(); } } if (Date.now() - t0 > 120000) { console.log('ТАЙМАУТ'); process.exit(1); } }
const log = document.getElementById('log').children.map((c) => c.textContent);
console.log('матч сыгран за', Date.now() - t0, 'мс; выстрелов человека', shots, ';', log.filter((l) => /^Раунд \d+ (за|:)/.test(l)).reverse().join(' | '));
console.log(document.getElementById('sheet').innerHTML.replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').slice(0, 400));

// вкладка «Сверка»: все события подборки должны совпасть
if (process.argv[3] === 'verify') {
  E('tab-verify').onclick();
  const t1 = Date.now();
  while (!created.some((e) => e.className === 'case')) { await new Promise((r) => setTimeout(r, 20)); if (Date.now() - t1 > 20000) { console.log('сверка не загрузилась'); process.exit(1); } }
  await E('b-vall').onclick();
  console.log('сверка:', E('vsum').innerHTML.replace(/<[^>]+>/g, ''));
  if (!/Проверено (\d+) из \1: совпало \1/.test(E('vsum').innerHTML.replace(/<[^>]+>/g, ''))) process.exit(1);
}
