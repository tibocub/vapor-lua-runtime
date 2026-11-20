// Glue between a page (or Node) and the wasm runtime built by `make TARGET=web` (web/vlr.js exports createVlr).
// Each call creates a fresh runtime instance (one Lua state per run) with a MEMFS filesystem.
//
//   const vlr = await startVlr(createVlr, {
//     files: {"/main.lua": "print('hi')"}, args: ["/main.lua"],
//     print, printErr, onExit,          // stdout/stderr lines, exit code (0 = ok, 1 = a task failed)
//     interactive: true,                // false: stdin is an empty stream (always readable, reads EOF)
//   });
//   vlr.sendInput("text\n");            // interactive only
//
// stdin: scripts wait with vapor.wait_fd(0) and then read; a read on an empty buffer returns EOF (a browser cannot block).
export async function startVlr(createVlr, { files = {}, args, print, printErr, onExit, interactive = true }) {
  const input = [];
  const enc = new TextEncoder();
  const m = await createVlr({
    noInitialRun: true,
    print,
    printErr,
    vlrStdinReady: interactive ? () => input.length > 0 : () => true,
    onVlrExit: onExit,
    preRun: [(mod) => mod.FS.init(() => (input.length ? input.shift() : null))],
  });
  for (const [path, data] of Object.entries(files)) {
    const dir = path.slice(0, path.lastIndexOf("/"));
    if (dir) m.FS.mkdirTree(dir);
    m.FS.writeFile(path, data);
  }
  m.callMain(args);
  return {
    sendInput(text) {
      input.push(...enc.encode(text));
      m._vlr_wasm_wake(); // run the loop now instead of at its next 20 ms poll
    },
  };
}
