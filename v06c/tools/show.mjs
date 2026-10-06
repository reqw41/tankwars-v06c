// Показать сборку: образ v06c/build/tw.rom исполняется в vector06js вместе с видеотрактом (развёртка, палитра),
// подпрограммы ядра вызываются по очереди через режимы стенда, кадр эмулятора сохраняется в PNG.
// node v06c/tools/show.mjs [out.png]   — картинка та, что показал бы Вектор: 576×288 вместе с бордюром.
import os from 'node:os';
import fs from 'node:fs';
import vm from 'node:vm';
import path from 'node:path';
import zlib from 'node:zlib';
import { fileURLToPath } from 'node:url';
import * as TW from '../../web/tankwars.js';
import { parseSym } from './run.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const VEC = process.env.VECTOR06JS || path.join(os.homedir(), 'projects/vector06js');
const json = (p) => JSON.parse(fs.readFileSync(path.join(ROOT, p), 'utf8'));
TW.init({ barrel: json('web/data/barrel.json'), trig: json('web/data/trig.json') });
TW.setProfile(TW.PROFILE_V06C);
const P = TW.PROFILE_V06C, L = parseSym(path.join(ROOT, 'v06c/build/tw.sym'));

const g = {}; g.window = g;
const fcx = () => ({ createImageData: () => ({ data: new Uint8ClampedArray(4) }), putImageData() {}, getImageData: () => ({ data: new Uint8ClampedArray(4) }), fillRect() {}, drawImage() {} });
const fc = () => ({ width: 0, height: 0, style: {}, getContext: () => fcx() });
g.document = { createElement: fc, getElementById: fc };
g.requestAnimationFrame = () => 0; g.setTimeout = () => 0; g.print = () => 0;
g.console = { log() {}, debug() {}, warn() {}, error() {}, info() {} };
const ctx = vm.createContext(g);
for (const f of ['i8080-js/i8080_trace.js', 'i8080-js/i8080_disasm.js', 'i8080-js/i8080.js', 'src/fili.js', 'src/ay.js', 'src/fd1793.js',
  'src/fddimage.js', 'src/i8253.js', 'src/io.js', 'src/keyboard.js', 'src/memory.js', 'src/sound.js', 'src/tv.js'])
  vm.runInContext(fs.readFileSync(path.join(VEC, f), 'utf8'), ctx, { filename: f });
const memory = new ctx.Memory(), keyboard = new ctx.Keyboard(), timer = new ctx.I8253(), ay = new ctx.AY(),
  floppy = new (ctx.Floppy().FD1793)(), io = new ctx.IO(keyboard, timer, memory, ay, floppy), cpu = new ctx.I8080(memory, io);
const v06c = new ctx.Vector06c(cpu, memory, io, ay, { advance() {}, sample: 0, reset() {} });
v06c.bmp = new Uint32Array(576 * 288); v06c.displayFrame = () => {}; v06c.check_breakpoint = () => false; v06c.dbg = null;

const rom = new Uint8Array(fs.readFileSync(path.join(ROOT, 'v06c/build/tw.rom')));
const img = new Uint8Array(0x10000); img.set(rom, 0x100);
memory.init_from_array(img, 0); memory.detach_boot && memory.detach_boot();
const wr = (a, bytes) => bytes.forEach((b, i) => { memory.bytes[memory.tobank((a + i) & 0xffff)] = b & 255; });
const PARAM = 0x80, LIST = 0x8800;
let frames = 0;
// один режим стенда: записать параметры, запустить с 0100h, крутить кадры до HLT
function mode(m, extra, list, runFrames = 0) {
  const hdr = new Uint8Array(16); hdr[0] = m; hdr.set(extra || [], 1);
  wr(PARAM, [...hdr]); if (list) wr(LIST, [...list]);
  cpu.pc = 0x100; cpu.iff = false;
  if (runFrames) { for (let f = 0; f < runFrames; f++) { v06c.oneInterrupt(true); frames++; } return; }
  for (let f = 0; f < 3000; f++) {
    v06c.oneInterrupt(true); frames++;
    if (memory.bytes[memory.tobank(cpu.pc & 0xffff)] === 0x76 || memory.bytes[memory.tobank((cpu.pc - 1) & 0xffff)] === 0x76) return;
  }
  throw new Error('режим ' + m + ' не закончился');
}
const cnt = (n) => [0, n & 255, n >> 8];
const w16 = (v) => [v & 255, (v >> 8) & 255];

