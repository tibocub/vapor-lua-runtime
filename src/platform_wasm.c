/*
 * vlr backend for WebAssembly (emscripten, no Asyncify). The browser cannot block, so vlr_wait never does: it
 * reports what is ready right now and the JS event loop calls back into vlr_step (via timers). Time, filesystem
 * (emscripten's MEMFS/NODERAWFS) come from platform_posix.c built with -DVLR_POSIX_NO_WAIT.
 */
#include <emscripten.h>
#include <stdio.h>

#include "vlr.h"
#include "vlr_platform.h"

/* the page decides when console input is readable: Module.vlrStdinReady() (default: always, like /dev/null) */
EM_JS(int, js_stdin_ready, (void), { return Module.vlrStdinReady ? (Module.vlrStdinReady() ? 1 : 0) : 1; });

uint32_t vlr_caps(void) { return VLR_CAP_FS; }

int vlr_wait(const int *fds, int n, int *ready, int timeout_ms)
{
    int i, count = 0;

    (void)timeout_ms; /* never sleeps: the JS timer that called us is the sleep */
    for (i = 0; i < n; i++) count += (ready[i] = fds[i] == 0 && js_stdin_ready());
    return count;
}

static lua_State *g_L;

static void tick(void *unused)
{
    int next = -1, r;

    (void)unused;
    r = vlr_step(g_L, 0, &next);
    if (r > 0) {
        /* shortcut: when only waiting on input poll every 20 ms; the page should call vlr_wasm_wake() instead */
        emscripten_async_call(tick, NULL, next < 0 ? 20 : next);
        return;
    }
    r = r < 0 || vlr_failed(g_L);
    lua_close(g_L);
    emscripten_force_exit(r);
}

/* page calls this when input arrives, to run the loop now */
EMSCRIPTEN_KEEPALIVE void vlr_wasm_wake(void)
{
    if (g_L != NULL) emscripten_async_call(tick, NULL, 0);
}

void vlr_wasm_run(lua_State *L)
{
    g_L = L;
    emscripten_async_call(tick, NULL, 0);
}
