# vlr API reference (version 0.1)

Stability: **stable** = frozen at 0.2 (semantic versioning on `vapor.version`; breaking changes only in a major release).
**experimental** = may change, graduates after real use. **internal** = used by the embedded Lua code, not part of the API.
Until 0.2 everything is technically experimental; the marks below are the intent. Tests in `tests/` are the executable spec.

All functions live on the global `vapor` table (it becomes a lazy facade over optional modules in 0.2, names unchanged).
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
| `vapor.wait_fd(fd, timeout?)` | stable | wait until the handle is readable; returns `fd`, or `nil, "timeout"`. Handle 0 = console input; other handles are backend specific |
| `vapor.pull(timeout?)` | stable | next event `(name, ...)` or `nil, "timeout"` |
| `vapor.push(name, ...)` | stable | queue an event (wakes a task blocked in `pull`) |
| `vapor.timer(seconds)` | stable | pushes `("timer", id)` after the delay; returns `id` |
| `vapor.run()` | stable | run until no task has anything left to wait for; returns when done |
| `vapor.step(max_ms?)` | stable | one loop turn for a host that owns the main loop (browser, GUI): returns ms to the next timer, `-1` if only waiting on handles, `nil` when done |
| `vapor.failed()` | stable | true if any task died with an error (the script exit status uses it) |
| `vapor.now()` | stable | monotonic milliseconds |

## Console and input events

| call | | meaning |
|---|---|---|
| `vapor.input(true \| {mouse=0\|1\|2})` | stable | raw console; events arrive through `vapor.pull`. `mouse`: 0 none, 1 clicks and drags, 2 also motion. `vapor.input(false)` restores the console (also restored on exit) |
| events | stable | `"char", text` · `"key", name, mods` (1 shift, 2 alt, 4 ctrl) · `"mouse", action, button, x, y, mods` (press, release, drag, move, scroll_up, scroll_down; 1-based) · `"resize", cols, rows` · `"quit"` when input ends |
| `vapor.size()` | stable | `cols, rows` of the console, or `nil` |
| `vapor.console_read/raw/size` | internal | the platform calls behind `input`/`size` |
| `vapor.decode`, `decode_flush`, `decode_pending` | internal | terminal byte decoder (tested in `tests/decode.lua`) |

Key names: `up down left right home end insert delete pageup pagedown enter tab backspace escape f1..f12 space`, or the ASCII letter for Ctrl/Alt combinations.
While `input` is on, the console belongs to the events: do not also read it with `io.read` or `wait_fd(0)`.

## Filesystem (becomes the optional `vapor.fs` module)

| call | | meaning |
|---|---|---|
| `vapor.fs.list(path)` | stable | array of names, or `nil, err` |
| `vapor.fs.stat(path)` | stable | `{type="file"\|"dir"\|..., size=, mtime=}` or `nil, err` |
| `vapor.fs.mkdir(path)` / `vapor.fs.rmdir(path)` | stable | `true` or `nil, err` (what `os.remove` cannot do for directories on Windows) |

## Process

`os.execute` works as in Lua (`vapor.caps.exec`); `os.exit` closes the Lua state first so finalizers run. Both are standard names, not `vapor.*`.

## Not in 0.1 (planned, experimental when they appear)

`vapor.net` (TCP/UDP/DNS), `vapor.spawn_process` (subprocess with pipes), `vapor.worker`, `vapor.gfx`, application manifests, `vapor.sandbox`.
