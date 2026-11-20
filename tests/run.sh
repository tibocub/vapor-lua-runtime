#!/bin/sh
# Runs every tests/*.lua twice: the normal loop and --step (loop driven from C like a browser host would).
# VLR overrides the command (e.g. VLR="wine ./vlr.exe"). A test starting with `--! dialect 5.4` runs as plain 5.4.
cd "$(dirname "$0")/.." || exit 1
VLR=${VLR:-./vlr}
fail=0
for t in tests/*.lua; do
  opt=
  head -n1 "$t" | grep -q '^--! dialect 5.4' && opt=--dialect=5.4
  for mode in "" --step; do
    if $VLR $opt $mode "$t" </dev/null >/dev/null 2>"${TMPDIR:-/tmp}/vlr-test.err"; then echo "ok   $t $mode"
    else echo "FAIL $t $mode"; cat "${TMPDIR:-/tmp}/vlr-test.err"; fail=1; fi
  done
done
exit $fail
