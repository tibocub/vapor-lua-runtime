# Status

As of 2026-11-24, version 0.2.0 plus unreleased work. This page says what is actually verified. "CI" means the GitHub workflow; "by hand" means a person ran it once.

## Works, verified

| area | state |
|---|---|
| Core: scheduler, timers, events, `vapor.step`, 5.1 dialect and `--dialect=5.4` | 62 suite runs pass on Linux (also under ASan/UBSan); same suite on macOS, Windows, WebAssembly in CI |
| Console input (keys, mouse, resize, paste) | Linux/macOS terminals (pty test), Windows console (real Windows, cmd, PowerShell, wezterm), WebAssembly byte path |
| `vapor.fs`, `os.execute`, app folders with manifests, `-e`, REPL | pass wherever the platform has them |
| Networking: TCP/UDP, streams, name lookup without blocking | Linux, wine, real Windows, NuttX simulator with host networking |
| TLS (BearSSL), chain and host name always verified; `std.http` client; `std.httpd` server | local openssl server tests; manual checks against public hosts; Windows trust store plus built-in root list |
| LuaSocket compatibility (`socket`, `ltn12`, `mime`, `socket.url`, `socket.http`) | tests, and unmodified pure-Lua rocks run through vpm |
| `vapor.sign` (ed25519) | used by vpm to verify the signed index |
| C rocks: `.so` loading (posix), compile into the binary, 5.1 C API shim | exercised against hundreds of real rocks through vpm (see the vpm status page) |
| WebAssembly build, playground, wterm page | Node suite in CI; headless Firefox; typing into wterm by hand not done |
| NuttX simulator, RP2040 | built and run in the vaporOS repository; vlr replaced vlua there |

Sizes: host binary about 1.3 MB unstripped with everything, 274 KB stripped with only `vapor.fs`. RP2040: about 140 KB of flash for vlr itself, 30 KB of Lua heap for an empty script (details in spec.md).

## Not verified or not done

- The 13 most recent local commits have not been pushed, so CI has not seen them.
- RP2040: the suite passed through 0.2.0; the network, TLS, HTTP and sign modules have not been run on the board (no network hardware), and `fs`, `exec`, `fd` and lfs were not re-run after the later module work.
- Linux virtual console raw keycodes (`src/term_vt.c`): written, needs a hands-on test ([tty-test.md](tty-test.md)).
- macOS: builds and passes the suite in CI; dlopen of rocks built by vpm is untested there (needs `-undefined dynamic_lookup`-style link flags handled by vpm).
- Windows: no dlopen (`.dll` loading is not implemented); C rocks must be bundled into the binary.
- DNS: blocking on NuttX and wasm; the first address returned is used.
- No compression, proxies, cookies or keep-alive in `std.http`; `std.httpd` is for local and development use.
- Not implemented: `vapor.worker`, subprocess spawn with pipes, `vapor.gfx`, security sandbox, bytecode distribution, LuaJIT engine.
- No license file yet.

## Stability
The names frozen in 0.2 (see [api.md](api.md)) will not change in a minor release. Networking, TLS, HTTP, `vapor.ui`, `vapor.manifest`, the REPL and the 5.1 C-API shim are experimental.
