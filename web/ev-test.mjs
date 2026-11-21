// Node check of the page-side event path (vlr_wasm_push): node web/ev-test.mjs
import createVlr from "./vlr.js";
import { startVlr } from "./vlr-glue.js";
import { readFileSync } from "node:fs";
const script = readFileSync(process.argv[2] ?? new URL("./ev-test.lua", import.meta.url), "utf8");
let out = "";
const v = await startVlr(createVlr, { files: { "t.lua": script }, args: ["/t.lua"], print: (s) => (out += s + "\n"), printErr: console.error, interactive: true, cols: 80, rows: 24, onExit: () => {
  console.log(out); const want = ["EV resize,100,30", "EV char,a", "EV key,up,4", "EV mouse,press,1,5,6,0", "EV key,down,0", "EV mouse,scroll_up,0,2,3,0", "EV char,q"];
  const miss = want.filter((w) => !out.includes(w)); console.log(miss.length ? "FAIL missing " + miss : "ok   web events"); process.exit(miss.length ? 1 : 0); } });
await new Promise((r) => setTimeout(r, 200));
v.resize(100, 30); v.event("char", "a"); v.event("key", "up", 4); v.event("mouse", "press", 1, 5, 6, 0); v.sendInput("\x1b[B\x1b[<64;2;3M"); // terminal bytes, as wterm sends them
 await new Promise((r) => setTimeout(r, 200)); v.event("char", "q");
