/* vapor.term: console access and the terminal byte decoder (platform: vlr_console_*, decoder: vtinput.c).
   The Lua side is lua/input.lua (vapor.input). Optional module "vapor.term". */
#include "lauxlib.h"
#include "lua.h"
#include "vlr_platform.h"
#include "vtinput.h"

/* ---- input events: terminal bytes -> {name, args...} tuples (see lua/input.lua) ---- */

static void push_event(lua_State *L, const vtev *e, int *n)
{
    lua_newtable(L);
    if (e->type == VT_CHAR) {
        lua_pushstring(L, "char");
        lua_rawseti(L, -2, 1);
        lua_pushstring(L, e->text);
        lua_rawseti(L, -2, 2);
    } else if (e->type == VT_KEY) {
        lua_pushstring(L, "key");
        lua_rawseti(L, -2, 1);
        lua_pushstring(L, e->code ? vtinput_keyname(e->code) : e->text);
        lua_rawseti(L, -2, 2);
        lua_pushinteger(L, e->mods);
        lua_rawseti(L, -2, 3);
    } else {
        static const char *const act[] = {"", "press", "release", "drag", "move", "scroll_up", "scroll_down"};

        lua_pushstring(L, "mouse");
        lua_rawseti(L, -2, 1);
        lua_pushstring(L, act[e->action]);
        lua_rawseti(L, -2, 2);
        lua_pushinteger(L, e->code);
        lua_rawseti(L, -2, 3);
        lua_pushinteger(L, e->x);
        lua_rawseti(L, -2, 4);
        lua_pushinteger(L, e->y);
        lua_rawseti(L, -2, 5);
        lua_pushinteger(L, e->mods);
        lua_rawseti(L, -2, 6);
    }
    lua_rawseti(L, -2, ++*n);
}

/* vapor.decode(bytes) -> array of event tuples; the decoder keeps state between calls (split escape sequences) */
static int l_decode(lua_State *L)
{
    vtinput *d = lua_touserdata(L, lua_upvalueindex(1));
    size_t len, i;
    const char *s = luaL_checklstring(L, 1, &len);
    int n = 0;
    vtev e;

    lua_newtable(L);
    for (i = 0; i < len; i++) {
        if (vtinput_feed(d, (unsigned char)s[i], &e)) push_event(L, &e, &n);
    }
    return 1;
}

/* vapor.decode_flush() -> array: reports a pending lone ESC as the Escape key; drops half a sequence */
static int l_decode_flush(lua_State *L)
{
    vtinput *d = lua_touserdata(L, lua_upvalueindex(1));
    int n = 0;
    vtev e;

    lua_newtable(L);
    if (vtinput_flush(d, &e)) push_event(L, &e, &n);
    return 1;
}

static int l_decode_pending(lua_State *L)
{
    lua_pushboolean(L, vtinput_pending(lua_touserdata(L, lua_upvalueindex(1))));
    return 1;
}

/* vapor.console_read(max) -> bytes ("" if none yet) or nil at end of input */
static int l_console_read(lua_State *L)
{
    char buf[256];
    int n = (int)luaL_optinteger(L, 1, (lua_Integer)sizeof buf), r;

    if (n > (int)sizeof buf) n = (int)sizeof buf;
    r = vlr_console_read(buf, n);
    if (r < 0) { lua_pushnil(L); return 1; }
    lua_pushlstring(L, buf, (size_t)r);
    return 1;
}

static int l_console_raw(lua_State *L)
{
    lua_pushboolean(L, vlr_console_raw(lua_toboolean(L, 1)) == 0);
    return 1;
}

static int l_console_size(lua_State *L)
{
    int c, r;

    if (vlr_console_size(&c, &r) != 0) { lua_pushnil(L); return 1; }
    lua_pushinteger(L, c);
    lua_pushinteger(L, r);
    return 2;
}


int luaopen_vapor_term(lua_State *L)
{
    static const luaL_Reg funcs[] = {{"console_read", l_console_read}, {"console_raw", l_console_raw},
                                     {"console_size", l_console_size}, {NULL, NULL}};
    static const luaL_Reg decfuncs[] = {{"decode", l_decode}, {"decode_flush", l_decode_flush},
                                        {"decode_pending", l_decode_pending}, {NULL, NULL}};
    vtinput *d;

    luaL_newlib(L, funcs);
    d = lua_newuserdatauv(L, sizeof *d, 0); /* the decoder is the shared upvalue of the three decode functions */
    vtinput_init(d);
    luaL_setfuncs(L, decfuncs, 1);
    return 1;
}
