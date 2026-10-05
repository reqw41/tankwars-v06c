// Экран настройки матча (v06c/build/game.rom): клавиши двигают курсор и меняют настройки в памяти игры.
// node v06c/test/setup.mjs [снимок.png]
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseSym } from '../tools/run.mjs';
import { createVector, savePng } from '../tools/vmachine.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const BUILD = process.env.BUILD || 'v06c/build';
const L = parseSym(path.join(ROOT, BUILD, 'game.sym'));
const m = createVector(new Uint8Array(fs.readFileSync(path.join(ROOT, BUILD, 'game.rom'))));
const KEY = { left: [0, 0x10], right: [0, 0x40], down: [0, 0x80], up: [0, 0x20] };
function fail(msg) { console.error('FAIL ' + msg); process.exit(1); }
m.frame(100); m.key(7, 0x80, true);
for (let f = 0; (m.rd(0x39) | (m.rd(0x3A) << 8)) !== L.isr; f++) { if (f > 600) fail('игра не запустилась после заставки'); m.frame(); }
m.key(7, 0x80, false); m.frame(60);
let steps = 0;
function press(name) {
  const [row, bit] = KEY[name], t0 = m.rd(L.kb_taken);
  m.key(row, bit, true);
  for (let f = 0; m.rd(L.kb_taken) === t0; f++) { if (f > 100) fail(`нажатие ${name} не принято`); m.frame(); }
  m.key(row, bit, false); m.frame(12); steps++;
}
const st = () => ({ cur: m.rd(L.st_cur), n: m.rd(L.g_n), types: [0, 1, 2, 3].map((i) => m.rd(L.g_types + i)).join(''), rounds: m.rd(L.g_rounds), walls: m.rd(L.g_walls),
  wind: m.rd(L.g_windmode), crumble: m.rd(L.g_crumble), fall: m.rd(L.g_fall), xkill: m.rd(L.g_xkill) });
function expect(tag, want) { const s = st(); for (const [k, v] of Object.entries(want)) if (String(s[k]) !== String(v)) fail(`${tag}: ${k} = ${s[k]}, нужно ${v} (${JSON.stringify(s)})`); }
expect('начало', { cur: 11, n: 2, types: '0623', rounds: 10, walls: 1, wind: 2, crumble: 50, fall: 1, xkill: 1 });
press('down'); expect('вниз с НАЧАТЬ — по кругу', { cur: 0 });
press('right'); press('right'); expect('игроков 4', { n: 4 });
press('right'); expect('игроков по кругу', { n: 2 });
press('left'); expect('игроков назад по кругу', { n: 4 }); press('right');
press('down'); press('right'); expect('тип игрока 1', { cur: 1, types: '1623' });
press('left'); press('left'); expect('тип игрока по кругу', { types: '7623' }); press('right');
press('down'); press('down'); expect('игроки 3 и 4 скрыты', { cur: 5 });
press('left'); expect('раундов 9', { rounds: 9 });
press('down'); press('right'); expect('отскок: да', { cur: 6, walls: 2 }); press('right'); expect('отскок по кругу', { walls: 0 });
press('down'); press('left'); expect('ветер слабый', { cur: 7, wind: 1 }); press('left'); press('left'); expect('ветер по кругу', { wind: 5 });
press('down'); press('right'); expect('осыпание 60', { cur: 8, crumble: 60 });
for (let i = 0; i < 5; i++) press('right'); expect('осыпание по кругу', { crumble: 0 }); press('left'); expect('осыпание 100', { crumble: 100 });
press('down'); press('right'); expect('падение: нет', { cur: 9, fall: 0 });
press('down'); press('left'); expect('обломки: нет', { cur: 10, xkill: 0 });
if (process.argv[2]) savePng(m.bmp(), process.argv[2]);
press('down'); expect('НАЧАТЬ', { cur: 11 }); press('up'); press('up'); expect('вверх', { cur: 9 });
press('up'); press('up'); press('up'); press('up'); press('up'); expect('вверх мимо скрытых игроков', { cur: 2 });
console.log(`OK  экран настройки: ${steps} нажатий — курсор и все настройки меняются как задумано`);
