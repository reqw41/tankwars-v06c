#!/bin/sh
# Сборка v06c/build/tw.rom (i8080, старт 0100h).
# Ассемблер: SjASMPlus 1.24.0 (tools/bin/sjasmplus, режим --i8080).
set -e
cd "$(dirname "$0")/.."
ROOT=$(pwd)
ASM="$ROOT/tools/bin/sjasmplus"
mkdir -p v06c/build
node v06c/tools/font2rows.mjs
node v06c/tools/disc2tab.mjs
node v06c/tools/fx2tab.mjs

out=$($ASM --i8080 --fullpath -i v06c/src \
	--lst=v06c/build/tw.lst --sym=v06c/build/tw.sym --sld=v06c/build/tw.sld \
	v06c/src/tw.asm 2>&1) || {
	echo "$out"
	echo "СБОРКА ПРОВАЛЕНА"
	exit 1
}
echo "$out"
if echo "$out" | grep -Eiq 'warning:|warnings: [1-9]'; then
	echo "ЕСТЬ ПРЕДУПРЕЖДЕНИЯ sjasmplus — провал"
	exit 1
fi

python3 v06c/tools/check_i8080.py v06c/build/tw.lst
sz=$(wc -c < v06c/build/tw.rom | tr -d ' ')
echo "OK: v06c/build/tw.rom ($sz Б)"
# потолок образа: буфер LIST стенда начинается с 7000h — образ не должен до него доставать
if [ "$sz" -gt $((0x7800 - 0x100)) ]; then
	echo "ОБРАЗ ($sz Б) ДОСТАЁТ ДО БУФЕРА LIST (7800h) — провал"
	rm -f v06c/build/tw.rom
	exit 1
fi

# игровой образ (v06c/src/game.asm) — те же модули с главным циклом
out=$($ASM --i8080 --fullpath -i v06c/src \
	--lst=v06c/build/game.lst --sym=v06c/build/game.sym \
	v06c/src/game.asm 2>&1) || {
	echo "$out"
	echo "СБОРКА ИГРЫ ПРОВАЛЕНА"
	exit 1
}
if echo "$out" | grep -Eiq 'warning:|warnings: [1-9]'; then
	echo "$out"
	echo "ЕСТЬ ПРЕДУПРЕЖДЕНИЯ sjasmplus (игра) — провал"
	exit 1
fi
python3 v06c/tools/check_i8080.py v06c/build/game.lst
gsz=$(wc -c < v06c/build/game.rom | tr -d ' ')
echo "OK: v06c/build/game.rom ($gsz Б)"
if [ "$gsz" -gt $((0x9E00 - 0x100)) ]; then
	echo "ИГРА ($gsz Б) ДОСТАЁТ ДО СТЕКА — провал"
	exit 1
fi
