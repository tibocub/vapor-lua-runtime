// Glue between a page (or Node) and the wasm runtime built by `make TARGET=web` (web/vlr.js exports createVlr).
// Each call creates a fresh runtime instance (one Lua state per run) with a MEMFS filesystem.
//
//   const vlr = await startVlr(createVlr, {
//     files: {"/main.lua": "print('hi')"}, args: ["/main.lua"],
//     print, printErr, onExit,          // stdout/stderr lines, exit code (0 = ok, 1 = a task failed)
//     interactive: true,                // false: stdin is an empty stream (always readable, reads EOF)
//   });
//   vlr.sendInput("text\n");            // interactive only: stdin bytes, and what vapor.input() decodes (a terminal's output)
//   stdout: (byte|null) => void        // raw output bytes (terminal emulator) instead of print lines
//
// stdin: scripts wait with vapor.wait_fd(0) and then read; a read on an empty buffer returns EOF (a browser cannot block).
export async function startVlr(createVlr, { files = {}, args, print, printErr, onExit, interactive = true, cols = 80, rows = 24, stdout = null }) {
  const input = [];
  const enc = new TextEncoder();
  const m = await createVlr({
    noInitialRun: true,
    print,
    printErr,
    vlrStdinReady: interactive ? () => input.length > 0 : () => true,
    onVlrExit: onExit,
    vlrIn: input, // the console byte queue vapor.input() decodes (same bytes as stdin)
    // stdout: a byte callback instead of lines, for a terminal emulator (null at flush time)
    preRun: [(mod) => mod.FS.init(() => (input.length ? input.shift() : null), stdout, stdout && ((b) => b && console.error(String.fromCharCode(b & 0xff))))],
  });
  for (const [path, data] of Object.entries(files)) {
    const dir = path.slice(0, path.lastIndexOf("/"));
    if (dir) m.FS.mkdirTree(dir);
    m.FS.writeFile(path, data);
  }
  m.vlrCols = cols;
  m.vlrRows = rows;
  m.callMain(args);
  const push = (name, s, ...ints) => m.ccall("vlr_wasm_push", null, ["string", "string", "number", "number", "number", "number", "number"],
    [name, s ?? null, ints.length, ints[0] ?? 0, ints[1] ?? 0, ints[2] ?? 0, ints[3] ?? 0]);
  return {
    // events for vapor.input(): char(text), key(name, mods), mouse(action, button, x, y, mods), resize(cols, rows)
    event: push,
    resize(c, r) { m.vlrCols = c; m.vlrRows = r; push("resize", null, c, r); },
    sendInput(text) {
      input.push(...enc.encode(text));
      m._vlr_wasm_wake(); // run the loop now instead of at its next 20 ms poll
    },
  };
}

// Translates DOM keyboard and mouse events on `el` into vlr events. cell() returns the size of one character cell in px.
export function attachEvents(el, vlr, cell) {
  const names = { ArrowUp: "up", ArrowDown: "down", ArrowLeft: "left", ArrowRight: "right", Home: "home", End: "end",
    PageUp: "pageup", PageDown: "pagedown", Insert: "insert", Delete: "delete", Enter: "enter", Tab: "tab",
    Backspace: "backspace", Escape: "escape" };
  const mods = (e) => (e.shiftKey ? 1 : 0) | (e.altKey ? 2 : 0) | (e.ctrlKey ? 4 : 0);
  const xy = (e) => { const r = el.getBoundingClientRect(), c = cell(); return [Math.floor((e.clientX - r.left) / c.w) + 1, Math.floor((e.clientY - r.top) / c.h) + 1]; };
  const btn = (e) => (e.button === 0 ? 1 : e.button === 1 ? 2 : 3);
  el.addEventListener("keydown", (e) => {
    let name = names[e.key] ?? (/^F([1-9]|1[0-2])$/.test(e.key) ? e.key.toLowerCase() : null);
    if (name) { vlr.event("key", name, mods(e)); e.preventDefault(); return; }
    if (e.key.length === 1) {
      if (e.ctrlKey || e.altKey) { vlr.event("key", e.key.toLowerCase(), mods(e)); e.preventDefault(); }
      else { vlr.event("char", e.key); e.preventDefault(); }
    }
  });
  el.addEventListener("mousedown", (e) => { const [x, y] = xy(e); el.focus(); vlr.event("mouse", "press", btn(e), x, y, mods(e)); });
  el.addEventListener("mouseup", (e) => { const [x, y] = xy(e); vlr.event("mouse", "release", btn(e), x, y, mods(e)); });
  el.addEventListener("mousemove", (e) => { const [x, y] = xy(e); vlr.event("mouse", e.buttons ? "drag" : "move", e.buttons ? 1 : 0, x, y, mods(e)); });
  el.addEventListener("wheel", (e) => { if (document.activeElement !== el) return; /* unfocused: let the page scroll */ const [x, y] = xy(e); vlr.event("mouse", e.deltaY < 0 ? "scroll_up" : "scroll_down", 0, x, y, mods(e)); e.preventDefault(); }, { passive: false });
}
