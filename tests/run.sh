#!/bin/sh
# Runs every tests/*.lua twice: the normal loop and --step (loop driven from C like a browser host would).
# VLR overrides the command (e.g. VLR="wine ./vlr.exe"). A test starting with `--! dialect 5.4` runs as plain 5.4.
cd "$(dirname "$0")/.." || exit 1
if [ -z "$VLR" ]; then
  case $(uname -s) in MINGW*|MSYS*|CYGWIN*) VLR=./vlr.exe ;; *) VLR=./vlr ;; esac
  [ -f "$VLR" ] || { echo "no $VLR here: build first (make, or make TARGET=win32 CC=gcc)"; exit 1; }
fi
fail=0
for t in tests/*.lua; do
  opt=
  head -n1 "$t" | grep -q '^--! dialect 5.4' && opt=--dialect=5.4
  for mode in "" --step; do
    if $VLR $opt $mode "$t" </dev/null >/dev/null 2>"${TMPDIR:-/tmp}/vlr-test.err"; then echo "ok   $t $mode"
    else echo "FAIL $t $mode"; cat "${TMPDIR:-/tmp}/vlr-test.err"; fail=1; fi
  done
done
# rockspec -> modules.conf lines (tools/rock2conf.lua)
if [ "$VLR" = ./vlr ]; then
  out=$(./vlr tools/rock2conf.lua tests/rock/toy-1.rockspec tests/rock 2>&1)
  if [ "$out" = "$(cat tests/rock/expected.conf)" ]; then echo "ok   rock2conf"; else echo "FAIL rock2conf: $out"; fail=1; fi
fi

# os.exit closes the state (finalizers run) and keeps the status
f="${TMPDIR:-/tmp}/vlr-exit.lua"
printf 'setmetatable({}, {__gc = function() io.write("closed") end})\nos.exit(7)\n' > "$f"
out=$($VLR "$f" </dev/null 2>/dev/null); rc=$?
if [ "$rc" = 7 ] && [ "$out" = closed ]; then echo "ok   os.exit"; else echo "FAIL os.exit (rc=$rc out=$out)"; fail=1; fi
rm -f "$f"
# TLS against local openssl servers (posix hosts)
if [ "$VLR" = ./vlr ]; then sh tests/tls/run.sh || fail=1; fi

# -e and the prompt (no script); the browser/Node runner (web/run.mjs) only takes a script
case $VLR in *run.mjs*) exit $fail ;; esac
out=$($VLR -e 'io.write(40 + 2)' </dev/null 2>&1)
if [ "$out" = 42 ]; then echo "ok   -e"; else echo "FAIL -e (out=$out)"; fail=1; fi
out=$(printf '6 * 7\n' | $VLR 2>&1 | tr -d '\r')
case $out in *42*) echo "ok   prompt" ;; *) echo "FAIL prompt (out=$out)"; fail=1 ;; esac
exit $fail
