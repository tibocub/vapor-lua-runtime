/* vapor.term: console access and the terminal byte decoder (platform: vlr_console_*, decoder: vtinput.c).
   The Lua side is lua/input.lua (vapor.input). Optional module "vapor.term". */
#include "lauxlib.h"
#include "lua.h"
#include "vlr_platform.h"
#include "input.h" /* vaporUI */

/* ---- input events: terminal bytes -> {name, args...} tuples (see lua/input.lua) ----
   The decoder is vaporUI's (src/input.c, vt.c, utf8.c, scancode.c; a sibling checkout, @EXT@/vaporUI): UTF-8, control keys, Alt,
   CSI/SS3 keys with modifiers, kitty and modifyOtherKeys, SGR mouse, bracketed paste. Here its events become tuples. */

static const char *const keynames[] = {"", "", "enter", "backspace", "tab", "escape", "delete", "up", "down", "left", "right",
                                       "home", "end", "pageup", "pagedown", "insert"};

static void put(lua_State *L, int i) { lua_rawseti(L, -2, i); }

/* appends the tuple for e to the result table at the top (nothing for events that have no tuple) */
static void push_event(lua_State *L, const VuiEvent *e, int *n)
{
    switch (e->type) {
    case VUI_EVENT_TEXT:
        lua_createtable(L, 2, 0);
        lua_pushliteral(L, "char"); put(L, 1);
        lua_pushfstring(L, "%U", (long)e->text.codepoint); put(L, 2);
        break;
    case VUI_EVENT_KEY: {
        const VuiKeyEvent *k = &e->key;

        lua_createtable(L, 5, 0);
        lua_pushliteral(L, "key"); put(L, 1);
        if (k->key == VUI_KEY_CHAR) lua_pushfstring(L, "%U", (long)k->character);
        else if (k->key >= VUI_KEY_F1) lua_pushfstring(L, "f%d", (int)(k->key - VUI_KEY_F1 + 1));
        else lua_pushstring(L, keynames[k->key]);
        put(L, 2);
        lua_pushinteger(L, (int)k->modifiers); put(L, 3);
        /* extras for characters: the key's US-layout character and its physical key (USB HID number, 0 if unknown) */
        if (k->key == VUI_KEY_CHAR && k->base) lua_pushfstring(L, "%U", (long)k->base);
        else lua_pushliteral(L, ""); /* never nil: tuples stay dense for table.concat / unpack */
        put(L, 4);
        lua_pushinteger(L, (int)k->scancode); put(L, 5);
        break;
    }
    case VUI_EVENT_MOUSE: {
        const VuiMouseEvent *m = &e->mouse;
        const char *act;
        int button = 0;

        switch (m->button) {
        case VUI_MOUSE_LEFT: button = 1; break;
        case VUI_MOUSE_MIDDLE: button = 2; break;
        case VUI_MOUSE_RIGHT: button = 3; break;
        default: break;
        }
        if (m->button == VUI_MOUSE_WHEEL_UP) act = "scroll_up";
        else if (m->button == VUI_MOUSE_WHEEL_DOWN) act = "scroll_down";
        else if (m->button == VUI_MOUSE_WHEEL_LEFT || m->button == VUI_MOUSE_WHEEL_RIGHT) return; /* no tuple for sideways wheels yet */
        else if (m->action == VUI_MOUSE_PRESS) act = "press";
        else if (m->action == VUI_MOUSE_RELEASE) act = "release";
        else act = button ? "drag" : "move";
        lua_createtable(L, 6, 0);
        lua_pushliteral(L, "mouse"); put(L, 1);
        lua_pushstring(L, act); put(L, 2);
        lua_pushinteger(L, button); put(L, 3);
        lua_pushinteger(L, (lua_Integer)m->x + 1); put(L, 4); /* 1-based */
        lua_pushinteger(L, (lua_Integer)m->y + 1); put(L, 5);
        lua_pushinteger(L, (int)m->modifiers); put(L, 6);
        break;
    }
    case VUI_EVENT_PASTE_START:
    case VUI_EVENT_PASTE_END:
        lua_createtable(L, 2, 0);
        lua_pushliteral(L, "paste"); put(L, 1);
        lua_pushstring(L, e->type == VUI_EVENT_PASTE_START ? "start" : "end"); put(L, 2);
        break;
    default:
        return;
    }
    lua_rawseti(L, -2, ++*n);
}

/* vapor.decode(bytes) -> array of event tuples; the decoder keeps state between calls (split escape sequences) */
static int l_decode(lua_State *L)
{
    VuiInputDecoder *d = lua_touserdata(L, lua_upvalueindex(1));
    size_t len, i;
    const char *s = luaL_checklstring(L, 1, &len);
    int n = 0;

    lua_newtable(L);
    for (i = 0; i < len; i++) {
        VuiEvent e = vui_input_feed(d, (unsigned char)s[i]);

        push_event(L, &e, &n);
    }
    return 1;
}

/* vapor.decode_flush() -> array: reports a pending lone ESC as the Escape key; drops half a sequence */
static int l_decode_flush(lua_State *L)
{
    VuiInputDecoder *d = lua_touserdata(L, lua_upvalueindex(1));
    int n = 0;
    VuiEvent e = vui_input_timeout(d);

    lua_newtable(L);
    push_event(L, &e, &n);
    return 1;
}

static int l_decode_pending(lua_State *L)
{
    lua_pushboolean(L, vui_input_pending_escape(lua_touserdata(L, lua_upvalueindex(1))));
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
    /* true/false, or 0/1/2 (2 = with mouse) */
    lua_pushboolean(L, vlr_console_raw(lua_isboolean(L, 1) ? lua_toboolean(L, 1) : (int)luaL_checkinteger(L, 1)) == 0);
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
    VuiInputDecoder *d;

    luaL_newlib(L, funcs);
    d = lua_newuserdatauv(L, sizeof *d, 0); /* the decoder is the shared upvalue of the three decode functions */
    vui_input_reset(d);
    luaL_setfuncs(L, decfuncs, 1);
    return 1;
}
