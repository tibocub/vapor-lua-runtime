/* vapor.ui: vaporUI's cell screen for Lua. A double-buffered grid you draw into; flush() writes only the cells that changed (ANSI on stdout).
   Input and the event loop stay with vapor.input; this module only draws. Coordinates are 1-based like the mouse events. Experimental. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "lauxlib.h"
#include "lua.h"
#include "vaporui.h"
#include "vlr_platform.h"

#define SCREEN_MT "vapor.ui.screen"

typedef struct { VuiScreen *scr; } screen_t;

static VuiScreen *check_screen(lua_State *L, int i)
{
    screen_t *s = luaL_checkudata(L, i, SCREEN_MT);

    if (s->scr == NULL) luaL_error(L, "screen is closed");
    return s->scr;
}

/* style: nil (terminal default), or {fg=, bg=, bold=, underline=, reverse=}; colors are 0 (default), 1..16 (ANSI), ui.rgb(...) or ui.color256(...) */
static VuiStyle get_style(lua_State *L, int i)
{
    VuiStyle st = {0, 0, VUI_ATTR_NONE};

    if (lua_isnoneornil(L, i)) return st;
    luaL_checktype(L, i, LUA_TTABLE);
    lua_getfield(L, i, "fg"); if (!lua_isnil(L, -1)) st.fg = (VuiColor)luaL_checkinteger(L, -1); lua_pop(L, 1);
    lua_getfield(L, i, "bg"); if (!lua_isnil(L, -1)) st.bg = (VuiColor)luaL_checkinteger(L, -1); lua_pop(L, 1);
    lua_getfield(L, i, "bold"); if (lua_toboolean(L, -1)) st.attr |= VUI_ATTR_BOLD; lua_pop(L, 1);
    lua_getfield(L, i, "underline"); if (lua_toboolean(L, -1)) st.attr |= VUI_ATTR_UNDERLINE; lua_pop(L, 1);
    lua_getfield(L, i, "reverse"); if (lua_toboolean(L, -1)) st.attr |= VUI_ATTR_REVERSE; lua_pop(L, 1);
    return st;
}

/* a character argument: a codepoint number, or a string whose first UTF-8 character is used */
static VuiCodepoint get_char(lua_State *L, int i)
{
    if (lua_type(L, i) == LUA_TNUMBER) return (VuiCodepoint)luaL_checkinteger(L, i);
    {
        size_t n;
        const unsigned char *s = (const unsigned char *)luaL_checklstring(L, i, &n);
        unsigned cp;
        int extra;

        if (n == 0) return ' ';
        if (s[0] < 0x80) return s[0];
        if (s[0] >= 0xF0) { cp = s[0] & 7; extra = 3; }
        else if (s[0] >= 0xE0) { cp = s[0] & 15; extra = 2; }
        else if (s[0] >= 0xC0) { cp = s[0] & 31; extra = 1; }
        else return 0xFFFD;
        for (int k = 1; k <= extra; k++) {
            if ((size_t)k >= n || (s[k] & 0xC0) != 0x80) return 0xFFFD;
            cp = (cp << 6) | (s[k] & 0x3F);
        }
        return cp;
    }
}

static unsigned int coord(lua_State *L, int i) { return (unsigned int)(luaL_checkinteger(L, i) - 1); } /* 1-based; 0 wraps to a huge value that clips away */

static int l_screen(lua_State *L)
{
    unsigned int w = (unsigned int)luaL_optinteger(L, 1, 0), h = (unsigned int)luaL_optinteger(L, 2, 0);
    screen_t *s;

    if (w == 0 || h == 0) {
        int cols = 80, rows = 24;

        if (vlr_console_size(&cols, &rows) != 0 || cols < 1 || rows < 1) { cols = 80; rows = 24; }
        if (w == 0) w = (unsigned int)cols;
        if (h == 0) h = (unsigned int)rows;
    }
    if (w > 1000 || h > 1000) return luaL_error(L, "screen too large");
    s = lua_newuserdatauv(L, sizeof *s, 0);
    s->scr = scr_create(w, h);
    if (s->scr == NULL) return luaL_error(L, "out of memory");
    luaL_setmetatable(L, SCREEN_MT);
    return 1;
}

static int s_set(lua_State *L)
{
    scr_set(check_screen(L, 1), coord(L, 2), coord(L, 3), get_char(L, 4), get_style(L, 5));
    return 0;
}

static int s_puts(lua_State *L)
{
    size_t n;
    const char *t = luaL_checklstring(L, 4, &n);

    scr_putn(check_screen(L, 1), coord(L, 2), coord(L, 3), t, n, get_style(L, 5));
    return 0;
}

static int s_fill(lua_State *L)
{
    VuiRect r;

    r.x = (int)luaL_checkinteger(L, 2) - 1;
    r.y = (int)luaL_checkinteger(L, 3) - 1;
    r.width = (unsigned int)luaL_checkinteger(L, 4);
    r.height = (unsigned int)luaL_checkinteger(L, 5);
    scr_fill(check_screen(L, 1), r, get_char(L, 6), get_style(L, 7));
    return 0;
}

