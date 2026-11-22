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
os.execute("rm -rf " .. dir)

-- the committed header module matches third_party/lua (when the tree is there)
local real = io.open("third_party/lua/lua.h", "rb")
if real then
  assert(real:read("a") == headers.files["lua.h"], "lua/luaheaders.lua is stale: run make headers")
  real:close()
end
print("ok")
