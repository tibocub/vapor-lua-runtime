# vlr.net and vlr.stream (experimental)

Networking for tasks. Nothing blocks the process; only the calling task waits. `vlr.caps.net` is true where the platform has sockets
and the build includes `vlr.net` (posix, Windows; not wasm, not NuttX boards without a network stack).

    local net = require("vlr.net")
    local c = net.connect("example.org", 80, 5)      -- host, port, timeout (seconds, optional); returns a stream, or nil, err
    c:write("GET / HTTP/1.0\r\nHost: example.org\r\n\r\n")
    for line in c:lines() do print(line) end
    c:close()

    local srv = net.listen("127.0.0.1", 8080)        -- host nil = all interfaces, port 0 = any (srv:port() tells)
    vlr.spawn(function() local c = srv:accept(); c:write("hi\n"); c:close() end)

    local u = net.udp("127.0.0.1", 0)                -- u:sendto(data, host, port), u:recvfrom(timeout) -> data, addr, port, u:port()

## Streams

A stream is one file-like object over any non-blocking byte source; sockets are the first user (pipes, files and the console can follow).
`read(fmt)` with a number of bytes, `"l"`, `"L"`, `"a"` (a leading `*` is accepted, as in 5.1); `readsome(max)` for streaming (returns as soon as
any byte arrived, `nil, "eof"` at the end); `write(...)` waits when the socket buffer is full (backpressure, tested with a 100 KB write against a slow reader);
`lines()`, `chunks(max)`, `settimeout(seconds)` (reads and writes then return `nil, "timeout"`), `close()`.
Node-style on top of the same object: `s:on("data" | "end" | "error" | "close", fn)` starts a task that reads for you, and
`require("vlr.stream").pipe(src, dst)` copies with backpressure. Both are thin Lua over the coroutine API; the coroutine style stays the primary one.

Platform side (`vlr_platform.h`, section Networking): `vlr_net_*` with handles that `vlr_wait` understands; `VLR_WRITABLE` or'ed into a handle waits for
writability (connect completion, send). `src/net_posix.c` (also NuttX with CONFIG_NET), `src/net_win32.c` (Winsock, `WSAPoll`), `src/net_none.c` (wasm: calls fail).
The module list picks the target half through `@PLAT@` in `modules.conf`.

## Shortcuts to revisit
- Name resolution (`getaddrinfo`) blocks the whole process while it runs. Fix: a resolver handle in the platform (thread or async resolver).
- No TLS yet (planned: verification on by default). No IPv6-only options, no socket options (`setsockopt`) exposed, no `shutdown` half-close.
- Windows: while the console is also waited on, polling is 10 ms slices (sockets alone get an exact wait).
- The luasocket-compatible API (`std.socket`) is the planned next layer so existing Lua network libraries run unchanged.

## TLS (`vlr.tls`)

    local tls = require("vlr.tls")
    local s, err = tls.connect("example.com", 443)       -- a stream like vlr.net's; handshake done
    s:write("GET / HTTP/1.1\r\nHost: example.com\r\nConnection: close\r\n\r\n"); print(s:read("l"))
    tls.wrap(sock, host, opts)                           -- over an already connected socket stream

The chain and the host name are **always** verified; there is no option to skip that. Trust: `opts.ca` (PEM text or `tls.anchors(pem)`), `opts.cafile`,
then `$VLR_CA_FILE`, `$SSL_CERT_FILE`, then the usual system bundles (Linux, macOS, BSD). On Windows the trusted roots come from the system certificate store
(read once per process; untested on real Windows until the next report). Errors say what failed: unknown issuer, expired, wrong host name.

