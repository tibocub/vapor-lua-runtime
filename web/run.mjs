// CLI wrapper so the conformance suite runs on the web build under Node:  VLR="node web/run.mjs" sh tests/run.sh
// usage: node web/run.mjs [--dialect=5.4] [--step] script.lua [args...]
import { readFileSync, readdirSync, statSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { startVlr } from "./vlr-glue.js";

const here = resolve(fileURLToPath(import.meta.url), "..");
const { default: createVlr } = await import(resolve(here, "vlr.js"));
const args = process.argv.slice(2);
const script = args.find((a) => !a.startsWith("--"));
if (!script) { console.error("usage: run.mjs [--dialect=5.4] script.lua"); process.exit(2); }
// an app folder is mounted whole; a script comes with its sibling tree (fixtures such as tests/app/...), like on a real disk
const files = {};
const mount = (dir) => { for (const e of readdirSync(dir)) { const p = join(dir, e); if (statSync(p).isDirectory()) mount(p); else files["/" + p.replace(/^\/+/, "")] = readFileSync(p); } };
if (statSync(script).isDirectory()) mount(script);
else if (!script.startsWith("/")) mount(dirname(script)); // absolute paths (temp files) come alone
else files[script] = readFileSync(script);
const rewritten = args; // relative paths resolve against MEMFS "/" like they do against the repo root on disk
await startVlr(createVlr, {
  files, args: rewritten, interactive: false,
  print: (s) => process.stdout.write(s + "\n"),
  printErr: (s) => process.stderr.write(s + "\n"),
  onExit: (code) => process.exit(code),
});
