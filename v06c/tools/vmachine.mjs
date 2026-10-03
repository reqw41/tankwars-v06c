// Вектор целиком (процессор, видеотракт, кадровое прерывание, клавиатура) под node — для игрового образа.
import fs from 'node:fs';
import vm from 'node:vm';
import path from 'node:path';

const VEC = process.env.VECTOR06JS || '~/projects/vector06js';
export function createVector(romPath) {
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
  const rom = new Uint8Array(fs.readFileSync(romPath));
  const img = new Uint8Array(0x10000); img.set(rom, 0x100);
  memory.init_from_array(img, 0); memory.detach_boot && memory.detach_boot();
  cpu.pc = 0x100; cpu.sp = 0xA000; cpu.iff = false;
  const m = {
    cpu, memory, keyboard, v06c, frames: 0,
    rd: (a) => memory.bytes[memory.tobank(a & 0xffff)],
    wr: (a, bytes) => bytes.forEach((b, i) => { memory.bytes[memory.tobank((a + i) & 0xffff)] = b & 255; }),
    frame(n = 1) { for (let i = 0; i < n; i++) { v06c.oneInterrupt(true); m.frames++; } },
    key(row, bit, down) { if (down) keyboard.matrix[row] |= bit; else keyboard.matrix[row] &= ~bit; },
    mem() { const out = new Uint8Array(0x10000); for (let a = 0; a < 0x10000; a++) out[a] = m.rd(a); return out; },
    bmp: () => v06c.bmp,
  };
  return m;
}
// кадр эмулятора 576×288 -> PNG
import zlib from 'node:zlib';
export function savePng(bmp, out) {
  const Wd = 576, Ht = 288, raw = Buffer.alloc(Ht * (Wd * 3 + 1));
  for (let y = 0; y < Ht; y++) for (let x = 0; x < Wd; x++) { const c = bmp[y * Wd + x], o = y * (Wd * 3 + 1) + 1 + x * 3; raw[o] = c & 255; raw[o + 1] = (c >> 8) & 255; raw[o + 2] = (c >> 16) & 255; }
  const crcT = new Int32Array(256).map((_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c; });
  const crc = (b) => { let c = -1; for (const x of b) c = crcT[(c ^ x) & 255] ^ (c >>> 8); return (c ^ -1) >>> 0; };
  const chunk = (t, d) => { const len = Buffer.alloc(4); len.writeUInt32BE(d.length); const td = Buffer.concat([Buffer.from(t), d]); const cr = Buffer.alloc(4); cr.writeUInt32BE(crc(td)); return Buffer.concat([len, td, cr]); };
  const ih = Buffer.alloc(13); ih.writeUInt32BE(Wd, 0); ih.writeUInt32BE(Ht, 4); ih[8] = 8; ih[9] = 2;
  fs.writeFileSync(out, Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', ih), chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]));
}
