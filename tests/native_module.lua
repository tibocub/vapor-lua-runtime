-- end to end: write the embedded Lua headers, compile a C module with the system compiler, load it. Skipped where there is no dlopen, no way to run a compiler, or no compiler.
if not (vapor.caps.dlopen and vapor.caps.exec) or vapor.platform == "windows" then return end
if os.execute("cc --version >/dev/null 2>&1") ~= 0 then print("skipped (no C compiler)"); return end

local headers = require("vapor.luaheaders")
local fs = vapor.fs
local dir = "native-test-" .. os.time()
os.execute("mkdir -p " .. dir .. "/inc")
assert(headers.write(dir .. "/inc"))
for _, n in ipairs{ "lua.h", "luaconf.h", "lauxlib.h", "lualib.h" } do assert(io.open(dir .. "/inc/" .. n, "rb"), n):close() end

local f = assert(io.open(dir .. "/hello.c", "wb"))
f:write([[
#include "lua.h"
#include "lauxlib.h"
static int add(lua_State *L) { lua_pushinteger(L, luaL_checkinteger(L, 1) + luaL_checkinteger(L, 2)); return 1; }
int luaopen_nativehello(lua_State *L) { lua_newtable(L); lua_pushcfunction(L, add); lua_setfield(L, -2, "add"); return 1; }
]])
f:close()
local flags = vapor.platform == "macos" and "-bundle -undefined dynamic_lookup" or "-shared -fPIC"
assert(os.execute(("cc -O2 %s -I%s/inc -o %s/nativehello.so %s/hello.c"):format(flags, dir, dir, dir)) == 0, "compile")

package.cpath = dir .. "/?.so;" .. package.cpath
local m = require("nativehello")
assert(m.add(2, 3) == 5, "the compiled module runs")

-- a module written for the Lua 5.1 C API (luaL_register, luaL_reg, lua_objlen, luaL_checkint, lua_equal), as many old rocks are
local g = assert(io.open(dir .. "/old.c", "wb"))
g:write([[
#include "lua.h"
#include "lauxlib.h"
static int len(lua_State *L) { lua_pushinteger(L, (lua_Integer)lua_objlen(L, 1) + luaL_checkint(L, 2)); return 1; }
static int same(lua_State *L) { lua_pushboolean(L, lua_equal(L, 1, 2)); return 1; }
static const struct luaL_reg funcs[] = { {"len", len}, {"same", same}, {NULL, NULL} };
int luaopen_oldstyle_core(lua_State *L) { luaL_register(L, "oldstyle.core", funcs); return 1; }
]])
g:close()
assert(os.execute(("cc -O2 -Wall -Werror %s -I%s/inc -o %s/oldstyle_core.so %s/old.c"):format(flags, dir, dir, dir)) == 0, "5.1 API module compiles warning-free")
local old = assert(package.loadlib(dir .. "/oldstyle_core.so", "luaopen_oldstyle_core"))
local m51 = old()
assert(m51.len("abc", 4) == 7 and m51.same("x", "x") and not m51.same("x", "y"), "5.1 API shim works")
assert(package.loaded["oldstyle.core"] == m51 and oldstyle.core == m51, "luaL_register records the module and sets the global like 5.1")

-- a rock that carries its own copy of what 5.1 had as functions (compat layers do): must compile and still raise the error (a dlopen'd module resolves to the runtime's copy, a bundled one links its own: the runtime's is weak)
local h = assert(io.open(dir .. "/own.c", "wb"))
h:write([[
#include "lua.h"
#include "lauxlib.h"
int luaL_typerror(lua_State *L, int narg, const char *tname) { return luaL_error(L, "own typerror %d %s", narg, tname); }
static int bad(lua_State *L) { return luaL_typerror(L, 1, "thing"); }
int luaopen_ownmod(lua_State *L) { lua_pushcfunction(L, bad); return 1; }
]])
h:close()
assert(os.execute(("cc -O2 -Wall -Werror %s -I%s/inc -o %s/ownmod.so %s/own.c"):format(flags, dir, dir, dir)) == 0, "module defining luaL_typerror compiles")
local own = assert(package.loadlib(dir .. "/ownmod.so", "luaopen_ownmod"))()
local okp, perr = pcall(own)
assert(not okp and tostring(perr):find("thing expected", 1, true) or tostring(perr):find("own typerror 1 thing", 1, true), "typerror raises: " .. tostring(perr))

-- the committed header module matches third_party/lua (when the tree is there)
local real = io.open("third_party/lua/lua.h", "rb")
if real then
  assert(real:read("a") == headers.files["lua.h"], "lua/luaheaders.lua is stale: run make headers")
  real:close()
end
os.execute("rm -rf " .. dir)
print("ok")
