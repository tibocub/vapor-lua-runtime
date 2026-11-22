#include "lua.h"
#include "lauxlib.h"
static int add(lua_State *L) { lua_pushinteger(L, luaL_checkinteger(L, 1) + luaL_checkinteger(L, 2)); return 1; }
int luaopen_nativehello(lua_State *L) { lua_newtable(L); lua_pushcfunction(L, add); lua_setfield(L, -2, "add"); return 1; }
