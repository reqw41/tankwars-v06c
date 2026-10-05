// Headless vector06js: загрузить ROM с 0100h, исполнить до HLT или метки, выгрузить память и регистры.
// Никаких окон. Эмулятор: ~/projects/vector06js (или VECTOR06JS).
import fs from 'node:fs';
import vm from 'node:vm';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const VEC = process.env.VECTOR06JS || '~/projects/vector06js';

export function parseSym(symPath) {
  const L = {};
  if (!fs.existsSync(symPath)) return L;
  for (const line of fs.readFileSync(symPath, 'latin1').split('\n')) {
    const m = line.match(/^([A-Za-z_][\w.]*):\s+EQU\s+0x([0-9A-Fa-f]+)\s*$/i);
    if (m) L[m[1]] = parseInt(m[2], 16);
  }
  return L;
}

function stubWindow() {
  const g = {};
  g.window = g;
  function fcx() {
    return {
      createImageData: () => ({ data: new Uint8ClampedArray(4) }),
      putImageData() {}, getImageData: () => ({ data: new Uint8ClampedArray(4) }),
      fillRect() {}, drawImage() {},
    };
  }
  function fc() { return { width: 0, height: 0, style: {}, getContext: () => fcx() }; }
  g.document = { createElement: () => fc(), getElementById: () => fc() };
  g.requestAnimationFrame = () => 0;
  g.setTimeout = () => 0;
  g.print = () => 0;
  g.console = { log() {}, debug() {}, warn() {}, error() {}, info() {} };
  return g;
}

let cachedCtx = null;
function emuContext() {
  if (cachedCtx) return cachedCtx;
  const g = stubWindow();
  const ctx = vm.createContext(g);
  for (const f of [
    'i8080-js/i8080_trace.js', 'i8080-js/i8080_disasm.js', 'i8080-js/i8080.js',
    'src/fili.js', 'src/ay.js', 'src/fd1793.js', 'src/fddimage.js', 'src/i8253.js',
    'src/io.js', 'src/keyboard.js', 'src/memory.js', 'src/sound.js', 'src/tv.js',
  ]) {
    vm.runInContext(fs.readFileSync(path.join(VEC, f), 'utf8'), ctx, { filename: f });
  }
  cachedCtx = ctx;
  return ctx;
}

export function createMachine() {
  const ctx = emuContext();
  const memory = new ctx.Memory();
  const keyboard = new ctx.Keyboard();
  const timer = new ctx.I8253();
  const ay = new ctx.AY();
  const floppy = new (ctx.Floppy().FD1793)();
  const io = new ctx.IO(keyboard, timer, memory, ay, floppy);
  const cpu = new ctx.I8080(memory, io);
  cpu.iff = false;
  return { ctx, memory, io, cpu, timer };
}

export function loadRom(machine, romBuf) {
  const img = new Uint8Array(0x10000);
  const n = Math.min(romBuf.length, 0x10000 - 0x100);
  img.set(romBuf.subarray(0, n), 0x100);
  machine.memory.init_from_array(img, 0);
  if (machine.memory.detach_boot) machine.memory.detach_boot();
  machine.cpu.pc = 0x100;
  machine.cpu.sp = 0x9F00;
  machine.cpu.iff = false;
}

export function poke(machine, addr, bytes) {
  // буфер LIST стенда (8800h) не должен доставать до RESULT (9600h)
  if (addr >= 0x8800 && addr < 0x9600 && addr + bytes.length > 0x9600) throw new Error(`poke: ${bytes.length} байт с ${addr.toString(16)} достают до RESULT`);
  for (let i = 0; i < bytes.length; i++) machine.memory.write((addr + i) & 0xffff, bytes[i] & 0xff, false);
}

export function peek(machine, addr) {
  return machine.memory.read(addr & 0xffff, false) & 0xff;
}

export function dumpMem(machine) {
  const mem = new Uint8Array(0x10000);
  for (let a = 0; a < 0x10000; a++) mem[a] = machine.memory.read(a, false) & 0xff;
  return mem;
}

export function regs(machine) {
  const c = machine.cpu;
  return {
    pc: c.pc & 0xffff, sp: c.sp & 0xffff,
    a: c.regs[7], b: c.regs[0], c: c.regs[1], d: c.regs[2], e: c.regs[3], h: c.regs[4], l: c.regs[5],
    iff: !!c.iff,
  };
}

