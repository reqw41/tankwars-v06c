#!/usr/bin/env node
// Тексты порта в кодах знакогенератора (20h..5Fh и русские прописные 80h..9Fh — charCode эталона):
//   v06c/src/names.inc        — названия оружия и товаров (из эталона), цены;
//   v06c/src/strings.inc      — строки панели, результатов и магазина (ui.asm), с нулём в конце;
//   v06c/src/strings_game.inc — строки игры: имена игроков, экран настройки (без нуля, длина в коде).
// sjasmplus русские буквы в строках не перекодирует, поэтому байты пишутся числами. Править тексты — здесь.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import * as TW from '../../web/tankwars.js';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const db = (label, text, { z = false, pad = 0, zpad = 0 } = {}) => {
  const b = TW.encodeText(text);
  if (pad && b.length > pad || zpad && b.length > zpad) throw new Error(`«${text}» длиннее ${pad || zpad}`);
  while (b.length < pad) b.push(0x20);
  while (b.length < zpad) b.push(0);
  if (z) b.push(0);
  return `${label ? label + ':' : ''}\tdb\t${b.map((v) => '0x' + v.toString(16).padStart(2, '0')).join(', ')}\t; "${text}"`;
};
const write = (file, lines) => { fs.writeFileSync(path.join(ROOT, 'v06c/src', file), lines.join('\n') + '\n'); console.log('OK: v06c/src/' + file); };

// --- названия и цены ---
const dw = (label, a) => `${label}:\n\tdw\t${a.map((v) => (v === null || v === undefined ? -1 : v)).join(', ')}`;
write('names.inc', ['; названия и цены магазина — из эталона (v06c/tools/text2inc.mjs), не править руками', 'wpn_names:',
  ...TW.WEAPON_NAMES_RU.map((n) => db('', n, { pad: 15 })), 'shop_n1:', ...TW.SHOP_NAMES_RU[1].map((n) => db('', n, { pad: 15 })),
  'shop_n2:', ...TW.SHOP_NAMES_RU[2].map((n) => db('', n, { pad: 15 })),
  dw('wpn_price', TW.SHOP_PRICE[0]), dw('shop_p1', TW.SHOP_PRICE[1]), dw('shop_p2', TW.SHOP_PRICE[2])]);

// --- панель, результаты, магазин: те же строки, что в drawPanel / drawResults / drawShop эталона ---
const UI = { s_wind: 'ВЕТЕР ', s_ang: 'УГОЛ ', s_pow: '  СИЛА ', s_men: '  ЭНЕРГИЯ ', s_x: ' X', s_after: 'ПОСЛЕ РАУНДА ', s_of: ' ИЗ ', s_final: 'ИТОГ МАТЧА',
  s_hdr: '# ИГРОК        ПОБЕД   ОЧКИ', s_money: 'ДЕНЬГИ', s_press: 'НАЖМИТЕ ЛЮБУЮ КЛАВИШУ', s_over: 'ИГРА ОКОНЧЕНА', s_shop: 'МАГАЗИН', s_moneys: 'ДЕНЬГИ ',
  s_cart: '  КОРЗИНА ', s_item: 'ТОВАР            ЦЕНА ЕСТЬ КУП', s_buy: ' КУПИТЬ', s_done: ' ГОТОВО' };
write('strings.inc', ['; строки панели, результатов и магазина (v06c/tools/text2inc.mjs), не править руками', ...Object.entries(UI).map(([l, t]) => db(l, t, { z: true }))]);

