// CLI wrapper so the conformance suite runs on the web build under Node:  VLR="node web/run.mjs" sh tests/run.sh
// usage: node web/run.mjs [--dialect=5.4] [--step] script.lua [args...]
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { startVlr } from "./vlr-glue.js";

const here = resolve(fileURLToPath(import.meta.url), "..");
const { default: createVlr } = await import(resolve(here, "vlr.js"));
const args = process.argv.slice(2);
const script = args.find((a) => !a.startsWith("--"));
if (!script) { console.error("usage: run.mjs [--dialect=5.4] script.lua"); process.exit(2); }
const vpath = "/" + script.replace(/^\/+/, ""); // same relative path inside MEMFS, so arg[0] and tests/ siblings match
const files = { [vpath]: readFileSync(script) };
const rewritten = args.map((a) => (a === script ? vpath : a));
await startVlr(createVlr, {
  files, args: rewritten, interactive: false,
  print: (s) => process.stdout.write(s + "\n"),
  printErr: (s) => process.stderr.write(s + "\n"),
  onExit: (code) => process.exit(code),
});