// --- сцена: раунд из эталона (рельеф и расстановка — эталон; рисование — подпрограммы 8080) ---
const rng = new TW.TPRandom(31337);
const ps = ['Twanger', 'Lob & Shoot', 'Windless Wit', 'Player 4'].map((nm, i) => { const p = TW.newPlayer(i + 1, 10); p.name = nm; return p; });
const r = TW.roundStart(rng, ps, 1, 0, 2);
ps[2].men = 35; ps[1].herb = 5; ps[1].guided = 1;
mode(10, [0]);                                             // очистка экрана
mode(6, cnt(1), [r.rebound ? 1 : 0]);                      // рамка
// рельеф: вертикальные линии земли по столбцам эталона
const lines = [];
for (let x = P.X0; x <= P.X1; x++) { let top = P.Y1 + 1; for (let y = P.Y0; y <= P.Y1; y++) if (r.v[y * 256 + x] === P.ground) { top = y; break; } if (top <= P.Y1) lines.push(x, top, x, P.Y1, P.ground); }
mode(3, cnt(lines.length / 5), lines);
// взрыв и воронка, шар грязи — закрашенные круги
const dk = (x, y, rad, c, el = 1, er = 1) => [...w16(x), ...w16(y), el, er, rad, c];
mode(17, cnt(3), [...dk(150, 150, 30, 0), ...dk(60, 120, 15, 1), ...dk(205, 120, 10, 3)]);
// танки со стволами
const tanks = [];
for (const p of ps) tanks.push(p.x, p.y, p.idx, p.angle & 255, p.angle >> 8, p.facing & 255, 1, 0);
mode(11, cnt(ps.length), tanks);
// панель хода — текст шрифтом 5×7 подпрограммами ядра
{
  const p = ps[1], b = new Uint8Array(80), i16 = (v) => w16(v & 0xffff), i32 = (v) => [v & 255, (v >> 8) & 255, (v >> 16) & 255, (v >> 24) & 255];
  TW.encodeText(TW.dispName(p.name).slice(0, 16)).forEach((c, i) => { b[i] = c; });
  b[16] = p.idx; b[17] = p.facing & 255; b.set(i16(p.angle), 18); b.set(i16(p.power), 20); b.set(i16(p.men), 22); b[24] = p.weapon; b[25] = p.guided;
  b.set(i16(p.herb), 26); b.set(i16(p.vick), 28); b.set(i16(p.wins), 30); b.set(i32(p.score), 32); b.set(i32(p.spent), 36); b.set(i16(p.shield), 40); b.set(i16(p.damp), 42);
  for (let i = 0; i < 18; i++) b.set(i16(p.ammo[i] | 0), 44 + i * 2);
  mode(16, [0], [...i16(r.wind), ...b]);
}
// палитра: страница + цвета танков по здоровью (tankPalV06C) — пишется в кадровом гасящем
wr(0x38, [0xfb, 0xc9]);                                    // RST 7: EI / RET
const pal = [];
for (const f of [(p) => p.men, (p) => p.colors[0], (p) => p.colors[1], (p) => p.colors[2]]) for (const p of ps) pal.push(...w16(f(p)));
mode(18, [], pal, 6);
const out = process.argv[2] || path.join(ROOT, 'work/show.png');
// кадр эмулятора -> PNG
const Wd = 576, Ht = 288, raw = Buffer.alloc(Ht * (Wd * 3 + 1));
for (let y = 0; y < Ht; y++) for (let x = 0; x < Wd; x++) { const c = v06c.bmp[y * Wd + x], o = y * (Wd * 3 + 1) + 1 + x * 3; raw[o] = c & 255; raw[o + 1] = (c >> 8) & 255; raw[o + 2] = (c >> 16) & 255; }
const crcT = new Int32Array(256).map((_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c; });
const crc = (b) => { let c = -1; for (const x of b) c = crcT[(c ^ x) & 255] ^ (c >>> 8); return (c ^ -1) >>> 0; };
const chunk = (t, d) => { const len = Buffer.alloc(4); len.writeUInt32BE(d.length); const td = Buffer.concat([Buffer.from(t), d]); const cr = Buffer.alloc(4); cr.writeUInt32BE(crc(td)); return Buffer.concat([len, td, cr]); };
const ih = Buffer.alloc(13); ih.writeUInt32BE(Wd, 0); ih.writeUInt32BE(Ht, 4); ih[8] = 8; ih[9] = 2;
fs.writeFileSync(out, Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', ih), chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]));
console.log('кадров эмулятора', frames, '→', out);
