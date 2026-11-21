#include "lua.h"
#include "lauxlib.h"
static int twice(lua_State *L) { lua_pushinteger(L, 2 * luaL_checkinteger(L, 1)); return 1; }
int luaopen_toy(lua_State *L) { lua_newtable(L); lua_pushcfunction(L, twice); lua_setfield(L, -2, "twice"); return 1; }
