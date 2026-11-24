local vlr = require("vlr")
-- what a package manager asks the runtime: who are you, where, which modules are already built in
assert(type(vlr.version) == "string" and vlr.version:match("^%d+%.%d+%.%d+"))
assert(({linux = 1, windows = 1, nuttx = 1, wasm = 1, macos = 1, posix = 1})[vlr.platform], vlr.platform)
assert(type(vlr.builtin) == "table")
for name in pairs(vlr.builtin) do assert(package.preload[name], name .. " listed but not in package.preload") end
for name in pairs(package.preload) do assert(vlr.builtin[name], name .. " preloaded but not listed") end
assert(vlr.builtin.lfs and vlr.builtin.lpeg and vlr.builtin.cjson)
