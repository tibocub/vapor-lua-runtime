#ifndef VLR_H
#define VLR_H
#include "lua.h"

/* dialect51: 1 = Lua 5.1 compatible globals and number printing (default), 0 = plain 5.4 */
lua_State *vlr_newstate(int dialect51);

/* runs path as the main task, then the scheduler until nothing is left; returns a process exit code */
int vlr_run_file(lua_State *L, const char *path, int argc, char **argv);

#endif
