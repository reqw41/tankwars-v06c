// Загрузчик (v06c/build/game.rom): заставка на экране = title.bin, палитра = title_pal.inc, после клавиши игра
// распакована на 0100h байт в байт = game.bin. node v06c/test/loader.mjs [заставка.png]
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseSym } from '../tools/run.mjs';
import { createVector, savePng } from '../tools/vmachine.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const BUILD = process.env.BUILD || 'v06c/build';
const rd = (f) => new Uint8Array(fs.readFileSync(path.join(ROOT, BUILD, f)));
const L = parseSym(path.join(ROOT, BUILD, 'loader.sym'));
const rom = rd('game.rom'), game = rd('game.bin'), title = rd('title.bin');
function fail(msg) { console.error('FAIL ' + msg); process.exit(1); }
// последняя команда второй ступени — JP 0100h; для проверки заменяется на «стоять на месте»
const jpAt = L.s2_entry + 12, jpFile = L.ld_end - (0x10000 - jpAt) - 0x100;
if (rom[jpFile] !== 0xC3 || rom[jpFile + 1] !== 0x00 || rom[jpFile + 2] !== 0x01) fail('вторая ступень: JP 0100h не на своём месте');
const stop = new Uint8Array(rom); stop[jpFile + 1] = jpAt & 255; stop[jpFile + 2] = jpAt >> 8;
const m = createVector(stop);
const waiting = (pc) => pc >= L.ld_keys && pc < L['lo.dzx0'];      // загрузчик опрашивает клавиатуру
let f = 0; for (; f < 600; f++) { m.frame(); const pc = m.cpu.pc & 0xffff; if (waiting(pc)) break; }
if (f >= 600) fail('заставка не появилась за 12 с');
m.frame(3);
const shown = f;
const mem = m.mem();
for (let a = 0; a < 0x8000; a++) if (mem[0x8000 + a] !== title[a]) fail(`заставка: байт экрана ${(0x8000 + a).toString(16)} = ${mem[0x8000 + a]}, нужно ${title[a]}`);
if (process.argv[2]) savePng(m.bmp(), process.argv[2]);
// палитра эмулятора: 16 разных регистров, как в title_pal.inc
const pal = [...fs.readFileSync(path.join(ROOT, 'v06c/src/title_pal.inc'), 'utf8').matchAll(/0x([0-9A-F]{2})/gi)].map((x) => parseInt(x[1], 16));
const io = m.v06c.io || m.v06c.IO || m.io, got = io && io.Palette;
let palNote = 'палитра в эмуляторе не найдена — не сверена';
if (got) { const mine = Array.from(got).slice(0, 16).map((v) => ((v >> 22) & 3) << 6 | ((v >> 13) & 7) << 3 | ((v >> 5) & 7));
  if (mine.join() !== pal.join()) fail(`палитра: ${mine.map((v) => v.toString(16))} нужно ${pal.map((v) => v.toString(16))}`); palNote = 'палитра совпала'; }
m.frame(20);
if (!waiting(m.cpu.pc & 0xffff)) fail('загрузчик ушёл с заставки без клавиши');
m.key(7, 0x80, true);
for (f = 0; (m.cpu.pc & 0xffff) !== jpAt; f++) { if (f > 600) fail(`игра не распаковалась за 12 с (PC=${(m.cpu.pc & 0xffff).toString(16)})`); m.frame(); }
m.key(7, 0x80, false);
const mem2 = m.mem();
for (let a = 0; a < game.length; a++) if (mem2[0x100 + a] !== game[a]) fail(`игра: байт ${(0x100 + a).toString(16)} = ${mem2[0x100 + a]}, нужно ${game[a]}`);
console.log(`OK  загрузчик: заставка на экране через ${(shown / 50).toFixed(1)} с (${palNote}), игра распакована за ${(f / 50).toFixed(1)} с — ${game.length} Б совпали; файл ${rom.length} Б`);
