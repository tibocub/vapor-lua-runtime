#!/bin/sh
# modsrc.sh modules.conf EXT [name...] -> sources and -D flags of the listed modules (all if none listed),
# one per line, @EXT@ replaced by EXT and @VLR@ by the folder of modules.conf (in-tree modules). Lua-file modules
# (lua:path) have no C sources; a posix:path source is only built for the posix hosts; a source with * is expanded by the shell and print nothing. @PLAT@ = $VLR_PLAT (posix, win32, wasm, none; default posix): the target's half of a module. Shared by the host Makefile and the NuttX app Makefile.
conf=$1 ext=$2
shift 2
root=$(dirname "$conf")
awk -v want=" $* " '!/^[#]/ && NF > 2 && $2 !~ /^lua:/ && (want == "  " || index(want, " " $1 " ")) { for (i = 3; i <= NF; i++) print $i }' "$conf" |
  sed "s#@EXT@#$ext#g; s#@VLR@#$root#g; s#@PLAT@#${VLR_PLAT:-posix}#g" |
  while read -r t; do
    case $t in
      *\**) for f in $t; do echo "$f"; done ;; # a glob (BearSSL's src/*/*.c): one source per line
      posix:*) [ "${VLR_PLAT:-posix}" = posix ] && echo "${t#posix:}" ;; # a source only the posix hosts need (the Linux console keycode translator)
      *) echo "$t" ;;
    esac
  done
