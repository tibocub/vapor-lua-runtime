#include "lua.h"
#include "lauxlib.h"
int luaL_typerror(lua_State *L, int narg, const char *tname) { return luaL_error(L, "own typerror %d %s", narg, tname); }
static int bad(lua_State *L) { return luaL_typerror(L, 1, "thing"); }
int luaopen_ownmod(lua_State *L) { lua_pushcfunction(L, bad); return 1; }
