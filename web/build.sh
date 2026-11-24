#!/bin/sh
# Bundles the wterm page (term.html + dist/): needs bun, and `make TARGET=web` for vlr.js/vlr.wasm first.
# Examples shown with ?example=NAME are copied from the sibling vaporUI checkout (bindings/lua/examples).
cd "$(dirname "$0")" && bun install >/dev/null && bun build term.js --outdir dist --target browser && cp vlr.wasm dist/ || exit 1
for d in ${VAPORUI:-../../vaporUI}/bindings/lua/examples/*/; do
  n=$(basename "$d"); mkdir -p "dist/examples/$n" && cp "$d"*.lua "dist/examples/$n/" || exit 1
  (cd "dist/examples/$n" && printf '[%s]' "$(ls *.lua | sed 's/.*/"&"/' | paste -sd, -)" > files.json)
done
(cd dist/examples && ls -d */ | tr -d /) | paste -sd, - | sed 's/[^,]*/"&"/g; s/^/[/; s/$/]/' > dist/examples/index.json # the list the playground shows
