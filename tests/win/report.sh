#!/bin/sh
# One command for a Windows machine: builds vlr.exe, runs every automated suite and writes everything to
# reports/windows-<date>.txt (also shown on screen). Run it from the MSYS2 *MinGW64* shell, in the repo root:
#     sh tests/win/report.sh
# It never closes the window by itself: it waits for Enter at the end. See docs/windows-test.md.
cd "$(dirname "$0")/../.." || exit 1
mkdir -p reports
R=reports/windows-$(date +%Y%m%d-%H%M).txt
FAILS=0
step() { # step NAME COMMAND... : run, show the exit status
  echo; echo "== $1"; shift
  "$@"; rc=$?
  echo "-- exit $rc"
  [ "$rc" = 0 ] || FAILS=$((FAILS + 1))
}
need() { command -v "$1" >/dev/null 2>&1 || { echo "MISSING TOOL: $1  (install: $2)"; MISSING=1; }; }

main() {
  echo "vlr Windows report $(date)"
  echo "commit: $(git rev-parse --short HEAD 2>&1) ($(git log -1 --format=%s 2>&1))"
  echo "system: $(uname -a)"
  echo "shell: $MSYSTEM  gcc: $(gcc --version 2>&1 | head -1)  make: $(make --version 2>&1 | head -1)"
  MISSING=
  need gcc "pacman -S mingw-w64-x86_64-gcc"; need make "pacman -S make"; need git "pacman -S git"; need curl "pacman -S curl"; need tar "pacman -S tar"
  if [ -n "$MISSING" ]; then echo "ABORT: install the missing tools in the MinGW64 shell and run again"; return 1; fi

  # the native modules are sibling checkouts of the repo (same pins as .github/workflows/ci.yml)
  [ -d ../luafilesystem ] || { git clone -q https://github.com/lunarmodules/luafilesystem ../luafilesystem && git -C ../luafilesystem checkout -q 146ab458e821cd7617892099fe8e6e399b46185c; }
  [ -d ../lua-cjson ] || { git clone -q https://github.com/mpx/lua-cjson ../lua-cjson && git -C ../lua-cjson checkout -q 718f27293a981fb5e9e662e9aec0b7cf78317da6; }
  [ -d ../lpeg-1.1.0 ] || curl -fsSL https://www.inf.puc-rio.br/~roberto/lpeg/lpeg-1.1.0.tar.gz | tar -xz -C ..
  [ -d ../vaporUI ] && git -C ../vaporUI pull -q --ff-only # we track the latest vaporUI on purpose
  [ -d ../vaporUI ] || git clone -q --depth 1 https://github.com/tibocub/vaporUI ../vaporUI
  [ -d ../Monocypher ] || { git clone -q https://github.com/LoupVaillant/Monocypher ../Monocypher && git -C ../Monocypher checkout -q ab2b16dd619ad5f6979a4fbe69cfa324a6fcc35f; }
  ls -d ../Monocypher ../vaporUI ../luafilesystem ../lua-cjson ../lpeg-1.1.0

  step "build vlr.exe" make TARGET=win32 CC=gcc
  [ -f vlr.exe ] || { echo "ABORT: no vlr.exe, the build failed (see above)"; return 1; }
  echo "vlr.exe: $(./vlr.exe tests/identity.lua && echo identity ok)"
  step "suite (tests/run.sh)" env VLR=./vlr.exe sh tests/run.sh
  step "ConPTY console suite" env VLR=./vlr.exe sh tests/win32/run.sh
  echo; echo "SUMMARY: $FAILS failing step(s). Lines starting with FAIL above say which checks."
}

main 2>&1 | tee "$R"
echo; echo "Report written to $R (commit and push it: git add reports && git commit -m 'Windows report' && git push)"
[ -t 0 ] && { printf 'Press Enter to close... '; read -r _; }
