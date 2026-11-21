#!/bin/sh
# DYNAMIC=1 builds only: a .so module loads through require and caps.dlopen is true. Run from the repo root.
set -e
make -s clean >/dev/null; make -s vlr DYNAMIC=1
d=$(mktemp -d); trap 'rm -rf "$d"' EXIT
${CC:-cc} -shared -fPIC -Ithird_party/lua -o "$d/toy.so" tests/dynamic/toy.c
printf 'package.cpath = "%s/?.so"\nassert(vapor.caps.dlopen == true)\nassert(require("toy").twice(21) == 42)\n' "$d" > "$d/t.lua"
./vlr "$d/t.lua" && echo "ok   dynamic module"
make -s clean >/dev/null; make -s vlr
