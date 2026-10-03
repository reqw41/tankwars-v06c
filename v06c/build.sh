#!/bin/sh
# Сборка v06c/build/tw.rom (i8080, старт 0100h).
# Ассемблер: SjASMPlus 1.24.0 (tools/bin/sjasmplus, режим --i8080).
set -e
cd "$(dirname "$0")/.."
ROOT=$(pwd)
ASM="$ROOT/tools/bin/sjasmplus"
mkdir -p v06c/build

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
