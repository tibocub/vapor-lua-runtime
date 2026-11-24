#!/bin/sh
# Hygiene gates: strict warnings on our own code, tests under ASan+UBSan (clang), and a size line.
cd "$(dirname "$0")/.." || exit 1
set -e
echo "== strict compile (our code only)"
make -s gen
cc -std=c99 -pedantic -Wall -Wextra -Werror -Iinclude -Ithird_party/lua -fsyntax-only src/vlr.c src/main.c src/platform_posix.c src/mod_netraw.c src/net_posix.c
echo "== tests under ASan+UBSan"
make -s clean
# THIRDFLAGS: BearSSL calls its method tables through differently typed pointers and reads unaligned on purpose; clang flags both
CC=clang CFLAGS="-O1 -g -fsanitize=address,undefined -fno-sanitize-recover=undefined " THIRDFLAGS="-fno-sanitize=function,alignment" LDFLAGS="-fsanitize=address,undefined" make -s vlr
sh tests/run.sh
echo "== normal build, tests, size"
make -s clean
make -s vlr
sh tests/run.sh
strip -o build/vlr.stripped vlr
echo "stripped size: $(wc -c < build/vlr.stripped) bytes"
