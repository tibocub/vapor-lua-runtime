#!/bin/sh
# modsrc.sh modules.conf EXT [name...] -> sources and -D flags of the listed modules (all if none listed),
# one per line, @EXT@ replaced by EXT. Shared by the host Makefile and the NuttX app Makefile.
conf=$1 ext=$2
shift 2
awk -v want=" $* " '!/^[#]/ && NF > 2 && (want == "  " || index(want, " " $1 " ")) { for (i = 3; i <= NF; i++) print $i }' "$conf" |
  sed "s#@EXT@#$ext#"
