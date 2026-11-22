#include "lua.h"
#include "lauxlib.h"
static int len(lua_State *L) { lua_pushinteger(L, (lua_Integer)lua_objlen(L, 1) + luaL_checkint(L, 2)); return 1; }
static int same(lua_State *L) { lua_pushboolean(L, lua_equal(L, 1, 2)); return 1; }
static const luaL_reg funcs[] = { {"len", len}, {"same", same}, {NULL, NULL} };
int luaopen_oldstyle_core(lua_State *L) { luaL_register(L, "oldstyle.core", funcs); return 1; }
