#!/bin/sh
# Hygiene gates: strict warnings on our own code, tests under ASan+UBSan (clang), and a size line.
cd "$(dirname "$0")/.." || exit 1
set -e
echo "== strict compile (our code only)"
make -s build/vlr_modules.c build/compat.c build/sched.c
cc -std=c99 -pedantic -Wall -Wextra -Werror -Iinclude -Ithird_party/lua -fsyntax-only src/vlr.c src/main.c src/platform_posix.c
echo "== tests under ASan+UBSan"
make -s clean
CC=clang CFLAGS="-O1 -g -fsanitize=address,undefined -fno-sanitize-recover=undefined" LDFLAGS="-fsanitize=address,undefined" make -s vlr
sh tests/run.sh
echo "== normal build, tests, size"
make -s clean
make -s vlr
sh tests/run.sh
strip -o build/vlr.stripped vlr
echo "stripped size: $(wc -c < build/vlr.stripped) bytes"
