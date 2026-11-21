#!/bin/sh
# Hygiene gates: strict warnings on our own code, tests under ASan+UBSan (clang), and a size line.
cd "$(dirname "$0")/.." || exit 1
set -e
echo "== strict compile (our code only)"
make -s gen
cc -std=c99 -pedantic -Wall -Wextra -Werror -Iinclude -Ithird_party/lua -fsyntax-only src/vlr.c src/main.c src/platform_posix.c src/mod_fs.c src/mod_netraw.c src/net_posix.c
# vaporUI's public header is C11 (anonymous unions), so the module that includes it is checked as C11
cc -std=c11 -pedantic -Wall -Wextra -Werror -Iinclude -Ithird_party/lua -I../vaporUI/src -fsyntax-only src/mod_term.c
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
