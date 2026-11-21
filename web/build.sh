#!/bin/sh
# Bundles the wterm page (term.html + dist/): needs bun, and `make TARGET=web` for vlr.js/vlr.wasm first.
cd "$(dirname "$0")" && bun install >/dev/null && bun build term.js --outdir dist --target browser && cp vlr.wasm dist/
