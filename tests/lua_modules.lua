local vlr = require("vlr")
-- ./lua_modules is searched first (Lua and C modules), like node_modules
local V = _VERSION:match("%d%.%d")   -- ./lua_modules is a luarocks tree (what vpm installs): share/lua/<ver> and lib/lua/<ver>
assert(package.path:find("^%./lua_modules/share/lua/" .. V .. "/%?%.lua;%./lua_modules/share/lua/" .. V .. "/%?/init%.lua;"), package.path)
assert(package.cpath:find("^%./lua_modules/lib/lua/" .. V .. "/%?%.so;"), package.cpath)
local ok, lfs = pcall(require, "lfs")
if not ok or vlr.platform == "windows" then print("ok"); return end
local cwd = lfs.currentdir()
local dir = cwd .. "/lm-test-" .. os.time()
assert(lfs.mkdir(dir)); assert(lfs.mkdir(dir .. "/lua_modules")); assert(lfs.mkdir(dir .. "/lua_modules/share")); assert(lfs.mkdir(dir .. "/lua_modules/share/lua")); assert(lfs.mkdir(dir .. "/lua_modules/share/lua/" .. V)); assert(lfs.mkdir(dir .. "/lua_modules/share/lua/" .. V .. "/pkg"))
local function write(path, text) local f = assert(io.open(path, "wb")); f:write(text); f:close() end
write(dir .. "/lua_modules/share/lua/" .. V .. "/lmdemo.lua", "return 'from lua_modules'")
write(dir .. "/lua_modules/share/lua/" .. V .. "/pkg/init.lua", "return 'pkg init'")
assert(lfs.chdir(dir))
package.loaded.lmdemo, package.loaded.pkg = nil, nil
assert(require("lmdemo") == "from lua_modules" and require("pkg") == "pkg init")
assert(lfs.chdir(cwd))
os.remove(dir .. "/lua_modules/share/lua/" .. V .. "/lmdemo.lua"); os.remove(dir .. "/lua_modules/share/lua/" .. V .. "/pkg/init.lua")
local lm = dir .. "/lua_modules"
lfs.rmdir(lm .. "/share/lua/" .. V .. "/pkg"); lfs.rmdir(lm .. "/share/lua/" .. V); lfs.rmdir(lm .. "/share/lua"); lfs.rmdir(lm .. "/share"); lfs.rmdir(lm); lfs.rmdir(dir)
print("ok")
