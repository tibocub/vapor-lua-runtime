#!/bin/sh
# modsrc.sh modules.conf EXT [name...] -> sources and -D flags of the listed modules (all if none listed),
# one per line, @EXT@ replaced by EXT and @VLR@ by the folder of modules.conf (in-tree modules). Lua-file modules
# (lua:path) have no C sources and print nothing. Shared by the host Makefile and the NuttX app Makefile.
conf=$1 ext=$2
shift 2
root=$(dirname "$conf")
awk -v want=" $* " '!/^[#]/ && NF > 2 && $2 !~ /^lua:/ && (want == "  " || index(want, " " $1 " ")) { for (i = 3; i <= NF; i++) print $i }' "$conf" |
  sed "s#@EXT@#$ext#g; s#@VLR@#$root#g"
