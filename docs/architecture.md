# Architecture

## Layers
```
apps and Lua rocks (installed with vpm)      Lua, loaded from files
the `vlr` internals (require("vlr")), embedded Lua modules     lua/*.lua, embedded in the binary, loaded on require
native modules (vlr.netraw, vlr.tlsraw, ...; lfs, lpeg, cjson; C rocks)   src/mod_*.c, third_party, rocks
core: Lua 5.4.8, scheduler glue, identity    src/vlr.c, src/main.c: portable C99, no OS headers
platform backend                             one file per target: platform_posix.c, platform_win32.c, platform_wasm.c (+ net_*.c)
```
The core never includes an OS header; everything OS-specific goes through `include/vlr_platform.h` (clock, wait on handles, console, filesystem,
exec, networking, name resolution). NuttX uses the POSIX backend. A new target is one backend file.

## Event loop
A program is a coroutine run by the scheduler (`lua/sched.lua`). `vlr.pull`, `vlr.sleep`, `wait_fd`, socket reads and console reads all
suspend only the calling task; the one real wait (`vlr_wait`) happens in `vlr.run`. A host that owns the main loop (browser, GUI) drives it with
`vlr.step`. This is the only model every target can implement, because a browser cannot block. The test suite runs every test in both modes.

## Modules
- `modules.conf` declares each module: name, `luaopen_` symbol or `lua:` file, sources, flags. `tools/mkmodules` generates `vlr_modules.c`
  (a `package.preload` table); `@PLAT@`, `@EXT@`, `@VLR@` select the platform half and locate sources.
- `vlr.builtin` lists what is compiled in,
  so a package manager can see what a device already satisfies.
- Native modules use only Lua's public C API, so one source builds statically (the only way on NuttX, wasm, Windows) or as a `.so` (posix, `caps.dlopen`).
  `lauxlib.h` adds the Lua 5.1 API names (`luaL_register`, `lua_objlen`, ...) so 5.1-era rocks compile unchanged. Name clashes between a rock's `luaopen_`
  symbol and Lua's own are renamed at build time, not in the rock.
- `vlr.luaheaders` embeds Lua's headers so a compiler can build a module against exactly this runtime.

## Dialects
The engine is PUC 5.4 with 64-bit integers. By default a compat layer (`lua/compat.lua` plus a C patch for number printing) gives Lua 5.1 behaviour
(`unpack`, `loadstring`, `setfenv`, `table.getn`, `5.0` prints as `5`), because most LuaRocks packages target 5.1. `--dialect=5.4` is plain 5.4. The compat layer costs about 4 KB of heap.

## Networking and TLS
`vlr.netraw` (C, non-blocking handles that `vlr_wait` understands) under `vlr.stream` and `vlr.net` (Lua). `vlr.tlsraw` is BearSSL as an I/O-free engine;
`lua/tls.lua` moves bytes between it and a socket so waiting stays in the scheduler. Another backend only has to offer the same small call set. Details: [net.md](net.md).

## Input and UI
Terminal bytes are decoded by vaporUI's pure C decoder (a sibling checkout); Windows reads native console records; a Linux VT can use raw keycodes. All produce the same
`vlr.pull` events. `vlr.ui` exposes vaporUI's double-buffered cell grid for drawing; the browser page feeds the same events through `vlr.event`.

## Why it is shaped this way
Portable, lightweight, modern, modular, generalist: one program, same behaviour on a microcontroller and in a browser, without libuv, a mandatory JIT or mandatory
dynamic linking. Decisions with dates and measurements are in [spec.md](spec.md).
