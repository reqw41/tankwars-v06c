// Звук ВИ53 (8080): порядок и значения записей в порты против ожидаемых. node v06c/test/sound.mjs
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createMachine, loadRom, poke, runUntil, parseSym } from '../tools/run.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const L = parseSym(path.join(ROOT, 'v06c/build/tw.sym'));
const rom = new Uint8Array(fs.readFileSync(path.join(ROOT, 'v06c/build/tw.rom')));
const machine = createMachine();
const PARAM = 0x80, LIST = 0x8800, MODE_SOUND = 35;
for (const n of ['snd_tone', 'snd_off', 'snd_play', 'snd_tick', 'sound_end', 'snd_ptr', 'snd_cnt']) if (L[n] === undefined) { console.error('FAIL нет метки ' + n); process.exit(1); }
let log = [];
const real = machine.io.realoutput.bind(machine.io);
machine.io.realoutput = (p, b) => { if (p >= 0x08 && p <= 0x0b) log.push(`${p.toString(16).padStart(2, '0')}=${b.toString(16).padStart(2, '0')}`); real(p, b); };
function run(kind, word, ticks, table) {
  loadRom(machine, rom); log = [];
  const hdr = new Uint8Array(16); hdr[0] = MODE_SOUND; hdr[1] = kind; hdr[2] = ticks & 255; hdr[3] = ticks >> 8; hdr[4] = word & 255; hdr[5] = word >> 8;
  poke(machine, PARAM, hdr); if (table) poke(machine, LIST, table);
  const r = runUntil(machine, { haltPc: null, maxInsns: 2_000_000 });
  return { log: log.join(' '), ptr: r.mem[L.snd_ptr] | (r.mem[L.snd_ptr + 1] << 8) };
}
const tone = (d) => `08=36 0b=${(d & 255).toString(16).padStart(2, '0')} 0b=${(d >> 8).toString(16).padStart(2, '0')}`, off = '08=36';
function expect(tag, got, want) { if (got !== want) { console.error(`FAIL ${tag}:\n  записи в порты 8080: ${got || '(нет)'}\n  надо:                ${want || '(нет)'}`); process.exit(1); } }
let n = 0;
for (const d of [2, 1000, 0x1234, 0xFFFF, 256, 255]) { expect(`snd_tone(${d})`, run(1, d, 0).log, tone(d)); n++; }
expect('snd_off', run(2, 0, 0).log, off); n++;
// эффект: ноты (делитель — слово, длительность в кадрах — байт), конец — слово 0; делитель 1 — пауза
const note = (d, f) => [d & 255, d >> 8, f];
const T1 = [...note(1000, 2), ...note(500, 1), ...note(1, 3), ...note(250, 1), 0, 0];
const steps = [tone(1000), '', tone(500), off, '', '', tone(250), off, '', ''];   // сразу при snd_play, затем по одному snd_tick
for (let t = 0; t < steps.length; t++) {
  const r = run(3, 0, t, T1), want = steps.slice(0, t + 1).filter(Boolean).join(' ');
  expect(`snd_play + ${t} раз snd_tick (таблица: 1000 на 2 кадра, 500 на 1, пауза на 3, 250 на 1, конец)`, r.log, want);
  if (t >= 7 && r.ptr !== 0) { console.error(`FAIL после конца эффекта snd_ptr должен быть 0, а он ${r.ptr}`); process.exit(1); }
  n++;
}
{ const r = run(3, 0, 5, [0, 0]); expect('snd_play с пустой таблицей', r.log, off); if (r.ptr !== 0) { console.error('FAIL пустая таблица: snd_ptr не 0'); process.exit(1); } n++; }
{ const r = run(3, 0, 300, [...note(777, 255), ...note(888, 1), 0, 0]); expect('нота на 255 кадров', r.log, [tone(777), tone(888), off].join(' ')); n++; }
console.log(`OK  звук: ${n} случаев — записи в порты ВИ53 совпали; байт ${L.sound_end - L.snd_tone}`);
