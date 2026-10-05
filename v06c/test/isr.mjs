// Прерывание кадра (v06c/build/game.rom): на какой строке после прерывания кадра игра переводит порт B ВВ55 на ввод (OUT 00h = 8Ah) и возвращает (88h),
// и где кончается запись палитры. Гашение кадра в ядре MiSTer длится 24,9 строки после прерывания (vc 271..295).
import fs from 'node:fs';
import { parseSym } from '../tools/run.mjs';
import { createVector } from '../tools/vmachine.mjs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const BUILD = path.join(ROOT, process.env.BUILD || 'v06c/build');
const L = parseSym(BUILD + '/game.sym');
const m = createVector(new Uint8Array(fs.readFileSync(BUILD + '/game.rom')));
const io = m.io, orig = io.output.bind(io);
let on = false, st = { kbFrames: 0, kbMax: 0, kbLate: 0, palFrames: 0, palMax: 0 }, cur = null;
const pos = () => { const fl = m.v06c.filler; return fl.raster_line + fl.raster_pixel / 768; };
io.output = function (port, val) {
  if (on) {
    if (port === 0 && val === 0x8A) cur = pos();
    if (port === 0 && val === 0x88 && cur !== null) { const e = pos(); st.kbFrames++; st.kbMax = Math.max(st.kbMax, e); if (e > 24.9) st.kbLate++; cur = null; }
    if (port === 0x0c) { st.palWrites = (st.palWrites || 0) + 1; st.palMax = Math.max(st.palMax, pos()); }
  }
  return orig(port, val);
};
const tap = (row, bit, n = 6) => { m.key(row, bit, true); m.frame(n); m.key(row, bit, false); m.frame(n); };
m.frame(100); tap(7, 0x80); for (let f = 0; (m.rd(0x39) | (m.rd(0x3A) << 8)) !== L.isr; f++) m.frame();
m.frame(60); on = true; m.wr(L.g_types, [0, 3, 2, 3]); m.wr(L.g_rounds, [2]); tap(7, 0x80);
for (let f = 0; f < 6000; f++) { m.frame(); const ph = m.rd(L.g_phase); if (ph === 1 && f % 40 === 0) tap(7, 0x80); else if ((ph === 3 || ph === 0) && f % 50 === 0) tap(7, 0x80); else if (ph === 5 && f % 30 === 0) { tap(0, 0x20); tap(7, 0x80); } }
const bad = st.kbLate > 0 || st.palMax > 24.9 || !st.kbFrames || !st.palWrites;
console.log(`${bad ? 'FAIL' : 'OK '} прерывание кадра: опросов клавиатуры ${st.kbFrames}: самый поздний конец — строка ${st.kbMax.toFixed(1)} после прерывания; за гашением кадра (позже 24,9): ${st.kbLate}; запись палитры: ${st.palWrites / 32} раз, конец не позже строки ${st.palMax.toFixed(1)}`);
if (bad) process.exit(1);
