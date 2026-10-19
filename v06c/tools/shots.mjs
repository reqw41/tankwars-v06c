// Снимки экрана для README (docs/screenshots, 576×576): заставка, настройка, помощь, игра.
// node v06c/tools/shots.mjs [каталог]   (по умолчанию docs/screenshots; нужен собранный v06c/build/game.rom)
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import { fileURLToPath } from 'node:url';
import { parseSym } from './run.mjs';
import { createVector } from './vmachine.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const OUT = path.resolve(process.argv[2] || path.join(ROOT, 'docs/screenshots'));
const L = parseSym(path.join(ROOT, 'v06c/build/game.sym'));
const m = createVector(new Uint8Array(fs.readFileSync(path.join(ROOT, 'v06c/build/game.rom'))));
fs.mkdirSync(OUT, { recursive: true });

// кадр эмулятора 576×288, каждая строка дважды — 576×576, как экран Вектора
function shot(name) {
  const bmp = m.bmp(), W = 576, H = 576, raw = Buffer.alloc(H * (W * 3 + 1));
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    const c = bmp[(y >> 1) * W + x], o = y * (W * 3 + 1) + 1 + x * 3;
    raw[o] = c & 255; raw[o + 1] = (c >> 8) & 255; raw[o + 2] = (c >> 16) & 255;
  }
  const crcT = new Int32Array(256).map((_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c; });
  const crc = (b) => { let c = -1; for (const x of b) c = crcT[(c ^ x) & 255] ^ (c >>> 8); return (c ^ -1) >>> 0; };
  const chunk = (t, d) => { const len = Buffer.alloc(4); len.writeUInt32BE(d.length); const td = Buffer.concat([Buffer.from(t), d]); const cr = Buffer.alloc(4); cr.writeUInt32BE(crc(td)); return Buffer.concat([len, td, cr]); };
  const ih = Buffer.alloc(13); ih.writeUInt32BE(W, 0); ih.writeUInt32BE(H, 4); ih[8] = 8; ih[9] = 2;
  fs.writeFileSync(path.join(OUT, name), Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', ih), chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]));
  console.log('OK: ' + path.join(OUT, name));
}
const KEY = { left: [0, 0x10], right: [0, 0x40], down: [0, 0x80], up: [0, 0x20], fire: [7, 0x80] };
function press(name, wait = 12) {
  const [row, bit] = KEY[name], t0 = m.rd(L.kb_taken);
  m.key(row, bit, true);
  for (let f = 0; m.rd(L.kb_taken) === t0 && f < 100; f++) m.frame();
  m.key(row, bit, false); m.frame(wait);
}
m.frame(150); shot('splash.png');
m.key(7, 0x80, true);
for (let f = 0; (m.rd(0x39) | (m.rd(0x3A) << 8)) !== L.isr && f < 600; f++) m.frame();
m.key(7, 0x80, false); m.frame(60);
shot('setup.png');
press('down'); press('fire', 40); shot('help.png');
press('fire', 40); press('fire', 50);                       // назад к настройке, курсор на НАЧАТЬ — старт матча
// ход человека: ждём ввода, поднимаем силу, стреляем; снимок — в полёте и после взрыва
const PH_INPUT = 1;
for (let f = 0; m.rd(L.g_phase) !== PH_INPUT && f < 3000; f++) m.frame();
m.frame(30);
for (let i = 0; i < 6; i++) press('left', 4);
press('fire', 25); shot('game.png');
