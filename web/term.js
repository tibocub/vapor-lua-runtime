// vlr in a real terminal emulator (wterm): stdout bytes go to the terminal, its output bytes are stdin and the
// escape sequences the vaporui module decodes, so keys, mouse and resize behave exactly as on a native tty.
// ?example=snake runs vaporUI's snake game (examples/<name>/{main,game}.lua, copied by build.sh), ?script=<url> loads any Lua file
// (default: the events demo), ?dialect=5.4 selects plain 5.4.
import { WTerm } from "@wterm/dom";
import "@wterm/dom/css";
import createVlr from "./vlr.js";
import { startVlr } from "./vlr-glue.js";

const q = new URLSearchParams(location.search);
const DEMO = `local ui = require("vaporui")
ui.open({mouse = 1})
local function show(...) io.write(table.concat({...}, " "), "\\r\\n"); io.flush() end
show("vaporui in wterm: type, click, resize the window; q quits")
while true do
  local ev = {ui.poll()}
  show(unpack and unpack(ev) or table.unpack(ev))
  if ev[1] == "char" and ev[2] == "q" then break end
end
ui.close()`;

window.addEventListener("error", (e) => { document.body.append(String(e.message)); });
window.addEventListener("unhandledrejection", (e) => { document.body.append(String(e.reason)); });
const term = new WTerm(document.getElementById("terminal"), { cursorBlink: true });
await term.init();
const text = async (u) => (await fetch(u)).text();
const files = {};
if (q.get("example")) { // an example folder: main.lua and the modules it requires, run from the root like `lua main.lua`
  const dir = "dist/examples/" + q.get("example").replace(/[^\w-]/g, "") + "/";
  const list = (await (await fetch(dir + "files.json")).json());
  for (const f of list) files["/" + f] = await text(dir + f);
} else files["/main.lua"] = q.get("script") ? await text(q.get("script")) : DEMO;

let out = [];
const flush = () => { if (out.length) { term.write(new Uint8Array(out)); out = []; } };
let prev = 0; // the emscripten tty ends lines with a bare LF; a terminal wants CR LF
const stdout = (b) => { if (b === null) return flush(); if (!out.length) queueMicrotask(flush); b &= 0xff; if (b === 10 && prev !== 13) out.push(13); out.push(b); prev = b; };

let vlr;
try { vlr = await startVlr(createVlr, {
  files, args: [q.get("dialect") === "5.4" ? "--dialect=5.4" : "", "/main.lua"].filter(Boolean),
  stdout, cols: term.cols, rows: term.rows,
  onExit: (c) => { flush(); term.write(`\r\n[exited ${c}]\r\n`); },
}); } catch (e) { term.write("startup failed: " + e + "\r\n"); throw e; }
term.onData = (s) => vlr.sendInput(s);
term.onResize = (c, r) => vlr.resize(c, r);
term.focus();
if (location.hash === "#shot") { await new Promise((r) => setTimeout(r, 3000)); fetch("/report", { method: "POST", body: document.body.innerText }); } // headless checks
