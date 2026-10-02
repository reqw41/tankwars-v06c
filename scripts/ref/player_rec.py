"""Запись игрока (0x61 байт, DS:3EFC + 0x61*i) — известные поля."""
import struct

FIELDS = {'x': (0x00, 'h'), 'y': (0x02, 'h'), 'score': (0x04, 'i'), 'power': (0x0E, 'h'), 'angle': (0x10, 'h'),
          'facing': (0x12, 'h'), 'men': (0x14, 'h'), 'alive': (0x16, 'B'), 'weapon': (0x17, 'h'), 'shield': (0x45, 'i')}


def decode(raw: bytes) -> dict:
    return {k: struct.unpack_from('<' + f, raw, o)[0] for k, (o, f) in FIELDS.items()}


def encode_into(raw: bytearray, rec: dict) -> bytearray:
    for k, (o, f) in FIELDS.items():
        if k in rec:
            struct.pack_into('<' + f, raw, o, rec[k])
    return raw
