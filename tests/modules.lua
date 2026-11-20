-- compiled-in native modules (modules.conf) are found by plain require
local lfs, lpeg, cjson = require("lfs"), require("lpeg"), require("cjson")
assert(lfs.attributes(arg[0], "mode") == "file") -- not ".": NuttX cannot stat a relative "."
assert(lpeg.match(lpeg.P("a") ^ 1 * lpeg.P(-1), "aaa") == 4)
assert(cjson.decode(cjson.encode({a = 1})).a == 1)
