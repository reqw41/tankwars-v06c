// Профиль полёта на стенде: такты по меткам. node v06c/tools/prof.mjs [угол мощность ветер стены]
import fs from 'node:fs';
import path from 'node:path';
import * as TW from '../../web/tankwars.js';
import { createMachine, loadRom, poke, parseSym, ROOT } from './run.mjs';
import { screenToPlanes } from './screen.mjs';
const json = (p) => JSON.parse(fs.readFileSync(path.join(ROOT, p), 'utf8'));
TW.init({ barrel: json('web/data/barrel.json'), trig: json('web/data/trig.json') }); TW.setProfile(TW.PROFILE_V06C);
const L = parseSym(path.join(ROOT, 'v06c/build/tw.sym')), rom = new Uint8Array(fs.readFileSync(path.join(ROOT, 'v06c/build/tw.rom')));
const [angle, power, wind, rebound] = [+process.argv[2] || 60, +process.argv[3] || 400, +(process.argv[4] ?? 30), +(process.argv[5] ?? 1)];
const m = createMachine(), ps = [1, 2].map((k) => TW.newPlayer(k, 10)), r0 = TW.roundStart(new TW.TPRandom(7), ps, 0, 0, 2);
loadRom(m, rom); const mem0 = new Uint8Array(0x10000); screenToPlanes(r0.v, mem0); poke(m, 0xA000, mem0.subarray(0xA000));
const hdr = new Uint8Array(16); hdr[0] = 23; poke(m, 0x80, hdr);
poke(m, 0x8000, [angle, 1, power & 255, power >> 8, ps[0].x, ps[0].y, wind & 255, (wind >> 8) & 255, rebound, 1, 100, 0, 2, 1]);
const names = Object.entries(L).filter(([, v]) => v >= 0x100 && v < 0x8000).sort((a, b) => a[1] - b[1]);
const owner = new Int32Array(0x10000).fill(-1); { let k = 0; for (let a = 0; a < 0x10000; a++) { while (k + 1 < names.length && names[k + 1][1] <= a) k++; owner[a] = names[k][1] <= a ? k : -1; } }
const cost = new Float64Array(names.length); let total = 0, loops = 0;
const cpu = m.cpu;
for (let i = 0; i < 2e9; i++) { const pc = cpu.pc & 0xffff; if (pc === L.fl_loop) loops++; cpu.instruction(); const vc = cpu.vcycles | 0; total += vc; if (owner[pc] >= 0) cost[owner[pc]] += vc; if (cpu.last_opcode === 0x76) break; }
// свернуть внутренние метки в подпрограммы: по префиксу до второго «_» не получится надёжно — печатаем метки как есть и группы по файлам
const top = [...cost.keys()].sort((a, b) => cost[b] - cost[a]).slice(0, 28);
console.log(`подшагов ${loops}, тактов ${total}, на подшаг ${(total / loops).toFixed(0)}`);
for (const k of top) console.log(`${(cost[k] / loops).toFixed(0).padStart(7)} ${(100 * cost[k] / total).toFixed(1).padStart(5)}%  ${names[k][0]}`);
