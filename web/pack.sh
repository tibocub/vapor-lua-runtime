#!/bin/sh
# pack.sh DIR: the static site (GitHub Pages) = the pages, the runtime and dist/. Run make TARGET=web web/vlr.js and build.sh first.
set -e
out=${1:?usage: pack.sh DIR}
cd "$(dirname "$0")"
mkdir -p "$out"
cp index.html term.html vlr.js vlr.wasm vlr-glue.js "$out"/
cp -r dist "$out"/