Design: `vlr.tlsraw` is an engine without I/O (BearSSL, sibling checkout `../BearSSL`, `tests` pinned in CI); `lua/tls.lua` moves bytes between it and the
socket, so waiting stays in the scheduler. Another backend (mbedTLS on NuttX, OpenSSL/Schannel later, browser fetch on wasm) only has to offer the same
`anchors/client/state/take/put/send/recv/flush/close/error` calls. A peer closing the transport without `close_notify` reads as end of data.
Tests: `tests/tls/run.sh` (local `openssl s_server` with a good certificate, a wrong-name one and an untrusted one); a manual check against
`example.com`, `expired.badssl.com` and `wrong.host.badssl.com` passes. Costs about 390 KB of code on the host: the module is optional (profiles).

## HTTP client

`socket.http` and `ssl.https` (the luasocket and luasec APIs, below) are the HTTP client. There is no vlr-specific one.

## Closing a handle someone waits on
`vlr.close_fd(handle)` (called by every `close` in `vlr.net`) wakes the tasks waiting on that handle with `nil, "closed"`. Without it a task blocked in
`accept`/`read` on a socket another task closes would never wake on Windows (a closed socket in a WSAPoll set stays silent). `tests/net.lua` covers it.

## LuaSocket compatibility (`socket`)
A LuaSocket-compatible subset over `vlr.net`, so pure-Lua rocks written for luasocket run unmodified: `socket.tcp()` (connect, bind/listen/accept, send, receive with
`*l`/`*L`/`*a`/count and a prefix, settimeout, getpeername/getsockname, close), `socket.bind`, `socket.udp()` (sendto, receivefrom, setpeername), `socket.select`,
`socket.gettime/sleep`, `socket.try/newtry/protect/skip`, `socket.dns` (stubs). Timeouts and errors use luasocket's strings (`"timeout"`, `"closed"`) and a receive timeout returns the
partial data as third result. Shortcuts: `select` polls every 5 ms; `dns.toip` does not resolve; luasocket's helper modules (url, ltn12, mime, http, smtp, ftp) are separate rocks.
Test: `tests/socket.lua`. Run it inside a coroutine-aware task: like all of vlr.net it needs the scheduler (the main script is one).

### Trusted roots, where they come from
`opts.ca` / `opts.cafile` / `$VLR_CA_FILE` / `$SSL_CERT_FILE` / the usual bundle files win. With none of them (Windows, boards without files) vlr uses the Windows certificate store **plus**
the built-in Mozilla list `vlr.cacerts` (`lua/cacerts.lua`, 118 roots, regenerated by `tools/mkcacerts.sh`; about 180 KB of the binary, leave the module out of small builds).
Why both: a first Windows run showed the store alone is not enough (`example.com` was refused as "unknown issuer"): Windows keeps only some roots locally and downloads the others when
the OS itself builds a chain. Shortcut: the built-in list is as old as the build; update by regenerating it.

## Name resolution does not stop the process
`net.connect` resolves names through a worker thread (`vlr_net_resolve_start/result`: a pipe on POSIX, a loopback UDP socket on Windows, either waitable), so other tasks keep running during a slow lookup.
`net.resolve(host, timeout)` is the same step on its own. NuttX and wasm have no worker thread here: they keep the blocking lookup inside connect (the start call says "unsupported").
Shortcut: the first address returned is used (no Happy Eyeballs); `udp`/`listen`/`sendto` with a name still resolve blocking (they normally get numeric addresses).

## LuaSocket companions (2026-11-22)
`ltn12`, `mime`, `socket.url` and `socket.http` are pure Lua in vlr (`lua/ltn12.lua`, `mime.lua`, `socket_url.lua`, `socket_http.lua`), same APIs as LuaSocket 3, so rocks written for it run unmodified.
Shortcuts: `socket.http` is http-only (as in LuaSocket; https goes through `ssl.https`), no proxy, no keep-alive, `step` ignored; `mime.unb64` can drop bits when a chunk
boundary splits a 4-character group; qp/wrap/eol work per chunk; no `socket.smtp`, `ftp`, `headers`. `receive("*l")` now drops every CR like LuaSocket (it used to keep one).
