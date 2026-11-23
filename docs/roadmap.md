# Roadmap

## Immediate (next weeks)
1. Push the local commits, confirm CI is green on Linux, macOS, Windows and WebAssembly. Add a license.
2. Hands-on checks: Linux virtual console keys ([tty-test.md](tty-test.md)), typing into the wterm page.
3. Re-run the RP2040 suite and measure heap and flash with the current module set; record numbers in status.md.
4. macOS: confirm that C rocks built by vpm load (dlopen link flags); fix in vpm or the Makefile.
5. Windows: decide how C rocks work there (bundle only, or implement `.dll` loading); test the MSYS2 flow for vpm.
6. Tag 0.3 once the experimental networking and HTTP names have survived real use by vpm; promote what is solid in api.md.
7. Small gaps: socket options and `shutdown`, `std.http` keep-alive and gzip, IPv6, async name lookup on NuttX and wasm.

## Next (months)
- `vapor.worker` (isolated Lua state, own scheduler, copied-value messages; thread on desktop, Web Worker in the browser) and subprocess spawn with pipes.
- vaporUI framebuffer cell renderer (SDL window, `/dev/fb`, canvas): the same program in terminal, window and browser. Developed in the vaporUI repository.
- Package tooling inside the runtime: running real `luarocks` on desktop vlr; vpm stays the preferred and on-device tool.
- Security tier: text-only `load` by default, memory and instruction limits, opt-in sandbox, manifest-declared capabilities. Hostile code still needs a separate process or the WASM build; the docs will say so.
- Bundling C rocks that need a system library; rocks' Lua files in the same bundle step.

## Long-term goals
- A real alternative to Python and Node for small portable programs: one binary of 0.3 to 1 MB, a large installable library ecosystem (all of luarocks.org that can work), the same program on desktop, browser, and boards with 190 KB of RAM.
- Every target in CI, including an emulated NuttX/RP2040 run.
- Embedding in the vaporOS browser (HyperBrowser) and mobile through it, if the WASM build performs well.
- A stable 1.0 API with long-term compatibility promises.

## Research and ideas (not committed)
- Bytecode distribution (`.vlb`): fixed format, trusted input only; saves parse time and compile RAM on boards, does not speed up the VM.
- Executing function prototypes in place from flash on the RP2040 (as NodeMCU's LFS does).
- Optional LuaJIT engine on desktop: needs the portable code to stay in the 5.1 intersection; low priority, never allowed to shape the API.
- WASM modules as a third native-module option (wasm3 or WAMR): measure on ESP32-class chips; not viable on 187 KB of RAM.
- Terminal images (half-blocks, Sixel, Kitty) as an optional module.
- mbedTLS backend on NuttX to avoid carrying two TLS stacks; OpenSSL or Schannel backends to use the OS trust store; browser `fetch` for wasm.
- Single-file app bundles; a name that is less awkward than "vlr".
