#!/bin/sh
# Сборка v06c/build/tw.rom (i8080, старт 0100h).
# Ассемблер: SjASMPlus 1.24.0 (tools/bin/sjasmplus, режим --i8080).
set -e
cd "$(dirname "$0")/.."
ROOT=$(pwd)
ASM="$ROOT/tools/bin/sjasmplus"
mkdir -p v06c/build
node v06c/tools/font2rows.mjs
node v06c/tools/text2inc.mjs
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
# потолок образа: буфер LIST стенда начинается с 8800h — образ не должен до него доставать
if [ "$sz" -gt $((0x8800 - 0x100)) ]; then
	echo "ОБРАЗ ($sz Б) ДОСТАЁТ ДО БУФЕРА LIST (8800h) — провал"
	rm -f v06c/build/tw.rom
	exit 1
fi

# игра (v06c/src/game.asm) — те же модули с главным циклом
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
gsz=$(wc -c < v06c/build/game.bin | tr -d ' ')
echo "OK: v06c/build/game.bin ($gsz Б)"
if [ "$gsz" -gt $((0x9A00 - 0x100)) ]; then
	echo "ИГРА ($gsz Б) ДОСТАЁТ ДО ТАБЛИЦ ГЕНЕРАТОРА (9A00h) — провал"
	exit 1
fi

# образ для машины: загрузчик с заставкой (16 цветов, четыре плоскости) и сжатая игра — v06c/src/loader.asm
python3 v06c/tools/title2planes.py > /dev/null
"$ROOT/tools/bin/zx0" -f -c v06c/build/title.bin v06c/build/title.zx0 > /dev/null
"$ROOT/tools/bin/zx0" -f -c v06c/build/game.bin v06c/build/game.zx0 > /dev/null
out=$($ASM --i8080 --fullpath -i v06c/src \
	--lst=v06c/build/loader.lst --sym=v06c/build/loader.sym \
	v06c/src/loader.asm 2>&1) || {
	echo "$out"
	echo "СБОРКА ЗАГРУЗЧИКА ПРОВАЛЕНА"
	exit 1
}
if echo "$out" | grep -Eiq 'warning:|warnings: [1-9]'; then
	echo "$out"
	echo "ЕСТЬ ПРЕДУПРЕЖДЕНИЯ sjasmplus (загрузчик) — провал"
	exit 1
fi
python3 v06c/tools/check_i8080.py v06c/build/loader.lst
rsz=$(wc -c < v06c/build/game.rom | tr -d ' ')
echo "OK: v06c/build/game.rom ($rsz Б: заставка $(wc -c < v06c/build/title.zx0 | tr -d ' '), игра $(wc -c < v06c/build/game.zx0 | tr -d ' '))"

# готовый образ — в rom/ (в репозитории): грузится с 0100h, на Векторе Турбо+ из CP/M — TANKWARS.COM, ключ -V T3
mkdir -p rom
cp v06c/build/game.rom rom/tankwars.rom
echo "OK: rom/tankwars.rom"