// --- игра: имена и экран настройки ---
const AI = ['Mr. Stupid', 'Lobber', 'Rifleman', 'Lob & Shoot', 'Windless Wit', 'Twanger', 'Birdy Bonker'];       // порядок — номер типа 1..7
const G = [
  db('s_gtitle', 'TANK WARS'), db('s_player', 'ИГРОК '),
  's_ainames:\t\t; по 13 байт; тип игрока порт узнаёт по первой букве (cs_type в aimain.asm)', ...AI.map((n) => db('', TW.dispName(n), { zpad: 13 })),
  db('s_start', 'НАЧАТЬ'), db('s_helpitem', 'ПОМОЩЬ'), db('s_help', 'СТРЕЛКИ: ВЫБОР  ПРОБЕЛ: СТАРТ'),
  '; подписи настроек — по 8 знаков', ...Object.entries({ s_o_n: 'ИГРОКОВ', s_o_rounds: 'РАУНДОВ', s_o_walls: 'ОТСКОК', s_o_wind: 'ВЕТЕР', s_o_crumble: 'ОСЫПАНИЕ',
    s_o_fall: 'ПАДЕНИЕ', s_o_xkill: 'ОБЛОМКИ' }).map(([l, t]) => db(l, t, { pad: 8 })),
  '; названия значений — по 9 знаков', 's_v_walls:', ...['НЕТ', 'СЛУЧАЙНО', 'ДА'].map((t) => db('', t, { pad: 9 })),
  's_v_wind:', ...['НЕТ', 'СЛАБЫЙ', 'СРЕДНИЙ', 'СИЛЬНЫЙ', 'ШТОРМ', 'СЛУЧАЙНЫЙ'].map((t) => db('', t, { pad: 9 })),
  's_v_yes:', ...['НЕТ', 'ДА'].map((t) => db('', t, { pad: 9 })),
];
// экран помощи: строки по порядку сверху вниз (не длиннее 32 знаков), каждая с нулём в конце; конец — байт FFh
const HELP = [
  '           УПРАВЛЕНИЕ',
  '',
  ' СТРЕЛКИ ВЛЕВО, ВПРАВО - УГОЛ',
  ' СТРЕЛКИ ВВЕРХ, ВНИЗ   - СИЛА',
  '         (ДЕРЖАТЬ - БЫСТРЕЕ)',
  ' ПРОБЕЛ ИЛИ ВК - ОГОНЬ',
  ' ТАБ ИЛИ W, Q  - ОРУЖИЕ',
  ' I             - РАЗВОРОТ',
  ' H, V          - НАВЕДЕНИЕ',
  ' T             - ЦЕЛЬ НАВЕДЕНИЯ',
  ' АР2 - ПРЕРВАТЬ РАУНД: НИЧЬЯ',
  ' СТР - ПРЕРВАТЬ: ПОБЕДА ЖРЕБИЕМ',
  ' ДЖОЙСТИК П - КАК СТРЕЛКИ,',
  ' ОГОНЬ 1 - ВЫСТРЕЛ, 2 - ОРУЖИЕ',
  '',
  ' ЦЕЛЬ - ОСТАТЬСЯ ПОСЛЕДНИМ.',
  ' ЗА УРОН И ПОБЕДЫ ДАЮТ ОЧКИ,',
  ' НА НИХ МЕЖДУ РАУНДАМИ ПОКУПАЮТ',
  ' ОРУЖИЕ И ЗАЩИТУ.',
  ' ВЕТЕР СНОСИТ СНАРЯД:',
  ' <20 - ВЛЕВО, 20> - ВПРАВО.',
  '',
  ' МАГАЗИН: ВВЕРХ, ВНИЗ - ТОВАР,',
  ' ВПРАВО - ВЗЯТЬ, ВЛЕВО - ВЕРНУТЬ',
  ' ПРОБЕЛ НА "ГОТОВО" - ДАЛЬШЕ.',
  '',
  '     НАЖМИТЕ ЛЮБУЮ КЛАВИШУ',
];
for (const l of HELP) if (l.length > 32) throw new Error(`помощь: строка длиннее 32: «${l}»`);
G.push('; экран помощи', 's_helptext:', ...HELP.map((l) => db('', l, { z: true })), '\tdb\t0xff');
write('strings_game.inc', ['; строки игры (v06c/tools/text2inc.mjs), не править руками', ...G]);
