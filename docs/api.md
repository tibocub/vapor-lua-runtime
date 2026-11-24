# vlr API reference (version 0.2)

Stability: **stable** = frozen since 0.2 (semantic versioning on `vlr.version`; breaking changes only in a major release).
**experimental** = may change, graduates after real use. **internal** = used by the embedded Lua code, not part of the API.
Since 0.2 the names marked stable are frozen. Tests in `tests/` are the executable spec.

**These are vlr's internals, for people working on the runtime.** Portable code uses the official libraries (`socket`, `ssl`, `copas`, `lfs`, ...) and never `require("vlr")`. The functions live on the table `require("vlr")` returns.
"Task" = a coroutine started with `vlr.spawn`, or the main script, which is itself a task.

## Identity

| name | | |
|---|---|---|
| `vlr.version` | stable | string `"major.minor.patch"` |
| `vlr.platform` | stable | `"linux"`, `"windows"`, `"macos"`, `"nuttx"`, `"wasm"`, `"posix"` |
| `vlr.dialect` | stable | `"5.1"` (default compat layer) or `"5.4"` (`--dialect=5.4`) |
| `vlr.caps` | stable | table of booleans: `fs`, `net`, `gfx`, `tty`, `dlopen`, `exec`. Check before using an optional area |
| `vlr.builtin` | stable | set of compiled-in native module names (`vlr.builtin.lfs == true`); matches `package.preload` |

## Tasks, time and events (core)

| call | | meaning |
|---|---|---|
| `vlr.spawn(fn, ...)` | stable | start a task; returns its coroutine |
| `vlr.sleep(seconds)` | stable | pause this task; other tasks run (millisecond resolution) |
| `vlr.wait_fd(fd, timeout?, mode?)` | stable | wait until the handle is readable (`mode "w"`: writable); returns `fd`, or `nil, "timeout"`. Handle 0 = console input; other handles are backend specific |
| `vlr.pull(timeout?)` | stable | next event `(name, ...)` or `nil, "timeout"` |
| `vlr.push(name, ...)` | stable | queue an event (wakes a task blocked in `pull`) |
| `vlr.timer(seconds)` | stable | pushes `("timer", id)` after the delay; returns `id` |
| `vlr.run()` | stable | run until no task has anything left to wait for; returns when done |
| `vlr.step(max_ms?)` | stable | one loop turn for a host that owns the main loop (browser, GUI): returns ms to the next timer, `-1` if only waiting on handles, `nil` when done |
| `vlr.failed()` | stable | true if any task died with an error (the script exit status uses it) |
| `vlr.now()` | stable | monotonic milliseconds |

## Not in vlr

Console input and the cell screen are the `vlrui` rock (vlrUI's `bindings/lua`), the file system is `lfs`, JSON is `cjson`; there are no
app folders or manifests (use vpm). `os.execute` works as in Lua; `os.exit` closes the Lua state first so finalizers run.

## Networking, TLS, HTTP, signatures (all experimental; see [net.md](net.md))

| module | | meaning |
|---|---|---|
| `vlr.net`, `vlr.stream` | experimental | TCP/UDP for tasks, file-like streams (`read`, `readsome`, `write`, `lines`, `settimeout`, `on`, `pipe`); `net.connect/listen/udp/resolve`; names resolve without stopping other tasks |
| `vlr.tls` | experimental | `tls.connect(host, port, opts)`, `tls.wrap(sock, host, opts)`; chain and host name always verified; roots from files, the Windows store, built-in list |
| `socket`, `socket.http`, `ltn12`, `mime` | experimental | LuaSocket-compatible subset so luasocket-based rocks run unmodified |
| `ssl`, `ssl.https` | experimental | LuaSec client API: `ssl.wrap(sock, params)`, `:sni(host)`, `:dohandshake()`, `https.request`. Always verifies chain and host name (see the header of `lua/ssl.lua` for the differences) |
| `ed25519` | experimental | `ed25519.verify(signature, message, public_key)` (the `ed25519` rock, Monocypher). |
| `vlr.close_fd(handle)` | experimental | wake tasks waiting on a handle about to be closed (`nil, "closed"`) |

`vlr.caps.net` says whether the build and platform have sockets.

## Interactive use

`vlr` with no script (or `vlr -i`) starts the prompt (`vlr.repl`); `vlr -e 'code'` runs a chunk. Experimental.

## Not yet (planned, experimental when they appear)

`vlr.spawn_process` (subprocess with pipes), `vlr.worker`, `vlr.gfx`, `vlr.sandbox`.
