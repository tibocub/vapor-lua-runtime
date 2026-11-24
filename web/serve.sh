#!/bin/sh
# Serves this folder (needs web/vlr.js + vlr.wasm from `make TARGET=web` and dist/ from build.sh). Pages:
#   http://localhost:8765/index.html                    playground
#   http://localhost:8765/term.html                     terminal, vaporui events demo
#   http://localhost:8765/term.html?example=snake       snake
cd "$(dirname "$0")" || exit 1
for f in vlr.js vlr.wasm dist/term.js index.html; do [ -e "$f" ] || { echo "missing web/$f: run make TARGET=web web/vlr.js and sh web/build.sh first"; exit 1; }; done
exec python3 -m http.server 8765
