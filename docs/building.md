# Building and testing

## Prerequisites
A C compiler, make, git, curl, tar. `sh tools/fetch-deps.sh` clones the third-party sources the default module set needs
(lfs, lpeg, cjson, vaporUI, ed25519 (vendors Monocypher), BearSSL) next to the repository, at the commits CI uses (vaporUI tracks its latest on purpose).
Lua 5.4.8 itself is in `third_party/lua`, with the small patches in `patches/`.

## Targets
| command | result |
|---|---|
| `make` | `./vlr` for the host (Linux, macOS, BSD); dlopen enabled |
| `make STATIC=1` | same without dlopen (no `.so` loading) |
| `make TARGET=win32 CC=x86_64-w64-mingw32-gcc` | `vlr.exe` (MSYS2 or a cross compiler; tests run under wine) |
| `make TARGET=web` | `web/vlr.js` + `web/vlr.wasm` (emscripten, Asyncify so scripts block like anywhere else; no threads). Under Node use `--liftoff-only`: V8's tier-up stalls the first sleep for about a second |
| NuttX | built from the vaporOS repository, which includes this one (Kconfig chooses modules per board) |

## Choosing modules
`modules.conf` lists every module and what it is built from. `make MODULES="lfs cjson"` builds only those (empty means all).
`tools/vlr-build profile` does the same from a small profile file (`tools/mini.vlrprofile`); `tools/vlr-build --list` shows the names.
Sizes by module set are in spec.md (a stripped build with only `lfs` is about 274 KB, everything about 1 MB).

## Adding C modules to a build
- One rock from its rockspec: `tools/vlr-build add-rock ROCKSPEC SRCDIR [--write]` (builtin-type rockspecs only).
- Several rocks fetched and hash-checked by vpm: `vpm bundle lpeg lbase64 --dir=D`, then `make CONF_EXTRA=D/bundle.conf`.
- Rocks that load as `.so` need no rebuild: `vpm i` builds them (in a sandbox) and vlr finds them on `./lua_modules`.
The C API a module may use is Lua's public one, including the 5.1 names (`lauxlib.h` carries the shim, `patches/lua-api51.patch`).

## Tests
- `make test` (or `sh tests/run.sh`): every `tests/*.lua`, each in the normal loop and in `--step` mode (loop driven from C like a browser host), plus the app, pty, rock, dynamic and TLS suites.
  `VLR="wine ./vlr.exe" sh tests/run.sh` and `VLR="node --liftoff-only web/run.mjs" sh tests/run.sh` run it on other targets.
- `make check` (Linux, clang): strict `-std=c99 -pedantic -Werror` on our own code, then the suite under ASan and UBSan. Run `make clean` afterwards, or sanitizer objects leak into the normal build.
- After regenerating `lua/luaheaders.lua` (`make headers`), build twice.
- Hands-on only: [windows-test.md](windows-test.md) (real console), [tty-test.md](tty-test.md) (Linux virtual terminal).
- CI (`.github/workflows/ci.yml`): Linux and macOS, Windows (MSYS2), WebAssembly.
