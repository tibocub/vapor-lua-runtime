/* vapor.netraw: non-blocking socket primitives over vlr_net_*; lua/net.lua (module vapor.net) builds streams on them.
   Calls return a value, or nil plus "again" (retry after waiting), "eof" (peer closed) or an error text. */
#include "lauxlib.h"
#include "lua.h"
#include "vlr_platform.h"

static int result(lua_State *L, int r)
{
    lua_pushnil(L);
    lua_pushstring(L, r == VLR_NET_AGAIN ? "again" : r == VLR_NET_EOF ? "eof" : vlr_net_error_text());
    return 2;
}

static int l_connect(lua_State *L)
{
    int h, r = vlr_net_connect(luaL_checkstring(L, 1), (int)luaL_checkinteger(L, 2), &h);

    if (r != 0) return result(L, r);
    lua_pushinteger(L, h);
    return 1;
}

static int l_resolve_start(lua_State *L)
{
    int h, r = vlr_net_resolve_start(luaL_checkstring(L, 1), &h);

    if (r != 0) return result(L, r);
    lua_pushinteger(L, h);
    return 1;
}

static int l_resolve_result(lua_State *L)
{
    char addr[64];
    int r = vlr_net_resolve_result((int)luaL_checkinteger(L, 1), addr, sizeof addr);

    if (r != 0) return result(L, r);
    lua_pushstring(L, addr);
    return 1;
}

static int l_listen(lua_State *L)
{
    int h, r = vlr_net_listen(luaL_optstring(L, 1, NULL), (int)luaL_checkinteger(L, 2), (int)luaL_optinteger(L, 3, 16), &h);

    if (r != 0) return result(L, r);
    lua_pushinteger(L, h);
    return 1;
}

static int l_udp(lua_State *L)
{
    int h, r = vlr_net_udp(luaL_optstring(L, 1, NULL), (int)luaL_optinteger(L, 2, 0), &h);

    if (r != 0) return result(L, r);
    lua_pushinteger(L, h);
    return 1;
}

static int l_accept(lua_State *L)
{
    char addr[64];
    int client, port, r = vlr_net_accept((int)luaL_checkinteger(L, 1), &client, addr, sizeof addr, &port);

    if (r != 0) return result(L, r);
    lua_pushinteger(L, client);
    lua_pushstring(L, addr);
    lua_pushinteger(L, port);
    return 3;
}

static int l_status(lua_State *L)
{
    int r = vlr_net_status((int)luaL_checkinteger(L, 1));

    if (r != 0) return result(L, r);
    lua_pushboolean(L, 1);
    return 1;
}

static int l_recv(lua_State *L)
{
    char buf[1024];
    int n = (int)luaL_optinteger(L, 2, (lua_Integer)sizeof buf), r;

    if (n > (int)sizeof buf) n = (int)sizeof buf;
    r = vlr_net_recv((int)luaL_checkinteger(L, 1), buf, n);
    if (r < 0) return result(L, r);
    lua_pushlstring(L, buf, (size_t)r);
    return 1;
}

static int l_send(lua_State *L)
{
    size_t len;
    const char *s = luaL_checklstring(L, 2, &len);
    int r = vlr_net_send((int)luaL_checkinteger(L, 1), s, len > 65536 ? 65536 : (int)len);

    if (r < 0) return result(L, r);
    lua_pushinteger(L, r);
    return 1;
}

static int l_sendto(lua_State *L)
{
    size_t len;
    const char *s = luaL_checklstring(L, 4, &len);
    int r = vlr_net_sendto((int)luaL_checkinteger(L, 1), luaL_checkstring(L, 2), (int)luaL_checkinteger(L, 3), s, len > 65507 ? 65507 : (int)len);

    if (r < 0) return result(L, r);
    lua_pushinteger(L, r);
    return 1;
}

static int l_recvfrom(lua_State *L)
{
    char buf[2048], addr[64];
    int port, r = vlr_net_recvfrom((int)luaL_checkinteger(L, 1), buf, (int)sizeof buf, addr, sizeof addr, &port);

    if (r < 0) return result(L, r);
    lua_pushlstring(L, buf, (size_t)r);
    lua_pushstring(L, addr);
    lua_pushinteger(L, port);
    return 3;
}

static int l_name(lua_State *L)
{
    char addr[64];
    int port, r = vlr_net_name((int)luaL_checkinteger(L, 1), lua_toboolean(L, 2), addr, sizeof addr, &port);

    if (r != 0) return result(L, r);
    lua_pushstring(L, addr);
    lua_pushinteger(L, port);
    return 2;
}

/* ready(handle [, writable]) -> boolean: a poll that never blocks and never yields (what a zero timeout means) */
static int l_ready(lua_State *L)
{
    int fd = (int)luaL_checkinteger(L, 1), ready = 0;

    if (lua_toboolean(L, 2)) fd |= VLR_WRITABLE;
    lua_pushboolean(L, vlr_wait(&fd, 1, &ready, 0) > 0 && ready);
    return 1;
}

static int l_close(lua_State *L)
{
    vlr_net_close((int)luaL_checkinteger(L, 1));
    lua_pushboolean(L, 1);
    return 1;
}

int luaopen_vapor_netraw(lua_State *L)
{
    static const luaL_Reg funcs[] = {
        {"connect", l_connect}, {"resolve_start", l_resolve_start}, {"resolve_result", l_resolve_result}, {"listen", l_listen}, {"udp", l_udp}, {"accept", l_accept}, {"status", l_status},
        {"recv", l_recv}, {"send", l_send}, {"sendto", l_sendto}, {"recvfrom", l_recvfrom}, {"name", l_name},
        {"ready", l_ready}, {"close", l_close}, {NULL, NULL}};

    luaL_newlib(L, funcs);
    return 1;
}