/** Исполнять до HLT, PC===haltPc, или maxInsns. Возврат: cpu_cycles и vcycles (Вектор). */
export function runUntil(machine, { haltPc = null, maxInsns = 20_000_000, countFromPc = null, prof = null } = {}) {
  const cpu = machine.cpu;
  const timer = machine.timer;
  let insns = 0, cpuCycles = 0, vcycles = 0, tacc = 0, counting = countFromPc == null;
  let bodyCpu = 0, bodyV = 0;
  while (insns < maxInsns) {
    if (haltPc != null && (cpu.pc & 0xffff) === haltPc) break;
    if (countFromPc != null && (cpu.pc & 0xffff) === countFromPc) counting = true;
    const opAt = cpu.pc & 0xffff;
    cpu.instruction();
    const cc = cpu.cpu_cycles | 0;
    const vc = cpu.vcycles | 0;
    cpuCycles += cc;
    vcycles += vc;
    if (counting) { bodyCpu += cc; bodyV += vc; }
    if (prof) prof[opAt] += vc;                        // профиль: такты по адресам команд
    tacc += vc;
    if (tacc > 1) { const tn = tacc >> 1; tacc -= tn * 2; timer.Count(tn); }
    if (cpu.last_opcode === 0xd3) machine.io.commit();
    insns++;
    if (cpu.last_opcode === 0x76) break; // HLT: PC уже на той же команде
    if (haltPc != null && (cpu.pc & 0xffff) === haltPc) break;
    void opAt;
  }
  if (insns >= maxInsns) {
    throw new Error(`не дошли до останова за ${maxInsns} команд, PC=0x${(cpu.pc & 0xffff).toString(16)}`);
  }
  return { insns, cpuCycles, vcycles, bodyCpu, bodyV, pc: cpu.pc & 0xffff, mem: dumpMem(machine), regs: regs(machine) };
}

function parseArgs(argv) {
  const o = { rom: null, dump: null, cycles: null, halt: null, poke: null };
  const a = argv.slice(2);
  o.rom = a.shift();
  while (a.length) {
    const k = a.shift();
    if (k === '--dump') o.dump = a.shift();
    else if (k === '--cycles') o.cycles = +a.shift();
    else if (k === '--halt') o.halt = a.shift();
    else if (k === '--poke') o.poke = a.shift();
    else throw new Error('неизвестная опция ' + k);
  }
  return o;
}

const isMain = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  const opt = parseArgs(process.argv);
  if (!opt.rom) {
    console.error('usage: node v06c/tools/run.mjs ROM [--dump mem.bin] [--halt LABEL] [--cycles N] [--poke addr:hex]');
    process.exit(2);
  }
  const romPath = path.resolve(opt.rom);
  const rom = fs.readFileSync(romPath);
  const sym = parseSym(romPath.replace(/\.rom$/i, '.sym'));
  const m = createMachine();
  loadRom(m, rom);
  if (opt.poke) {
    const [addrS, hex] = opt.poke.split(':');
    poke(m, parseInt(addrS, 16), Buffer.from(hex, 'hex'));
  }
  let haltPc = null;
  if (opt.halt) {
    if (!(opt.halt in sym)) throw new Error('нет метки ' + opt.halt);
    haltPc = sym[opt.halt];
  }
  const maxInsns = opt.cycles ? opt.cycles : 20_000_000;
  const r = runUntil(m, { haltPc, maxInsns });
  if (opt.dump) fs.writeFileSync(opt.dump, r.mem);
  console.log(`OK pc=0x${r.pc.toString(16)} insns=${r.insns} cpu_cycles=${r.cpuCycles} vcycles=${r.vcycles}`);
  console.log(`regs a=${r.regs.a} bc=${((r.regs.b << 8) | r.regs.c).toString(16)} de=${((r.regs.d << 8) | r.regs.e).toString(16)} hl=${((r.regs.h << 8) | r.regs.l).toString(16)} sp=0x${r.regs.sp.toString(16)}`);
}

export { ROOT, VEC };

/** Печать профиля: такты по файлам-модулям (по меткам *_end и началам) и по меткам. */
export function printProf(prof, L, top = 30) {
  const names = Object.entries(L).filter(([, v]) => v >= 0x100 && v < 0xA000).sort((a, b) => a[1] - b[1]);
  const cost = new Float64Array(names.length); let total = 0, k = 0;
  for (let a = 0; a < 0x10000; a++) { while (k + 1 < names.length && names[k + 1][1] <= a) k++; if (prof[a]) { total += prof[a]; if (names[k][1] <= a) cost[k] += prof[a]; } }
  const byPrefix = {};
  names.forEach(([n], i) => { if (!cost[i]) return; const pre = n.split('_')[0]; byPrefix[pre] = (byPrefix[pre] || 0) + cost[i]; });
  console.log(`всего тактов ${total}; по префиксам меток:`);
  for (const [pre, c] of Object.entries(byPrefix).sort((a, b) => b[1] - a[1]).slice(0, 16)) console.log(`  ${(100 * c / total).toFixed(1).padStart(5)}%  ${pre}_*`);
  console.log('по меткам:');
  for (const i of [...cost.keys()].sort((a, b) => cost[b] - cost[a]).slice(0, top)) console.log(`  ${(100 * cost[i] / total).toFixed(1).padStart(5)}%  ${names[i][0]}`);
}
