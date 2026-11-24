// Node check of the terminal path on the web build: vaporui on vaporUI's wasm backend. node --liftoff-only web/ui-test.mjs
import createVlr from "./vlr.js";
import { startVlr } from "./vlr-glue.js";
const script = `local ui = require("vaporui")
local c, r = ui.open({mouse = 1})
io.stderr:write("SIZE ", c, "x", r, "\\n")
while true do
  local ev = {ui.poll()}
  io.stderr:write("EV ", table.concat(ev, ","), "\\n")
  if ev[1] == "char" and ev[2] == "q" then break end
end
ui.close()`;
let err = "", done = false;
const v = await startVlr(createVlr, { files: { "/t.lua": script }, args: ["/t.lua"], print: () => {}, printErr: (s) => (err += s + "\n"), interactive: true, cols: 80, rows: 24,
  onExit: () => { done = true; } });
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
await wait(300);
v.sendInput("a\x1b[A\x1b[<0;5;6M"); await wait(200);
v.resize(100, 30); await wait(200);
v.sendInput("q"); await wait(300);
const want = ["SIZE 80x24", "EV char,a", "EV key,up,0", "EV mouse,press,1,5,6,0", "EV resize,100,30", "EV char,q"];
const miss = want.filter((w) => !err.includes(w));
console.log(miss.length || !done ? "FAIL web ui; missing " + miss + " done=" + done + "\n" + err : "ok   web ui (vaporui on the wasm backend)");
process.exit(miss.length || !done ? 1 : 0);
