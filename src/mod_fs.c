/* vapor.fs: what plain Lua lacks for the filesystem (list, stat, mkdir, rmdir) over vlr_fs_*. Optional module "vapor.fs". */
#include "lauxlib.h"
#include "lua.h"
#include "vlr_platform.h"

static int fail(lua_State *L)
{
    lua_pushnil(L);
    lua_pushstring(L, vlr_last_error());
    return 2;
}

static int list_cb(void *ud, const char *name)
{
    lua_State *L = ud;
    lua_pushstring(L, name);
    lua_rawseti(L, -2, (lua_Integer)lua_rawlen(L, -2) + 1);
    return 0;
}

static int l_list(lua_State *L)
{
    const char *path = luaL_checkstring(L, 1);
    lua_newtable(L);
    return vlr_fs_list(path, list_cb, L) == 0 ? 1 : (lua_pop(L, 1), fail(L));
}

static int l_mkdir(lua_State *L)
{
    if (vlr_fs_mkdir(luaL_checkstring(L, 1)) != 0) return fail(L);
    lua_pushboolean(L, 1);
    return 1;
}

static int l_rmdir(lua_State *L)
{
    if (vlr_fs_rmdir(luaL_checkstring(L, 1)) != 0) return fail(L);
    lua_pushboolean(L, 1);
    return 1;
}

static int l_stat(lua_State *L)
{
    vlr_stat st;

    if (vlr_fs_stat(luaL_checkstring(L, 1), &st) != 0) return fail(L);
    lua_createtable(L, 0, 3);
    lua_pushstring(L, st.is_dir ? "dir" : "file");
    lua_setfield(L, -2, "type");
    lua_pushinteger(L, (lua_Integer)st.size);
    lua_setfield(L, -2, "size");
    lua_pushinteger(L, (lua_Integer)st.mtime);
    lua_setfield(L, -2, "mtime");
    return 1;
}


int luaopen_vapor_fs(lua_State *L)
{
    static const luaL_Reg funcs[] = {{"list", l_list}, {"mkdir", l_mkdir}, {"rmdir", l_rmdir}, {"stat", l_stat}, {NULL, NULL}};

    luaL_newlib(L, funcs);
    return 1;
}
