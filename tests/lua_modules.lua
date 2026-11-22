-- ./lua_modules is searched first (Lua and C modules), like node_modules
assert(package.path:find("^%./lua_modules/%?%.lua;%./lua_modules/%?/init%.lua;"), package.path)
assert(package.cpath:find("^%./lua_modules/%?%.so;"), package.cpath)
local ok, lfs = pcall(require, "lfs")
if not ok or vapor.platform == "windows" then print("ok"); return end
local cwd = lfs.currentdir()
local dir = cwd .. "/lm-test-" .. os.time()
assert(lfs.mkdir(dir)); assert(lfs.mkdir(dir .. "/lua_modules")); assert(lfs.mkdir(dir .. "/lua_modules/pkg"))
local function write(path, text) local f = assert(io.open(path, "wb")); f:write(text); f:close() end
write(dir .. "/lua_modules/lmdemo.lua", "return 'from lua_modules'")
write(dir .. "/lua_modules/pkg/init.lua", "return 'pkg init'")
assert(lfs.chdir(dir))
package.loaded.lmdemo, package.loaded.pkg = nil, nil
assert(require("lmdemo") == "from lua_modules" and require("pkg") == "pkg init")
assert(lfs.chdir(cwd))
os.remove(dir .. "/lua_modules/lmdemo.lua"); os.remove(dir .. "/lua_modules/pkg/init.lua")
lfs.rmdir(dir .. "/lua_modules/pkg"); lfs.rmdir(dir .. "/lua_modules"); lfs.rmdir(dir)
print("ok")
