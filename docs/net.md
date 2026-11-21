# vapor.net and vapor.stream (experimental)

Networking for tasks. Nothing blocks the process; only the calling task waits. `vapor.caps.net` is true where the platform has sockets
and the build includes `vapor.net` (posix, Windows; not wasm, not NuttX boards without a network stack).

    local net = require("vapor.net")
    local c = net.connect("example.org", 80, 5)      -- host, port, timeout (seconds, optional); returns a stream, or nil, err
    c:write("GET / HTTP/1.0\r\nHost: example.org\r\n\r\n")
    for line in c:lines() do print(line) end
    c:close()

    local srv = net.listen("127.0.0.1", 8080)        -- host nil = all interfaces, port 0 = any (srv:port() tells)
    vapor.spawn(function() local c = srv:accept(); c:write("hi\n"); c:close() end)

    local u = net.udp("127.0.0.1", 0)                -- u:sendto(data, host, port), u:recvfrom(timeout) -> data, addr, port, u:port()

## Streams

A stream is one file-like object over any non-blocking byte source; sockets are the first user (pipes, files and the console can follow).
`read(fmt)` with a number of bytes, `"l"`, `"L"`, `"a"` (a leading `*` is accepted, as in 5.1); `readsome(max)` for streaming (returns as soon as
any byte arrived, `nil, "eof"` at the end); `write(...)` waits when the socket buffer is full (backpressure, tested with a 100 KB write against a slow reader);
`lines()`, `chunks(max)`, `settimeout(seconds)` (reads and writes then return `nil, "timeout"`), `close()`.
Node-style on top of the same object: `s:on("data" | "end" | "error" | "close", fn)` starts a task that reads for you, and
`require("vapor.stream").pipe(src, dst)` copies with backpressure. Both are thin Lua over the coroutine API; the coroutine style stays the primary one.

Platform side (`vlr_platform.h`, section Networking): `vlr_net_*` with handles that `vlr_wait` understands; `VLR_WRITABLE` or'ed into a handle waits for
writability (connect completion, send). `src/net_posix.c` (also NuttX with CONFIG_NET), `src/net_win32.c` (Winsock, `WSAPoll`), `src/net_none.c` (wasm: calls fail).
The module list picks the target half through `@PLAT@` in `modules.conf`.

## Shortcuts to revisit
- Name resolution (`getaddrinfo`) blocks the whole process while it runs. Fix: a resolver handle in the platform (thread or async resolver).
- No TLS yet (planned: verification on by default). No IPv6-only options, no socket options (`setsockopt`) exposed, no `shutdown` half-close.
- Windows: while the console is also waited on, polling is 10 ms slices (sockets alone get an exact wait).
- The luasocket-compatible API (`std.socket`) is the planned next layer so existing Lua network libraries run unchanged.
