// Запись игрока 8080 (v06c/src/player.inc) <-> объект Player эталона.
import { dispName, encodeText, decodeText } from '../../web/tankwars.js';
export const PL_SIZE = 108, MAX_PLAYERS = 4;
const O = { x: 0, y: 1, angle: 2, facing: 3, power: 4, men: 6, alive: 8, weapon: 9, guided: 10, target: 11, herb: 12, vick: 14, score: 16, spent: 20,
  wins: 24, ctrl: 26, strategy: 27, colors: 28, shield: 32, damp: 36, ammo: 40, name: 76, aiN: 90, aiPlan: 91, aiPower: 92, aiAngle: 94, aiFacing: 95,
  aiWeapon: 96, aiTarget: 97 };
const w16 = (b, o, v) => { b[o] = v & 255; b[o + 1] = (v >> 8) & 255; };
const w32 = (b, o, v) => { w16(b, o, v); w16(b, o + 2, v >> 16); };
const r16 = (b, o) => ((b[o] | (b[o + 1] << 8)) << 16) >> 16;
const r32 = (b, o) => (b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24)) | 0;
export function packPlayer(p) {
  const b = new Uint8Array(PL_SIZE);
  b[O.x] = p.x; b[O.y] = p.y; b[O.angle] = p.angle; b[O.facing] = p.facing & 255; w16(b, O.power, p.power); w16(b, O.men, p.men);
  b[O.alive] = p.alive ? 1 : 0; b[O.weapon] = p.weapon; b[O.guided] = p.guided; b[O.target] = p.target; w16(b, O.herb, p.herb); w16(b, O.vick, p.vick);
  w32(b, O.score, p.score); w32(b, O.spent, p.spent); w16(b, O.wins, p.wins); b[O.ctrl] = p.ctrl; b[O.strategy] = p.strategy | 0;
  p.colors.forEach((c, i) => { b[O.colors + i] = c === 1 ? 1 : 0xff; });
  w32(b, O.shield, p.shield); w32(b, O.damp, p.damp);
  for (let k = 0; k < 18; k++) w16(b, O.ammo + 2 * k, p.ammo[k]);
  // в записи — имя, как на экране: русское, в кодах знакогенератора (у компьютеров по первой букве порт узнаёт тип)
  encodeText(dispName(p.name).slice(0, 13)).forEach((c, i) => { b[O.name + i] = c; });
  const h = p.hist || {};
  b[O.aiN] = h.n | 0; b[O.aiPlan] = h.planned | 0; w16(b, O.aiPower, h.power | 0); b[O.aiAngle] = h.angle | 0; b[O.aiFacing] = (h.facing | 0) & 255;
  b[O.aiWeapon] = h.weapon | 0; b[O.aiTarget] = h.target | 0;
  return b;
}
// объект для сравнения: все поля записи в читаемом виде
export function viewPlayer(b) {
  let n = 0; while (n < 13 && b[O.name + n]) n++;
  const name = decodeText(b.subarray(O.name, O.name + n));
  const ammo = []; for (let k = 0; k < 18; k++) ammo.push(r16(b, O.ammo + 2 * k));
  return { name, x: b[O.x], y: b[O.y], angle: b[O.angle], facing: (b[O.facing] << 24) >> 24, power: r16(b, O.power), men: r16(b, O.men), alive: b[O.alive],
    weapon: b[O.weapon], guided: b[O.guided], target: b[O.target], herb: r16(b, O.herb), vick: r16(b, O.vick), score: r32(b, O.score), spent: r32(b, O.spent),
    wins: r16(b, O.wins), ctrl: b[O.ctrl], strategy: b[O.strategy], colors: [...b.subarray(O.colors, O.colors + 3)].join('.'), shield: r32(b, O.shield),
    damp: r32(b, O.damp), ammo: ammo.join('.'), aiN: b[O.aiN], aiPlan: b[O.aiPlan], aiPower: r16(b, O.aiPower), aiAngle: b[O.aiAngle],
    aiFacing: (b[O.aiFacing] << 24) >> 24, aiWeapon: b[O.aiWeapon], aiTarget: b[O.aiTarget] };
}
export const viewKey = (b) => JSON.stringify(viewPlayer(b));
