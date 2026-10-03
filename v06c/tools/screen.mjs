// Экран Вектора (три плоскости A000/C000/E000) → массив 256×256 индексов 0..7, как v[y*256+x] эталона.

/** Адрес байта и маска бита точки (x, y) в плоскости. y=0 — верх (младший байт адреса 255-y), бит 7 — левая точка. */
export function pixelLoc(x, y) {
  const col = x >> 3;
  const mask = 0x80 >> (x & 7);
  const off = col * 256 + (255 - y);
  return {
    col, mask, y, off,
    a000: 0xA000 + off,
    c000: 0xC000 + off,
    e000: 0xE000 + off,
  };
}

export function screenToPlanes(v, mem) {
  if (!mem) mem = new Uint8Array(0x10000);
  for (let y = 0; y < 256; y++) {
    for (let col = 0; col < 32; col++) {
      let a = 0, b = 0, c = 0;
      for (let bit = 0; bit < 8; bit++) {
        const x = col * 8 + bit;
        const color = v[y * 256 + x] & 7;
        const mask = 0x80 >> bit;
        if (color & 1) a |= mask;
        if (color & 2) b |= mask;
        if (color & 4) c |= mask;
      }
      const off = col * 256 + (255 - y);
      mem[0xA000 + off] = a;
      mem[0xC000 + off] = b;
      mem[0xE000 + off] = c;
    }
  }
  return mem;
}

export function planesToScreen(mem) {
  const v = new Uint8Array(256 * 256);
  for (let y = 0; y < 256; y++) {
    for (let col = 0; col < 32; col++) {
      const a = mem[0xA000 + col * 256 + (255 - y)];
      const b = mem[0xC000 + col * 256 + (255 - y)];
      const c = mem[0xE000 + col * 256 + (255 - y)];
      for (let bit = 0; bit < 8; bit++) {
        const mask = 0x80 >> bit;
        const x = col * 8 + bit;
        let color = 0;
        if (a & mask) color |= 1;
        if (b & mask) color |= 2;
        if (c & mask) color |= 4;
        v[y * 256 + x] = color;
      }
    }
  }
  return v;
}

export function firstPixelDiff(got, exp) {
  for (let i = 0; i < got.length; i++) {
    if (got[i] !== exp[i]) {
      const x = i & 255, y = i >> 8;
      return { i, x, y, got: got[i], exp: exp[i] };
    }
  }
  return null;
}
