// Джойстик «П» (ВВ55 №2, порт 06h): закрывает заставку, двигает курсор и меняет настройки, огонь 2 — оружие.
// Порт 06h подменяется: в покое JOY_IDLE (по умолчанию FFh, как отпущенный джойстик; любое постоянное
// значение — тоже покой), нажатие — инверсия бита (0 вправо, 1 влево, 2 вверх, 3 вниз, 6 огонь 1, 7 огонь 2).
// Клавиатура не трогается ни разу. JOY_INJECT=1 — джойстик молчит: проверка обязана провалиться.
// node v06c/test/joy.mjs
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseSym } from '../tools/run.mjs';
import { createVector } from '../tools/vmachine.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const BUILD = process.env.BUILD || 'v06c/build';
const L = parseSym(path.join(ROOT, BUILD, 'game.sym'));
const IDLE = parseInt(process.env.JOY_IDLE || '0xFF');
const INJECT = process.env.JOY_INJECT === '1';
const m = createVector(new Uint8Array(fs.readFileSync(path.join(ROOT, BUILD, 'game.rom'))));
let held = 0;
const realIn = m.io.input.bind(m.io);
m.io.input = (port) => ((port & 0xff) === 0x06 ? (IDLE ^ (INJECT ? 0 : held)) & 0xff : realIn(port));
const J = { right: 0x01, left: 0x02, up: 0x04, down: 0x08, fire: 0x40, fire2: 0x80 };
function fail(msg) { console.error('FAIL ' + msg); process.exit(1); }
m.frame(100); held = J.fire;
for (let f = 0; (m.rd(0x39) | (m.rd(0x3A) << 8)) !== L.isr; f++) { if (f > 600) fail('огонь джойстика не закрыл заставку'); m.frame(); }
held = 0; m.frame(60);
let steps = 0;
function press(name) {
  const t0 = m.rd(L.kb_taken);
  held = J[name];
  for (let f = 0; m.rd(L.kb_taken) === t0; f++) { if (f > 100) fail(`нажатие ${name} не принято`); m.frame(); }
  held = 0; m.frame(12); steps++;
}
const st = () => ({ cur: m.rd(L.st_cur), n: m.rd(L.g_n) });
function expect(tag, want) { const s = st(); for (const [k, v] of Object.entries(want)) if (String(s[k]) !== String(v)) fail(`${tag}: ${k} = ${s[k]}, нужно ${v} (${JSON.stringify(s)})`); }
expect('начало', { cur: 11, n: 2 });
press('down'); expect('вниз — ПОМОЩЬ', { cur: 12 });
press('up'); press('up'); expect('вверх', { cur: 10 });
for (let i = 0; i < 8; i++) press('up');      // 10→9…5→2→1→0: игроки 3 и 4 скрыты
expect('вверх до ИГРОКОВ', { cur: 0 });
press('right'); expect('вправо — игроков 3', { n: 3 });
press('left'); expect('влево — игроков 2', { n: 2 });
// огонь 2 даёт код «оружие» (8): на экране настройки он ничего не меняет, но нажатие обязано быть принято
press('fire2');
// старт матча огнём 1 с пункта НАЧАТЬ
for (let i = 0; i < 9; i++) press('down');
expect('НАЧАТЬ', { cur: 11 });
press('fire'); m.frame(50);
if (m.rd(L.g_phase) === 0) fail('огонь 1 на НАЧАТЬ не запустил матч');
console.log(`OK  джойстик «П» (покой ${IDLE.toString(16)}h): заставка, ${steps} нажатий, старт матча`);
