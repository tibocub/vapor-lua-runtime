# vlr: the Vapor Lua Runtime

A small, portable Lua runtime for writing general-purpose programs (the things people write in Python or Node) that
run unchanged on a desktop, in a browser and on a microcontroller. It is to Lua and LuaRocks what
[Bare](https://github.com/holepunchto/bare) is to JavaScript and Node: a small core with optional modules.

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
sh tools/fetch-deps.sh        # clones lfs, lpeg, cjson, vaporUI, Monocypher, BearSSL next to this folder
make                          # builds ./vlr (a few seconds)
./vlr -e 'print("hello from vlr " .. vapor.version)'
make test                     # runs the suite
```

A program that uses the event loop:

```lua
-- ticker.lua
vapor.spawn(function()
  for i = 1, 3 do vapor.sleep(0.5); print("tick", i) end
end)
vapor.spawn(function()
  local c = assert(require("vapor.net").connect("example.org", 80, 5))
  c:write("HEAD / HTTP/1.0\r\nHost: example.org\r\n\r\n")
  print(c:read("l"))
end)
```

```sh
./vlr ticker.lua              # both tasks run side by side; the script ends when nothing is left to wait for
```

## Using it

```
vlr script.lua [args]      run a script
vlr folder [args]          run an app folder (manifest.lua + main.lua, see docs/api.md)
vlr -e 'code'              run a chunk
vlr                        interactive prompt (also: vlr -i)
vlr --dialect=5.4 ...      plain Lua 5.4 instead of the 5.1 dialect
```

The API lives on the global `vapor` table: `vapor.spawn`, `vapor.sleep`, `vapor.pull` (events), `vapor.input`, `vapor.fs`, `vapor.caps`
(what this build and platform can do), and so on. Optional modules load on first use and are `nil` in builds without them.
Reference: [docs/api.md](docs/api.md), networking: [docs/net.md](docs/net.md). More examples: `examples/snake` (a terminal game),
`examples/httpd` (a small web app), and `tests/`, which doubles as executable documentation.

Packages come from [vpm](https://github.com/tibocub/vapor-package-manager): `vpm i lpeg`, `vpm search json --works`.
Where the platform allows it (`vapor.caps.dlopen`), C modules installed by vpm load from `./lua_modules`.

## Building variants

```sh
make MODULES="vapor.fs vapor.input"        # a smaller binary with only some modules (empty = all)
make STATIC=1                              # no dlopen (the old fully static binary)
make TARGET=win32 CC=x86_64-w64-mingw32-gcc    # Windows
make TARGET=web                            # WebAssembly (needs emsdk); see web/
```

More in [docs/building.md](docs/building.md).

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

No license has been chosen yet; until one is added, all rights are reserved by the author. Lua itself is MIT-licensed (`third_party/lua`),
and the sibling projects keep their own licenses.
