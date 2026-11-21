# vlr API reference (version 0.2)

Stability: **stable** = frozen since 0.2 (semantic versioning on `vapor.version`; breaking changes only in a major release).
**experimental** = may change, graduates after real use. **internal** = used by the embedded Lua code, not part of the API.
Since 0.2 the names marked stable are frozen. Tests in `tests/` are the executable spec.

All functions live on the global `vapor` table, which is a lazy facade: `vapor.fs`, `vapor.input` (and `vapor.size`) load their optional modules on first access, and are `nil` in a build without them. `require("vapor.fs")` works too.
"Task" = a coroutine started with `vapor.spawn`, or the main script, which is itself a task.

## Identity

| name | | |
|---|---|---|
| `vapor.version` | stable | string `"major.minor.patch"` |
| `vapor.platform` | stable | `"linux"`, `"windows"`, `"macos"`, `"nuttx"`, `"wasm"`, `"posix"` |
| `vapor.dialect` | stable | `"5.1"` (default compat layer) or `"5.4"` (`--dialect=5.4`) |
| `vapor.caps` | stable | table of booleans: `fs`, `net`, `gfx`, `tty`, `dlopen`, `exec`. Check before using an optional area |
| `vapor.builtin` | stable | set of compiled-in native module names (`vapor.builtin.lfs == true`); matches `package.preload` |

## Tasks, time and events (core)

| call | | meaning |
|---|---|---|
| `vapor.spawn(fn, ...)` | stable | start a task; returns its coroutine |
| `vapor.sleep(seconds)` | stable | pause this task; other tasks run (millisecond resolution) |
| `vapor.wait_fd(fd, timeout?, mode?)` | stable | wait until the handle is readable (`mode "w"`: writable); returns `fd`, or `nil, "timeout"`. Handle 0 = console input; other handles are backend specific |
| `vapor.pull(timeout?)` | stable | next event `(name, ...)` or `nil, "timeout"` |
| `vapor.push(name, ...)` | stable | queue an event (wakes a task blocked in `pull`) |
| `vapor.timer(seconds)` | stable | pushes `("timer", id)` after the delay; returns `id` |
| `vapor.run()` | stable | run until no task has anything left to wait for; returns when done |
| `vapor.step(max_ms?)` | stable | one loop turn for a host that owns the main loop (browser, GUI): returns ms to the next timer, `-1` if only waiting on handles, `nil` when done |
| `vapor.failed()` | stable | true if any task died with an error (the script exit status uses it) |
| `vapor.now()` | stable | monotonic milliseconds |

## Console and input events (optional modules `vapor.input` and `vapor.term`)

| call | | meaning |
|---|---|---|
| `vapor.input(true \| {mouse=0\|1\|2})` | stable | raw console; events arrive through `vapor.pull`. `mouse`: 0 none, 1 clicks and drags, 2 also motion. `vapor.input(false)` restores the console (also restored on exit) |
| events | stable | `"char", text` · `"key", name, mods, base, scancode` (mods: 1 shift, 2 alt, 4 ctrl, 8 meta; for characters `name` is the lowercase key and Shift is a flag, `base` is the same key on a US layout ("" for named keys), `scancode` the physical key in USB HID numbering, 0 if unknown; experimental: the last two) · `"paste", "start"|"end"` (bracketed paste; text between arrives as `char`) · `"mouse", action, button, x, y, mods` (press, release, drag, move, scroll_up, scroll_down; 1-based) · `"resize", cols, rows` · `"quit"` when input ends |
| `vapor.size()` | stable | `cols, rows` of the console, or `nil` |
| `require("vapor.term")` | internal | `console_read/raw/size` and `decode*`: the platform calls and byte decoder behind `input` (tested in `tests/decode.lua`) |
| `vapor._after(ms, fn)`, `vapor._source(fd, fn)` | internal | loop hooks for optional modules |

Key names: `up down left right home end insert delete pageup pagedown enter tab backspace escape f1..f12 space`, or the ASCII letter for Ctrl/Alt combinations.
While `input` is on, the console belongs to the events: do not also read it with `io.read` or `wait_fd(0)`.

## Filesystem (becomes the optional `vapor.fs` module)

| call | | meaning |
|---|---|---|
| `vapor.fs.list(path)` | stable | array of names, or `nil, err` |
| `vapor.fs.stat(path)` | stable | `{type="file"\|"dir", size=, mtime=}` or `nil, err` |
| `vapor.fs.mkdir(path)` / `vapor.fs.rmdir(path)` | stable | `true` or `nil, err` (what `os.remove` cannot do for directories on Windows) |

## Apps (optional module `vapor.manifest`)

`vlr <folder>` runs an app folder: `manifest.lua` (data only, evaluated with an empty environment) plus the entry script (default `main.lua`).
Fields: `name`, `version`, `entry`, `needs = {vlr = "0.2", dialect = "5.4", caps = {...}, modules = {...}}`. Modules count if built in (`vapor.builtin`) or
found as Lua files in `<folder>/lua_modules` or `<folder>`. If anything is missing the app is refused with the reasons and exit status 1.
Experimental. Functions: `require("vapor.manifest").load(dir)`, `.check(m, dir)`, `.main(dir, ...)`.

## Process

`os.execute` works as in Lua (`vapor.caps.exec`); `os.exit` closes the Lua state first so finalizers run. Both are standard names, not `vapor.*`.

## Networking, TLS, HTTP, signatures (all experimental; see [net.md](net.md))

| module | | meaning |
|---|---|---|
| `vapor.net`, `vapor.stream` | experimental | TCP/UDP for tasks, file-like streams (`read`, `readsome`, `write`, `lines`, `settimeout`, `on`, `pipe`); `net.connect/listen/udp/resolve`; names resolve without stopping other tasks |
| `vapor.tls` | experimental | `tls.connect(host, port, opts)`, `tls.wrap(sock, host, opts)`; chain and host name always verified; roots from files, the Windows store, built-in list |
| `std.http` | experimental | `http.get/post/request`; redirects, chunked, streaming `sink`, https |
| `socket`, `std.socket` | experimental | LuaSocket-compatible subset so luasocket-based rocks run unmodified |
| `vapor.sign` | experimental | `sign.verify(signature, message, public_key)`, ed25519 |
| `vapor.close_fd(handle)` | experimental | wake tasks waiting on a handle about to be closed (`nil, "closed"`) |

`vapor.caps.net` says whether the build and platform have sockets.

## Interactive use

`vlr` with no script (or `vlr -i`) starts the prompt (`vapor.repl`); `vlr -e 'code'` runs a chunk. Experimental.

## Not yet (planned, experimental when they appear)

`vapor.spawn_process` (subprocess with pipes), `vapor.worker`, `vapor.gfx`, `vapor.sandbox`.
