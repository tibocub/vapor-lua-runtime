#!/bin/sh
# runs every tests/*.lua with ./vlr; a test file may start with `--! dialect 5.4` to run in plain 5.4
cd "$(dirname "$0")/.." || exit 1
fail=0
for t in tests/*.lua; do
  opt=
  head -n1 "$t" | grep -q '^--! dialect 5.4' && opt=--dialect=5.4
  if ./vlr $opt "$t" </dev/null >/dev/null 2>/tmp/vlr-test.err; then echo "ok   $t"; else echo "FAIL $t"; cat /tmp/vlr-test.err; fail=1; fi
done
exit $fail