static int s_clear(lua_State *L) { scr_clear(check_screen(L, 1), get_style(L, 2)); return 0; }
static int s_flush(lua_State *L) { scr_flush(check_screen(L, 1)); return 0; }

static int s_size(lua_State *L)
{
    VuiScreen *s = check_screen(L, 1);

    lua_pushinteger(L, scr_width(s));
    lua_pushinteger(L, scr_height(s));
    return 2;
}

static int s_resize(lua_State *L)
{
    unsigned int w = (unsigned int)luaL_checkinteger(L, 2), h = (unsigned int)luaL_checkinteger(L, 3);

    if (w == 0 || h == 0 || w > 1000 || h > 1000) return luaL_error(L, "bad screen size");
    scr_resize(check_screen(L, 1), w, h);
    return 0;
}

static int s_close(lua_State *L)
{
    screen_t *s = luaL_checkudata(L, 1, SCREEN_MT);

    if (s->scr != NULL) { scr_destroy(s->scr); s->scr = NULL; }
    return 0;
}

static int l_rgb(lua_State *L)
{
    lua_pushinteger(L, VUI_RGB(luaL_checkinteger(L, 1), luaL_checkinteger(L, 2), luaL_checkinteger(L, 3)));
    return 1;
}

static int l_color256(lua_State *L) { lua_pushinteger(L, VUI_COLOR256(luaL_checkinteger(L, 1))); return 1; }

static int l_width(lua_State *L) { lua_pushinteger(L, vui_str_width(luaL_checkstring(L, 1))); return 1; }

static int l_depth(lua_State *L) { vui_set_color_depth((int)luaL_checkinteger(L, 1)); return 0; }

/* alternate screen + hidden cursor, restored by leave() or when the state closes (os.exit, normal end) so a crash does not leave the terminal in it */
static int g_entered;

static void do_leave(void)
{
    if (g_entered) { fputs("\033[0m\033[?25h\033[?1049l", stdout); fflush(stdout); g_entered = 0; }
}

static int l_enter(lua_State *L)
{
    (void)L;
    if (!g_entered) { fputs("\033[?1049h\033[?25l\033[2J", stdout); fflush(stdout); g_entered = 1; }
    return 0;
}

static int l_leave(lua_State *L) { (void)L; do_leave(); return 0; }
static int l_guard_gc(lua_State *L) { (void)L; do_leave(); return 0; }

int luaopen_vapor_ui(lua_State *L)
{
    static const luaL_Reg methods[] = {
        {"set", s_set}, {"puts", s_puts}, {"fill", s_fill}, {"clear", s_clear}, {"flush", s_flush},
        {"size", s_size}, {"resize", s_resize}, {"close", s_close}, {NULL, NULL}};
    static const luaL_Reg funcs[] = {
        {"screen", l_screen}, {"rgb", l_rgb}, {"color256", l_color256}, {"width", l_width}, {"depth", l_depth},
        {"enter", l_enter}, {"leave", l_leave}, {NULL, NULL}};
    static const char *const names[] = {"default", "black", "red", "green", "yellow", "blue", "magenta", "cyan", "white", "gray",
                                        "bright_red", "bright_green", "bright_yellow", "bright_blue", "bright_magenta", "bright_cyan", "bright_white", NULL};
    const char *ct = getenv("COLORTERM"), *term = getenv("TERM");

    if (luaL_newmetatable(L, SCREEN_MT)) {
        lua_newtable(L);
        luaL_setfuncs(L, methods, 0);
        lua_setfield(L, -2, "__index");
        lua_pushcfunction(L, s_close);
        lua_setfield(L, -2, "__gc");
    }
    lua_pop(L, 1);
    luaL_newlib(L, funcs);
    lua_newtable(L);
    for (int i = 0; names[i] != NULL; i++) { lua_pushinteger(L, i); lua_setfield(L, -2, names[i]); }
    lua_setfield(L, -2, "color");
    /* colors the terminal can show: truecolor if it says so (Windows terminals do), else 256 or 16 by TERM */
#ifndef _WIN32
    if (!(ct != NULL && (strstr(ct, "truecolor") || strstr(ct, "24bit")))) {
        if (term != NULL && strstr(term, "256")) vui_set_color_depth(8);
        else if (term == NULL || strcmp(term, "linux") == 0 || strcmp(term, "dumb") == 0 || strcmp(term, "vt100") == 0) vui_set_color_depth(4);
    }
#else
    (void)ct; (void)term;
#endif
    lua_newuserdatauv(L, 1, 0); /* guard: closing the state leaves the alternate screen */
    lua_newtable(L);
    lua_pushcfunction(L, l_guard_gc);
    lua_setfield(L, -2, "__gc");
    lua_setmetatable(L, -2);
    lua_setfield(L, -2, "_guard");
    return 1;
}
