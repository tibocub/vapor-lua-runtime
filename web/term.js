// vlr in a real terminal emulator (wterm): stdout bytes go to the terminal, its output bytes are stdin and the
// escape sequences vapor.input() decodes, so keys, mouse and resize behave exactly as on a native tty.
// ?script=<url> loads a Lua file (default: the events demo), ?dialect=5.4 selects plain 5.4.
import { WTerm } from "@wterm/dom";
import "@wterm/dom/css";
import createVlr from "./vlr.js";
import { startVlr } from "./vlr-glue.js";

const q = new URLSearchParams(location.search);
const DEMO = `vapor.input({mouse = 1})
print("vlr in wterm: type, click, resize the window; q quits")
while true do
  local ev = {vapor.pull()}
  io.write(table.concat(ev, " "), "\\r\\n"); io.flush()
  if ev[1] == "char" and ev[2] == "q" then break end
end
vapor.input(false)`;

window.addEventListener("error", (e) => { document.body.append(String(e.message)); });
window.addEventListener("unhandledrejection", (e) => { document.body.append(String(e.reason)); });
const term = new WTerm(document.getElementById("terminal"), { cursorBlink: true });
await term.init();
const src = q.get("script") ? await (await fetch(q.get("script"))).text() : DEMO;

let out = [];
const flush = () => { if (out.length) { term.write(new Uint8Array(out)); out = []; } };
let prev = 0; // the emscripten tty ends lines with a bare LF; a terminal wants CR LF
const stdout = (b) => { if (b === null) return flush(); if (!out.length) queueMicrotask(flush); b &= 0xff; if (b === 10 && prev !== 13) out.push(13); out.push(b); prev = b; };

let vlr;
try { vlr = await startVlr(createVlr, {
  files: { "/main.lua": src }, args: [q.get("dialect") === "5.4" ? "--dialect=5.4" : "", "/main.lua"].filter(Boolean),
  stdout, cols: term.cols, rows: term.rows,
  onExit: (c) => { flush(); term.write(`\r\n[exited ${c}]\r\n`); },
}); } catch (e) { term.write("startup failed: " + e + "\r\n"); throw e; }
term.onData = (s) => vlr.sendInput(s);
term.onResize = (c, r) => vlr.resize(c, r);
term.focus();
if (location.hash === "#shot") { await new Promise((r) => setTimeout(r, 3000)); fetch("/report", { method: "POST", body: document.body.innerText }); } // headless checks
