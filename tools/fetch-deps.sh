#!/bin/sh
# Clones the sibling checkouts the default module set is built from, next to this repository (modules.conf, make EXT=..), at the commits CI uses.
# Idempotent: a folder that exists is left alone. Needs git, curl and tar.
#   sh tools/fetch-deps.sh [PARENT_DIR]      (default: the folder containing this repository)
set -e
here=$(cd "$(dirname "$0")/.." && pwd)
parent=${1:-$(dirname "$here")}
clone() { # name url [commit]
  [ -d "$parent/$1" ] && { echo "have $1"; return; }
  if [ -n "$3" ]; then git clone -q "$2" "$parent/$1" && git -C "$parent/$1" checkout -q "$3"; else git clone -q --depth 1 "$2" "$parent/$1"; fi
  echo "cloned $1"
}
clone luafilesystem https://github.com/lunarmodules/luafilesystem 146ab458e821cd7617892099fe8e6e399b46185c
clone lua-cjson https://github.com/mpx/lua-cjson 718f27293a981fb5e9e662e9aec0b7cf78317da6
clone vaporUI https://github.com/tibocub/vaporUI        # tracks the latest on purpose: vlr and vaporUI evolve together
clone Monocypher https://github.com/LoupVaillant/Monocypher ab2b16dd619ad5f6979a4fbe69cfa324a6fcc35f
clone BearSSL https://www.bearssl.org/git/BearSSL 7bea48e5e850ab4cafbe68d3765cdaba13a86d6f
if [ ! -d "$parent/lpeg-1.1.0" ]; then curl -fsSL https://www.inf.puc-rio.br/~roberto/lpeg/lpeg-1.1.0.tar.gz | tar -xz -C "$parent"; echo "fetched lpeg-1.1.0"; else echo "have lpeg-1.1.0"; fi
