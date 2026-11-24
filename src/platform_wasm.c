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
    vlr_flush();
    g_L = NULL;
    if (!js_exit(r)) emscripten_force_exit(r);
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

/*
 * The page pushes input events itself (no terminal to decode): vlr.push(name, s, ints...) with nint integers.
 * char: ("char", text)   key: ("key", name, mods)   mouse: ("mouse", action, button, x, y, mods)   resize: ("resize", cols, rows)
 * (s may be NULL for resize).
 */
EMSCRIPTEN_KEEPALIVE void vlr_wasm_push(const char *name, const char *s, int nint, int a, int b, int c, int d)
{
    int ints[4], i;

    if (g_L == NULL) return;
    ints[0] = a; ints[1] = b; ints[2] = c; ints[3] = d;
    lua_getfield(g_L, LUA_REGISTRYINDEX, "_LOADED");
    lua_getfield(g_L, -1, "vlr");
    lua_remove(g_L, -2);
    lua_getfield(g_L, -1, "push");
    lua_remove(g_L, -2);
    lua_pushstring(g_L, name);
    if (s != NULL) lua_pushstring(g_L, s);
    for (i = 0; i < nint && i < 4; i++) lua_pushinteger(g_L, ints[i]);
    if (lua_pcall(g_L, 1 + (s != NULL) + (nint < 4 ? nint : 4), 0, 0) != LUA_OK) lua_pop(g_L, 1);
    vlr_wasm_wake();
}
