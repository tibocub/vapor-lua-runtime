// Glue between a page (or Node) and the wasm runtime built by `make TARGET=web` (web/vlr.js exports createVlr).
// Each call creates a fresh runtime instance (one Lua state per run) with a MEMFS filesystem. The runtime is built with Asyncify:
// a script blocks like on any host (sleeps, io.read after waiting on stdin, vaporui.poll), the page stays responsive.
//
//   const vlr = await startVlr(createVlr, {
//     files: {"/main.lua": "print('hi')"}, args: ["/main.lua"],
//     print, printErr, onExit,          // stdout/stderr lines, exit code (0 = ok, 1 = a task failed)
//     interactive: true,                // false: stdin is an empty stream (always readable, reads EOF)
//     stdout, cols, rows,               // terminal mode: raw output bytes (byte|null) instead of lines, and the terminal's size
//   });
//   vlr.sendInput("text");              // what a terminal sends: stdin bytes, decoded into events by the vaporui module
//   vlr.resize(cols, rows);
export async function startVlr(createVlr, { files = {}, args, print, printErr, onExit, interactive = true, cols = 80, rows = 24, stdout = null }) {
  const input = [];
  const enc = new TextEncoder();
  let size = [cols, rows], resized = false, wake = null, mod = null;
  const poke = () => { if (wake) { const w = wake; wake = null; w(1); } if (mod && mod.vlrWake) mod.vlrWake(); };
  // what vaporUI's wasm backend (src/platform/wasm.c) reads through Module.vui
  const vui = {
    wait: (ms) => input.length || resized ? 1 : new Promise((res) => {
      wake = res;
      if (ms >= 0) setTimeout(() => { if (wake === res) { wake = null; res(0); } }, ms);
    }),
    pending: () => input.length,
    take: (dst) => { const n = Math.min(dst.length, input.length); for (let i = 0; i < n; i++) dst[i] = input.shift(); return n; },
    resized: () => { const r = resized; resized = false; return r ? 1 : 0; },
    cols: () => size[0],
    rows: () => size[1],
  };
  mod = await createVlr({
    noInitialRun: true,
    print,
    printErr,
    vui,
    vlrStdinReady: interactive ? () => input.length > 0 : () => true,
    onVlrExit: onExit,
    // stdout: a byte callback instead of lines, for a terminal emulator (null at flush time)
    preRun: [(m) => m.FS.init(() => (input.length ? input.shift() : null), stdout, stdout && ((b) => b && console.error(String.fromCharCode(b & 0xff))))],
  });
  for (const [path, data] of Object.entries(files)) {
    const dir = path.slice(0, path.lastIndexOf("/"));
    if (dir) mod.FS.mkdirTree(dir);
    mod.FS.writeFile(path, data);
  }
  mod.callMain(args); // returns at the first wait; the script goes on from timers and input
  return {
    resize(c, r) { size = [c, r]; resized = true; poke(); },
    sendInput(text) { input.push(...enc.encode(text)); poke(); },
  };
}
