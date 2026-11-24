# vlr: the Vapor Lua Runtime

A small Lua runtime for the places where stock Lua cannot build or load C libraries: the browser (WebAssembly), microcontrollers
(NuttX, RP2040) and single static binaries. Libraries such as lfs, lpeg and cjson are compiled into the runtime and behave exactly as
if they had been installed from LuaRocks, so a program written for them runs unchanged on stock Lua, LuaJIT and vlr.
On a desktop vlr is supported but optional: plain `lua` or `luajit` plus [vpm](https://github.com/tibocub/vapor-package-manager) is the intended setup.

**The rule:** code that runs on vlr must also run on official Lua. vlr adds no syntax and aims to add no API of its own: it provides
the libraries people already use (`lfs`, `lpeg`, `cjson`, `socket`, `ssl`, `copas`, `ed25519`, `vaporui`, ...) under their usual names.
There is no `vapor` global and no `std` library; `require("vlr")` is the runtime's own internals (scheduler, `vlr.net`, `vlr.tls`, ...)
and portable code does not use it.

"vlr" is a working name.

**Status: version 0.2, usable, API partly experimental.** Runs the same test suite on Linux, macOS, Windows and WebAssembly
(CI), and on the NuttX simulator and the RP2040 (checked by hand). See [docs/status.md](docs/status.md) for exactly what is
verified and what is not.

## What you get

- Lua 5.4 engine with a **Lua 5.1 dialect by default** (most of the Lua ecosystem targets 5.1); `--dialect=5.4` switches to plain 5.4.
- One cooperative event loop: tasks (coroutines), timers, file-descriptor waits, input events. Nothing blocks the process, so the
  same program also runs in a browser, which cannot block.
- Optional modules, chosen per build: files, console input (keys, mouse, resize), a cell-grid screen, TCP/UDP, TLS (BearSSL), HTTP client
  and server, a LuaSocket-compatible `socket`, ed25519 signature checks. Bundled C libraries: lfs, lpeg, cjson.
- C Lua modules from LuaRocks load as `.so` files or compile into the binary, with no source changes.
- Targets: Linux, macOS, BSD (POSIX), Windows, WebAssembly (Node and browser), NuttX (including the RP2040, about 190 KB of RAM).
- [vpm](https://github.com/tibocub/vapor-package-manager) is the package manager for it (also usable with any Lua).

## Quickstart

Needs a C compiler, make, git, curl and tar.

```sh
git clone https://github.com/tibocub/vapor-lua-runtime vlr && cd vlr
sh tools/fetch-deps.sh        # clones lfs, lpeg, cjson, vaporUI, ed25519, BearSSL next to this folder
make                          # builds ./vlr (a few seconds)
./vlr -e 'print(_VERSION)'
make test                     # runs the suite
```

After `vpm i copas`, a program written for luasocket and copas runs unchanged:

```lua
local copas = require("copas")
local http = require("copas.http")
copas.addthread(function() print((http.request("http://example.org/"))) end)
copas.loop()
```

## Using it

```
vlr script.lua [args]      run a script
vlr -e 'code'              run a chunk
vlr                        interactive prompt (also: vlr -i)
vlr --dialect=5.4 ...      plain Lua 5.4 instead of the 5.1 dialect
```

Libraries (`lfs`, `socket`, `ssl`, `cjson`, `lpeg`, `vaporui`, ...) are used exactly as with stock Lua. The runtime's own internals
(`require("vlr")`: scheduler, `vlr.net`, `vlr.tls`) are documented in [docs/api.md](docs/api.md) for people working on vlr; networking: [docs/net.md](docs/net.md).
`tests/` doubles as executable documentation.

Packages come from [vpm](https://github.com/tibocub/vapor-package-manager): `vpm i lpeg`, `vpm search json --works`.
Where the platform allows it (when `package.loadlib` can load shared objects), C modules installed by vpm load from the `./lua_modules` luarocks tree.

## Building variants

```sh
make MODULES="lfs cjson"             # a smaller binary with only some modules (empty = all)
make STATIC=1                                   # no dlopen (the old fully static binary)
make TARGET=win32 CC=x86_64-w64-mingw32-gcc     # Windows
make TARGET=web                                 # WebAssembly (needs emsdk); see web/
```

More in [docs/building.md](docs/building.md).


## How it relates to other runtimes

| Runtime | Relation |
|---|---|
| PUC Lua 5.1-5.4, LuaJIT | The reference. Anything portable runs there too; vlr exists for the targets they do not reach (WASM, NuttX, RP2040) and to bundle native libraries into one binary. |
| [Luvit](https://github.com/luvit/luvit), [Evo](https://github.com/evo-lua/evo-runtime), [Ulua](https://github.com/uluadist/ulua) | Desktop runtimes with their own APIs (libuv). vlr does not compete with them on the desktop and does not copy their APIs: its goal is to stay interchangeable with stock Lua. |

Lua version: the default dialect is 5.1 (what PUC 5.1 and LuaJIT accept) on the Lua 5.4 engine; `--dialect=5.4` switches to plain 5.4. A program
picks one version, like a LuaRocks package (`lua >= 5.1` in its rockspec); versions are never mixed in one process.

## Repository layout

```
src/        C: core, platform backends (posix, win32, wasm), native modules
lua/        Lua modules embedded into the binary (scheduler, net, http, tls glue, ...)
third_party/ Lua 5.4.8 with a few documented patches (patches/)
modules.conf which modules exist and what they are built from
tests/      the conformance suite, run unchanged on every target (tests/run.sh)
tools/      build helpers (vlr-build, header and module generators)
web/        browser build, playground and terminal page
docs/       documentation
```

## Documentation

[docs/README.md](docs/README.md) is the index. Start with [status](docs/status.md) (what works today),
[architecture](docs/architecture.md) (how it is built) and [roadmap](docs/roadmap.md) (where it is going).

## Contributing

Run `make test` and, on Linux with clang, `make check` (strict warnings, ASan and UBSan) before sending a change. The core is portable C99
with no OS headers (everything OS-specific goes through `include/vlr_platform.h`); a new platform means one backend file. Tests are Lua scripts
in `tests/` and must pass in both the normal and the `--step` loop mode. CI runs Linux, macOS, Windows and WebAssembly.

## License

MIT
