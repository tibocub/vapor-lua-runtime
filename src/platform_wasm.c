/*
 * vlr backend for WebAssembly (emscripten, built with -sASYNCIFY). The browser cannot block, so vlr_wait parks the wasm stack
 * on a JS promise (a timer, or console input arriving) and the C code above stays synchronous, as on any other host. Time and
 * the filesystem (emscripten's MEMFS/NODERAWFS) come from platform_posix.c built with -DVLR_POSIX_NO_WAIT.
 * Terminal input and the screen are the vaporui module, on vaporUI's own wasm backend (Module.vui, see web/vlr-glue.js).
 */
#include <emscripten.h>
#include <stdio.h>
#include <string.h>

#include "vlr.h"
#include "vlr_platform.h"

/* stdin (handle 0) is readable when the page says so: Module.vlrStdinReady() (default: always, like /dev/null) */
EM_JS(int, js_stdin_ready, (void), { return Module.vlrStdinReady ? (Module.vlrStdinReady() ? 1 : 0) : 1; });

/* wait up to ms (-1: until woken) for a timer or for Module.vlrWake(); resolves when either happens */
EM_ASYNC_JS(void, js_sleep, (int ms), {
  await new Promise((res) => {
    let t = null;
    const done = () => { if (t !== null) clearTimeout(t); Module.vlrWake = null; res(); };
    Module.vlrWake = done;
    if (ms >= 0) t = setTimeout(done, ms);
  });
});

/* browsers: tell the page the script ended (Module.onVlrExit(code)); returns 0 when nobody listens (Node: exit) */
EM_JS(int, js_exit, (int code), { if (Module.onVlrExit) { Module.onVlrExit(code); return 1; } return 0; });

/* emscripten keeps a partial last line of stdout/stderr in JS until a newline: push it out */
EM_JS(void, js_flush_tty, (void), {
  for (const fd of [1, 2]) { const s = FS.streams[fd]; if (s && s.tty && s.tty.ops.fsync) s.tty.ops.fsync(s.tty); }
});

void vlr_flush(void)
{
    fflush(NULL);
    js_flush_tty();
}

uint32_t vlr_caps(void) { return VLR_CAP_FS | VLR_CAP_TTY; }

int vlr_wait(const int *fds, int n, int *ready, int timeout_ms)
{
    int i, count = 0, watch0 = 0;

    for (i = 0; i < n; i++) {
        ready[i] = fds[i] == 0 && js_stdin_ready();
        count += ready[i];
        watch0 |= fds[i] == 0;
    }
    if (count > 0 || timeout_ms == 0) return count;
    /* shortcut: stdin has no event to wait on, so poll it every 20 ms while a script waits for it */
    for (;;) {
        int slice = watch0 && (timeout_ms < 0 || timeout_ms > 20) ? 20 : timeout_ms;

        js_sleep(slice);
        if (watch0 && js_stdin_ready()) {
            for (i = 0; i < n; i++) count += (ready[i] = fds[i] == 0);
            return count;
        }
        if (timeout_ms >= 0) timeout_ms -= slice;
        if (!watch0 || timeout_ms == 0) return 0;
    }
}

void vlr_wasm_exit(int code)
{
    vlr_flush();
    if (!js_exit(code)) emscripten_force_exit(code);
}
