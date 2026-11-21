#ifndef VLR_H
#define VLR_H
#include "lua.h"

/*
 * dialect51: 1 = Lua 5.1 compatible globals and number printing (default), 0 = plain 5.4.
 * alloc/ud: allocator for the Lua state, or NULL for the default (a capped allocator goes here, see the sandbox
 * in docs/spec.md).
 */
lua_State *vlr_newstate(int dialect51, lua_Alloc alloc, void *ud);

/* loads path and starts it as the main task (not yet run). Returns 0, or 1 with a message on stderr */
int vlr_spawn_file(lua_State *L, const char *path, int argc, char **argv);

/* the same for a chunk of source text (vlr -e, the REPL) */
int vlr_spawn_string(lua_State *L, const char *code, int argc, char **argv);

/*
 * One scheduler turn for hosts that own the main loop: waits at most max_ms (-1 = until something is due).
 * Returns 1 if work remains (*next_ms = ms until the next timer, -1 if only waiting on input), 0 if everything is
 * finished, -1 on error. next_ms may be NULL.
 */
int vlr_step(lua_State *L, int max_ms, int *next_ms);

/* 1 if any task raised an error */
int vlr_failed(lua_State *L);

/* spawn path and run to completion; returns a process exit code */
int vlr_run_file(lua_State *L, const char *path, int argc, char **argv);

#endif
