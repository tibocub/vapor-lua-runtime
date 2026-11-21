# Running real rocks on vlr (2026-11-22)

Method (vpm `tools/libtest/`): build the signed index of the pure-Lua rocks that pass vpm's filter (1,276 plain ones of 5,799 on luarocks.org),
install each with vpm into its own folder, then load every module the rock ships (`require`) in its own `vlr` process inside a bubblewrap sandbox
(no network, read-only system, scratch /tmp, 1 GB / 20 s / 2 MB-file limits), once in the default 5.1 dialect and once with `--dialect=5.4`.
Loading only: this finds missing functions, syntax the dialect cannot parse and missing modules, not wrong behaviour.

## First run (1,276 packages, 4,970 modules)
1,045 packages installed; 3,657 modules loaded in 5.1 (3,656 in 5.4); 683 packages had every module load (54% of all, 65% of the installable ones).
Why the rest failed, in vlr's court (fixed the same day, `tests/compat_libs.lua`): `module()`/`package.seeall` (many older rocks), `math.log10` and the other
5.1 math functions, float arguments (`("x"):sub(1.5)` is an error in 5.4 and was silent truncation in 5.1: patched for the 5.1 dialect only,
`patches/lua-float-args.patch`), no `bit`/`bit32` (about 60 modules), no `cjson.safe`. Re-run on the same packages: +57 modules loading, 0 lost.

Not vlr's to fix (the index should say so instead):
- LuaJIT only (`ffi`, `jit`): about 130 modules. Rocks that `require "ffi"` cannot work on stock Lua.
- Host frameworks: Neovim (`vim`, plenary), OpenResty/Kong (`ngx`, `resty.*`, `kong.*`, and `cjson.decode_array_with_array_mt` from OpenResty's lua-cjson fork), awesome (`awful`).
- Rocks needing their own helpers as globals (`reload`, `import`, `pl`): test runners and framework-style code.
- LuaSocket's companions `mime`, `ltn12`, `socket.http`, `socket.url`: vlr provides `socket` only. Candidates for pure-Lua modules in vlr (ltn12, url, headers, http over our socket).

## Findings about vpm and the index
- 231 packages are in the index but cannot be installed: their sources are archives (dkjson, distilled, luaunit, ...) so entries have no per-file URL. Either vpm learns archives
  (inflate + tar on a 187 KB board: no) or the index host also serves the files (content-addressed blobs next to the index): the second keeps vpm small.
- vpm has no retry/backoff: a 429 or a timeout from a host fails the install. Installing 1,000+ rocks twice in an hour from one address made 24 more fail that way.
- The builder knows `requires` per rock: `ffi`/`ngx`/`vim` etc. should reject or tag at index time.

Failing outcomes are kept as data, not hidden: the libtest results (one line per module) are the input for deciding what the index accepts.
