# vlr: portable Lua runtime (vapor lua runtime)

Status (2026-11-21): **working runtime, version 0.2.** Runs the same conformance suite on Linux, Windows (including a real
Windows pseudo-console suite), the browser (WASM, Node and Firefox), the NuttX simulator and the RP2040. Started 2026-11-19; extends
and replaces `vlua` (vaporOS/vlua, which was a draft). Sections below that describe design are still the intent; the per-target
sections at the end record what was measured. Direction and decisions: "Vision and decisions" right below.

## Vision and decisions

**What it is.** A lightweight, portable Lua runtime: a middle ground between uxn and the JVM, a lightweight Luvit. For programmers who
want portable software and a generalist language (Python/Node use cases) without hundreds of MB of RAM. Design tests: Portable,
Lightweight, Modern, Modular, Generalist. Example target: a vim-like editor on vaporUI that runs unchanged in a terminal, a desktop
window and the browser. vlr is to Lua and LuaRocks what [Bare](https://github.com/holepunchto/bare) is to JavaScript and Node: a small
core with optional modules.

**Decided (2026-11-21, design interview):**

1. **Core vs modules.** Core: Lua, the scheduler, the event queue, timers, the console. `vapor.fs`, `vapor.net`, `vapor.gfx`, workers and
   the `std` helpers are optional modules, each with its backend part and the targets it supports. The global `vapor` is a lazy facade
   that loads a module on first access; `require("vapor.fs")` also works.
2. `vapor.*` stays minimal: only what plain Lua cannot do. `std.*` is optional pure-Lua batteries that a small build leaves out.
3. **Ecosystem.** C Lua libraries (5.1 to 5.4 API) compile in without source changes. `vlr-build` reads LuaRocks rockspecs to add
   native modules (`modules.conf` becomes the generated lock). The real `luarocks` should run on desktop vlr; vpm stays the preferred CLI
   and the on-device tool.
4. **Apps** are loose scripts plus a manifest (name, version, needed `vapor.caps`, needed built-in modules, entry point). No single-file
   bundle format yet.
5. **Parallelism.** One primitive: an optional `vapor.worker(file)` (isolated Lua state, own scheduler, copied-value messages; pthread,
   Windows thread, Web Worker), plus subprocess spawn with pipes on desktops. No shared-memory threads. Reported in `vapor.caps`.
6. **UI.** vaporUI keeps one cell-grid model with output surfaces: terminal, framebuffer cell-renderer (SDL window, `/dev/fb`, web
   canvas), shared bitmap font. `vapor.gfx` is a separate low-level pixel surface, only when a program needs it. Image and video
   rendering in the terminal (ASCII, half-blocks, Sixel/Kitty) is a later optional module.
7. **Security.** The default is trusted, like Node. A tiered security milestone is studied and planned when we reach it (text-only
   `load` by default, memory and instruction limits, an opt-in sandbox, manifest-declared capabilities, TLS verification). Hostile code
   needs a separate process or the WASM build; the docs will say so.
8. **API stability.** Version 0.2 freezes the core names (`pull`, `sleep`, `wait_fd`, `step`, `input`, `fs`, `caps`, `version`,
   `builtin`, `platform`) after the module split. New areas start experimental and graduate after real use. Semantic versioning on
   `vapor.version`. The 5.1-compatible dialect stays the default for the life of the project; plain 5.4 is opt-in.
9. **Targets.** Done: Linux, Windows, WASM, NuttX sim, RP2040. Next: macOS through CI. No native Android or iOS: mobile goes through
   HyperBrowser if the WASM build performs well. Embedding in HyperBrowser waits for WASM performance numbers.
10. **vlua** is replaced by vlr in vaporOS once vlr is no heavier on the RP2040 than vlua.

**Milestones from here:** M1 housekeeping (this spec, `docs/api.md`, CI, RP2040 heap gap); M2 module system and 0.2 freeze; M3 networking
as the first real module; M4 vaporUI framebuffer renderer; M5 workers, then running `luarocks`. Parked: security tier, terminal images,
`.vlb` bytecode, LuaJIT, single-file bundles.

## Goal (original, kept for the record)

One Lua program, same behaviour on NuttX (RP2040 first), Linux/macOS/Windows and the browser (WASM), compatible with the LuaRocks
ecosystem (pure Lua; C rocks are compiled in). No libuv, no mandatory JIT, no mandatory dynamic linking.

## Layers

```
apps + pure-Lua rocks (vpm)          dynamic
vapor.* API  +  C modules (lfs...)   core: portable C99, no OS headers
platform backend                     1 C file per target: nuttx, posix, win32, sdl, wasm
```

Rules for the core (Doom/uxn style, so a port is a weekend, not a project):

- **Core never includes an OS header.** Everything OS-specific goes through `vlr_platform.h`.
- Plain C99, no threads, no `fork`, no signals, no assumption of `malloc` (allocator is injected), no required stdio.
- Compiles clean with `-std=c99 -pedantic`; a size budget is tracked per target (flash and RAM of an empty state).

## Execution model: one event queue

- A program is a coroutine run by the scheduler. It never blocks the process.
- `vapor.pull(timeout) -> ev, ...` yields until an event or the timeout (ComputerCraft's `os.pullEvent`).
- `vapor.sleep(s)`, sockets, `io.read` on stdin and timers are built on it by the scheduler (a coroutine-aware
  wrapper), so plain scripts still look blocking and just work.
- Events are `(name, a, b, c)` tuples: `key`, `char`, `mouse`, `resize`, `timer`, `readable`, `writable`, `quit`.
- Why: the browser cannot block, so blocking-inside-the-loop is not portable; this model is the only one all
  targets can implement. No Asyncify, no threads.

## Platform interface (`vlr_platform.h`), the whole porting surface

Required (small on purpose, target < 15 functions):

| function | meaning |
|---|---|
| `vlr_now_ms()` | monotonic clock |
| `vlr_wait(fds, n, timeout_ms)` | block until an fd is ready, input arrives or timeout; on wasm it returns to the host and resumes on the next host event |
| `vlr_poll_event(ev)` | next input event (key, mouse, resize), non-blocking |
| `vlr_stdio_*` | raw console in/out |
| `vlr_fs_*` | list, mkdir, rmdir, stat (what plain Lua lacks; `os.remove` cannot delete directories on Windows) |
| `vlr_net_*` | optional (caps) |
| `vlr_gfx_*`, `vlr_audio_*` | optional (caps); reuse vaporUI backends where possible |

`vapor.caps` is a table of booleans (`fs`, `net`, `gfx`, `audio`, `tty`, `gpio`...) so an app can degrade.

## Native modules: static always, dynamic where the OS allows

Two ways to get the same `require("lfs")`:

1. **Static (always available).** `modules.conf` (declarative, one line per module: name, source dir, `luaopen_`
   symbol, flags, targets) generates `vlr_modules.c`, a `package.preload` table. A target selects modules;
   unselected ones cost nothing. This is the only way on NuttX.
2. **Dynamic (capability `dlopen`).** Where the platform has it, `package.cpath` loads `.so`/`.dylib`/`.dll`.
   The backend provides `vlr_dlopen/dlsym`; without it the loader is simply absent.

Constraint that makes both work: **a native module is written against the public Lua C API only** (`lua.h`,
`lauxlib.h`, no internal headers, no globals shared with the runtime), so one source builds either way.
Lookup order: preload, then `package.path`, then `package.cpath` (if enabled).

## Who manages native modules: two tools, one record format

- **`vlr-build` (host, build time, needs a compiler).** Reads `modules.conf`, compiles the chosen C modules into the
  runtime and writes, for each one, a **stub record** in the image: `<libdir>/vlr/builtin/<name>.lua` with
  `{name, version, provides, abi, source="builtin"}`. It also fills `profile.native`. This is where built-in
  libraries (lfs, cjson...) are added or removed; it never runs on a device.
- **`vpm` (on device, no compiler needed for built-ins).** Treats builtin records as *installed, pinned, not
  removable* packages. The resolver needs no special case: a dependency on `lfs >= 1.8` is satisfied by the stub or
  is a plain unsatisfied dependency. Same for packages vpm itself installed.
- **Dynamic native modules (`caps.dlopen`).** vpm installs `.so/.dylib/.dll` into the same state database as any
  package, with `kind="native"` and an **ABI tag** `engine-dialect-platform` (e.g. `puc54-linux-x86_64`,
  `luajit-macos-arm64`). A binary is only offered if its tag matches `profile.abi`; otherwise vpm builds it from
  source if a compiler exists, or hides it with the reason.
- **Conflicts:** a builtin module always wins over a dynamic copy of the same name (two copies of one library in one
  process cause symbol and state clashes). vpm refuses the install unless asked to shadow it explicitly.

Records are written by `vlr-build` and by vpm in one format, so `vpm list` shows built-in and installed packages
together and `vpm why` explains either.

## Optional JIT: one dialect that runs on both engines

**Priority: low.** Performance is designed around Lua glue + native modules (the JIT is never assumed: it cannot run
on RP2040/ESP32-class chips, iOS or wasm). LuaJIT is a late desktop bonus: it must not shape the API or block a
milestone. If the dialect rule below ever costs more than it gains, drop the rule, not the other way round.

LuaJIT is Lua 5.1 semantics; PUC 5.4 has integers, `//`, bit operators, `goto`, `<const>`. "Same code with or
without the JIT" therefore means programs must stay in the **intersection**: this is a decision, see open questions.
Proposed:

- The portable dialect is **5.1-compatible code that also runs on 5.4** (this is also what most LuaRocks rocks
  already are, `lua >= 5.1`, so ecosystem compatibility is a plus, not a cost).
- No FFI in portable code; no reliance on the integer/float distinction, `//`, `&`/`|`, `goto`; bit operations
  through a provided `bit` module (the LuaJIT `bit` API, implemented on 5.4 by a tiny C module).
- The conformance suite runs on **both** engines; engine is a build option (`ENGINE=puc|luajit`) and
  `vapor.runtime.engine` / `.jit` report it.
- Programs that want 5.4 features may declare `vlr.dialect = "5.4"` and are then not offered on JIT builds.
  Tension with vlua's 64-bit-integer decision: kept for the PUC engine, just not relied upon by portable code.

## Device awareness (profile) and vpm

Each build emits a **profile** (generated, read-only, e.g. `/lib/vlr/profile.lua`, also `vapor.runtime`):

```lua
{ runtime = "0.1", engine = "puc", jit = false, dialect = "5.1+",
  caps = { fs=true, net=true, gfx=false, dlopen=false, ... },
  native = { lfs="1.8.0", lpeg="1.1.0", cjson="2.1.0" } }   -- compiled-in modules
```

vpm uses it to decide what it may offer. A rock/program is installable when **any** holds:

1. pure Lua (dialect compatible with the engine), no native dependency;
2. every native dependency is in `profile.native` (at an acceptable version);
3. `caps.dlopen` and the rock ships/builds a native binary for this platform (opt-in, Linux first).

So the same index serves a RP2040 (case 1-2 only) and a Linux laptop (also case 3). vpm says why something is
hidden ("needs native `luasocket`, not built into this runtime"). This extends vpm's current "pure Lua only" goal
(vpm/README) rather than replacing it.

## What is pinned

- Engine: PUC Lua 5.4.x (currently 5.4.8), 64-bit integers and floats on every target (see lua-runtime.md:
  32-bit is not faster for floats and breaks semantics). Optional LuaJIT engine, see above.
- Distribution format is **source**. Bytecode is an optional trusted-only artifact (`.vlb`): a fixed format
  (little-endian, 64-bit integers/doubles, version and engine tag) written and read by our own dump/undump so it is
  identical on every target. Never loaded from untrusted input (Lua has no bytecode verifier: crafted bytecode can
  crash or exploit the VM). Gains: no parse step and no compiler RAM at load (lpeg's suite did not fit on the RP2040
  to compile); it does **not** make the VM execute faster. A new VM is not planned: see the discussion in the
  open questions.
- Paths use `/` in the API on every target; the Windows backend translates.
- No `fork`, no signals, no threads in the API.

## Sandbox (needed for HyperBrowser, optional elsewhere)

`vlr_new(opts)`: memory cap (custom allocator), instruction limit (count hook), `_ENV` whitelist, capability list.
Untrusted code gets only what the host grants.

## Native code in WASM (deferred, third option next to static and dlopen)

Compare native vs wasm3/wamr for lpeg and cjson on sim and RP2040 (size, min RAM, time) before deciding. Expect:
WASM modules not viable on 187 KB RAM (64 KiB pages), possible on ESP32-S3 with PSRAM.

## Conformance suite

`tests/` is Lua, runs unchanged on every target, and tests the `vapor.*` contract (events, timers, fs, caps, limits),
not only Lua. A target is "supported" when it passes. Known per-target skips are listed in the test, not hidden.

## Targets and backends

| target | backend | state |
|---|---|---|
| Linux, macOS, BSD | `platform_posix.c` | Linux done; macOS/BSD untested (CI next) |
| Windows | `platform_win32.c` | done, real-console suite in `tests/win32` |
| browser, Node | `platform_wasm.c` (+ posix parts) | done, no Asyncify |
| NuttX sim, RP2040 | `platform_posix.c` (NuttX is POSIX) | done |

## Open questions

- Own bytecode VM (instead of PUC 5.4 + patches)? Not now: revisit only if measurements show PUC's speed or RAM is
  the blocker. Possible later wins that do not need a new VM: `.vlb` (above), and executing protos in place from
  flash on RP2040 (NodeMCU's LFS does this).
- **Dialect decision:** accept the 5.1-compatible intersection for portable code (my recommendation), or drop
  "same code on LuaJIT" and keep JIT out of scope?
- Dynamic modules on Linux: prebuilt binaries per platform, or build from source on install (needs a compiler)?
- Name, and whether this lives in vaporOS or stays separate (leaning separate: vaporOS depends on it).
- `vapor.pull` event names for gamepad/touch/IME.
- Is `vlr_wait` plus `vlr_poll_event` one call? (decide while writing the posix backend)
- Does `io.read` on stdin get coroutine-wrapped, or only `vapor.read`?

## Status (2026-11-20)

Backends passing the same suite (`tests/*.lua`, each in normal and `--step` mode): Linux (posix), Windows (mingw
under wine), WASM (emscripten under Node, no Asyncify), NuttX simulator (vaporOS `sim-vlr`, via the posix backend
unchanged). RP2040-Zero (vaporOS `rp2040-vlr`, flashed 2026-11-20): `sched`, `events`, `compat51`, `dialect54`, `modules`, `exec`, `exec54` pass; `fs` passes from a writable directory (from `/`, a pseudo-filesystem, creating files fails by design). `fd` not run on the board (needs console input). Browser (`make TARGET=web`, 373 KB wasm + 194 KB glue JS): the suite passes under Node (`VLR="node web/run.mjs" sh tests/run.sh`) and the playground page `web/index.html` ran a script with sleeps and console input in headless Firefox (output and `io.read` after `vapor.wait_fd(0)` verified). Not yet run: real Windows, a browser with a person typing, wterm.

Measured (build only, no board connected): RP2040 image text size, `arm-none-eabi-size`:

| image | text | bss |
|---|---|---|
| vaporOS `rp2040-vlr` (vlr, lfs+lpeg+cjson) | 645196 | 15064 |
| vaporOS `rp2040-zero` (vlua, lfs+lpeg+cjson+vsign) | 686172 | 18016 |

Not a fair comparison yet: vlua's image also has vsign (ed25519); vlr has the scheduler and fs API instead. Heap
and stack on the board are unmeasured.

RP2040 heap: `free` after 20 runs of `events.lua` grew by 200 bytes (no leak); peak used 120 KB of 244 KB during the suite.

`os.execute` is `vlr_exec` in the platform interface: `system()` on POSIX/Windows, `vaporshell -c` on NuttX (works on the sim and the RP2040), unavailable on wasm (`vapor.caps.exec` false).

NuttX quirks found: no `system()` here (hence `vlr_exec`), `environ` is a macro from `<stdlib.h>` (not linkable), and `stat(".")` fails
(a relative "." is not resolved), so tests and modules must use real paths.

## RP2040 measurements (2026-11-20, `rp2040-vlr` image, GC 100/400, `tools/measure.lua`)

Board: 243,896 B heap total; `free` at the prompt (vaporshell running): 66 KB used, 177 KB free, **largest free block 129 KB**.

| what | result |
|---|---|
| flash cost of vlr (object sizes, before link GC) | 140.8 KB text: Lua 104.6, lpeg 15.2, cjson 8.1, embedded scheduler+compat sources 6.4, lfs 3.5, core+platform 3.0 (22% of the 645 KB image) |
| Lua heap of a one-line script | 30.9 KB (vlua's empty state: 16.7 KB; the extra is the scheduler and compat code kept as Lua functions) |
| per module after `require` | lfs 1.4 KB, lpeg 1.9 KB, cjson 1.8 KB |
| coroutine / parked vlr task | 0.88 KB / 1.23 KB each |
| 1000 integers in a table | 16.4 KB |
| `fib(23)` | 0.4 s (vlua 0.36 s) |
| 300k integer-loop steps | 2.1 s (vlua 2.43 s) |
| 20k `math.sin` | 2.2 s (vlua: 7.4 s for 60k) |
| 1000 `string.format` + concat | 1.7 s |
| sort 1000 numbers | 0.1 s |
| 500 small tables | 0.9 s (GC 100/400 cost) |
| `pcall` nesting | 37 levels reached (limit 40) |
| Lua recursion depth before "not enough memory" | about 1400 frames (desktop: 200000) |
| largest script that compiles | 20 KB of dense source fits, 40 KB does not (a real file with longer lines uses less memory per byte) |
| timer granularity | `sleep(0.01)` takes ~20 ms, `sleep(0.1)` takes ~110 ms: NuttX 10 ms tick |
| leak check | 20 runs of `events.lua`: +200 bytes of heap |

Reading: the interpreter speed equals vlua's (same VM). The limits that bite are heap (about 130 KB contiguous for
a script's data, and about 1400 Lua frames), compile memory (about 20-30 KB of source per file) and timer resolution.
Not measured: stack high-water mark (`ps` STACK/USED), the 6x string-benchmark slowdown from GC 100/400 on this exact
image, and a larger-script comparison between source and bytecode.

## Browser build (`make TARGET=web`)

`web/vlr.js` + `web/vlr.wasm`: an ES module factory `createVlr()`. `web/vlr-glue.js` (`startVlr`) puts files in MEMFS, calls main, and
feeds stdin; `web/index.html` is a playground (editor, dialect choice, output, input line). Serve `web/` with any static server.
No Asyncify and no threads: the loop is driven by JS timers calling `vlr_step`; input calls `vlr_wasm_wake`.
Stdin rule: scripts wait with `vapor.wait_fd(0)` and then read; a read on an empty buffer returns EOF (a browser cannot block).
`os.execute` is unavailable there (`vapor.caps.exec == false`). Each Run creates a fresh instance (one Lua state per run).
Limits: output is line-buffered by emscripten (`vlr_flush` pushes a partial last line at exit); no keyboard/mouse/resize
events yet (that is the next milestone), no wterm yet (plain `<pre>`).

## Input events (`vapor.input`)

`vapor.input(true | {mouse = 0|1|2})` puts the console in raw mode and delivers `vapor.pull` events: `char, text`;
`key, name, mods` (1 shift, 2 alt, 4 ctrl); `mouse, action, button, x, y, mods` (press, release, drag, move, scroll_up/down; 1-based);
`resize, cols, rows`; `quit` at end of input. `vapor.input(false)` (or exit, via a gc guard) restores the terminal.
Bytes are decoded by vaporUI's decoder (`../vaporUI/src/input.c`, vt.c, utf8.c, scancode.c; a sibling checkout like lfs, tracking its latest version on purpose; replaced `src/vtinput.c`; adds kitty, modifyOtherKeys, bracketed paste, base/scancode; +24 KB on the host build, matters for RP2040). The old description (pure C: UTF-8, CSI/SS3 keys with modifiers, Shift+Tab, Alt+key, SGR mouse, split sequences,
lone-ESC after 25 ms). The platform adds `vlr_console_read/raw/size`. Windows uses VT input mode (same decoder).
Web: the page pushes the same events via `vlr.event(...)` / `attachEvents(el, vlr, cell)` in `web/vlr-glue.js`.
The playground (`web/index.html`) makes the output pane the console: click it to focus, then keys, mouse, wheel and pane resizes reach the script ("Events demo" button). The wheel goes to the script only while the pane has focus.
Tests: `tests/decode.lua` (decoder), `tests/pty/run.py` (real pty: keys, mouse, ESC, resize), `web/ev-test.mjs` (page path).
Shortcuts: resize is polled every 250 ms on native targets; Windows console path is untested under wine (no real console).
Also: `VLR_STRIP_INTERNAL` strips debug info from our own Lua (heap -3.4 KB on host); Kconfig `VAPOROS_VLR_STRIP_INTERNAL` (default y).

### RP2040 re-check with input events (2026-11-21)

Image rebuilt with vtinput, `vapor.input` and `VLR_STRIP_INTERNAL=1`; flashed. `decode`, `sched`, `events`, `compat51`, `dialect54`
(with `--dialect=5.4`) pass on the board. Strip confirmed active (`debug.getinfo(vapor.sleep, "L")` has 0 active lines vs 5 unstripped).
Real console path over USB CDC: `vapor.input(true)` received a char, an Up arrow and an SGR mouse press typed from the host
(`EV char,a / key,up,0 / mouse,press,1,5,6,0`). Lua heap at start of a script: 31.8 KB (before/after the strip not measured on the board;
host: 40.5 -> 37.0 KB). Also passing on the board afterwards: `fs` (from /flash), `exec`, `exec54`, `modules`, `fd` (needs `< /dev/null`: a console is never readable), and lfs's own suite (`Ok!`, needs `/tmp`: `mkdir /tmp` first). The stale corrupted `/flash/t` entry is gone.

### Browser terminal (wterm)

`web/term.html` + `web/term.js` (bundle with `web/build.sh`, needs bun): vlr in a wterm terminal. stdout bytes go to the terminal;
its output bytes are the stdin queue and the escape sequences `vapor.input()` decodes (wasm `vlr_console_read` reads `Module.vlrIn`), so keys,
mouse and resize behave as on a native tty; resize goes through `vlr.resize`. `?script=<url>` loads a script, `?dialect=5.4` selects plain 5.4.
Verified: output renders in headless Firefox, byte-level input path in Node (`web/ev-test.mjs`); typing into wterm itself not tried by hand.

## Identity and build profiles

`vapor.version`, `vapor.platform` (linux, windows, macos, nuttx, wasm, posix) and `vapor.builtin` (set of compiled-in module names, generated
with the registry) let a package manager see what the device already satisfies; `tests/identity.lua` keeps `vapor.builtin` and
`package.preload` in sync. `tools/vlr-build [profile]` builds a vlr with a chosen module set for a target from a small `key = value`
profile (`tools/mini.vlrprofile`: posix, lfs only: 324 KB vs 395 KB with everything); `--list` shows the modules in `modules.conf`.
Not built yet: the vpm side (a device-aware resolver that reads `vapor.builtin` and asks `vlr-build` for missing native modules).

## Dynamic modules (optional)

Since 2026-11-22 the posix host build has dlopen by default (`LUA_USE_DLOPEN`, links `-ldl -Wl,-E`, `vapor.caps.dlopen == true`): `require` also finds `.so` files on `package.cpath`,
which is how vpm loads the C rocks it builds. `make STATIC=1` gives the old static binary. NuttX, wasm and Windows have no dlopen.
`vapor.luaheaders` (generated `lua/luaheaders.lua`, `make headers`) carries Lua's headers: `require("vapor.luaheaders").write(dir)` lets a compiler build a module against exactly this runtime.
Test: `tests/native_module.lua` (writes the headers, compiles a C module, loads it).
Test: `sh tests/dynamic/run.sh`. Windows `.dll` loading is not done (Lua's loadlib would need `LoadLibrary` and an exported API).

## Module system, first cut (2026-11-21)

`modules.conf` now also lists the optional parts of the vapor API: `vapor.fs` (`src/mod_fs.c`), `vapor.term` (`src/mod_term.c` + the decoder in
`src/vtinput.c`) and `vapor.input` (`lua/input.lua`, a Lua-file module: `name lua:path`, embedded by `tools/mkmodules`). `@VLR@` in a path is the
folder of `modules.conf`. A build lists the modules it wants (`MODULES=...`, empty = all); one without `vapor.fs` simply has `vapor.fs == nil`.
The global `vapor` table is a lazy facade: `vapor.<name>` loads the registered module `vapor.<name>` on first access (only compiled-in
modules count, no file search); `vapor.size` stays as an alias into `vapor.term`. The core now only has tasks, timers, events, `now`, `wait`,
`caps`, identity. Optional modules reach the loop through two hooks in `lua/sched.lua`: `vapor._after(ms, fn)` and `vapor._source(fd, fn)`
(a persistent readable-handle callback; `vapor.input` uses it for the console, `vapor.net` will for sockets).
Heap at start of a script (host, same one-line script): 46.1 KB before the split, 44.2 KB after (40.3 KB with the internal Lua stripped).
Still to do for 0.2: app manifest check, rockspec reading in `vlr-build`, the 5.1 C-API shims test with more real rocks.

`tools/vlr-build add-rock ROCKSPEC SRCDIR [--write]` turns a builtin-type rockspec into `modules.conf` lines (`tools/rock2conf.lua`, run by vlr itself):
`sources`, `defines`, `incdirs` and `luaopen_` names (dots to underscores, everything up to the last hyphen dropped, as LuaRocks does) for C modules, `name lua:file` for Lua files. Rocks with
other build types or external `libraries` are refused. Verified: the lfs and lua-cjson rockspecs reproduce their existing `modules.conf` lines exactly
(`tests/rock` pins the rules). Lua-file modules may use `@EXT@` too (`VLR_EXT`, set by the Makefile from `EXT`).

**C rocks unmodified (2026-11-21).** Beyond lfs, lpeg and cjson, two more third-party rocks compiled into vlr from their own rockspec and sources, no edits, and
passed a round-trip script: `lua-cmsgpack` (a 5.1-era single file) and `luautf8` (module `lua-utf8`). Finding: luautf8's `luaopen_utf8` is also Lua 5.4's own
utf8 library symbol and its file is called `lutf8lib.c` like Lua's. Fixed in the build, not in the rock: module objects are named from their whole path
(`build/<target>/m_<path>.o`), and `rock2conf` renames a clashing `luaopen_` symbol with `-Dluaopen_utf8=luaopen_rock_<name>`. These two are not in `modules.conf`
(default builds must not need checkouts nobody has); `vlr-build add-rock` adds them where wanted.

## Version 0.2.0 (2026-11-21)

Module split, app manifests and rockspec reading are done, so the core names in `docs/api.md` are frozen (tag `v0.2.0`). Board check on the RP2040
(`rp2040-vlr`, flashed): `identity`, `decode`, `sched`, `events`, `compat51`, `modules` pass; keys and mouse arrive through the lazy `vapor.input`; Lua heap at
start of a script 30.3 KB (31.8 KB before the split). Not re-run on the board after the split: `fs`, `exec`, `fd`, the lfs suite. NuttX sim image builds.

## Networking, TLS, input backends (2026-11-21 evening)
New since 0.2.0 (all experimental until used by a real app; core names unchanged):
- `vapor.net` + `vapor.stream` (docs/net.md); `vapor.tls` (BearSSL engine `vapor.tlsraw` + `lua/tls.lua`, chain and host name always verified, roots from files, the Windows store and
  the built-in list `vapor.cacerts`); `std.http` (HTTP/1.1 client); `socket` / `std.socket` (LuaSocket subset); `vapor.sign` (ed25519 verify, Monocypher); `vapor.close_fd`;
  `vapor.repl` and `vlr -e CODE`; `VLR_LIBDIR`. vpm runs on vlr (HTTP/HTTPS through std.http, index signature through vapor.sign).
- Input: the terminal decoder is vaporUI's (sibling checkout, latest main on purpose); Windows reads native console records (`vlr_console_record`); a real Linux VT uses raw keycodes
  (`src/term_vt.c`, needs a hands-on test: docs/tty-test.md).
- Verified: Linux (ASan/UBSan), wine, wasm/Node, real Windows (reports/), NuttX sim with host networking (HTTP, HTTPS with a mounted CA file, vpm starts). macOS and the Linux VT: CI / user.

Host build sizes, stripped (x86-64, `-O2`), by module set; the Lua heap right after start is what matters on boards and barely moves with modules (embedded Lua is only loaded on `require`):

| modules | stripped size | Lua heap at start |
|---|---|---|
| `vapor.fs` (smallest useful) | 274 KB | 44.8 KB |
| + `vapor.term vapor.input` (vaporUI decoder, native key records) | 303 KB (+29) | 45.0 KB |
| + `vapor.stream vapor.netraw vapor.net` instead of the terminal | 290 KB (+17) | - |
| + TLS (`vapor.tlsraw vapor.tls`) and `vapor.cacerts` | +573 KB (BearSSL about 390, root list about 180) | 45.4 KB |
| `vapor.sign` (Monocypher ed25519) | +57 KB | - |
| everything, with lfs, lpeg, cjson | 1037 KB | 46.9 KB (42.7 KB with `--dialect=5.4`: the 5.1 compat layer costs 4 KB) |

The RP2040 numbers are in the section above (32-bit, about 30 KB at start); modules are chosen per board in Kconfig, so a board that does not need TLS or the decoder does not pay for them.
