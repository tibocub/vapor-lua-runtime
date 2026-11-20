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
# the real terminal path through a pty (posix hosts only)
if [ "$VLR" = ./vlr ] && command -v python3 >/dev/null 2>&1; then
  python3 -I tests/pty/run.py || fail=1
fi

# os.exit closes the state (finalizers run) and keeps the status
f="${TMPDIR:-/tmp}/vlr-exit.lua"
printf 'setmetatable({}, {__gc = function() io.write("closed") end})\nos.exit(7)\n' > "$f"
out=$($VLR "$f" </dev/null 2>/dev/null); rc=$?
if [ "$rc" = 7 ] && [ "$out" = closed ]; then echo "ok   os.exit"; else echo "FAIL os.exit (rc=$rc out=$out)"; fail=1; fi
rm -f "$f"
exit $fail
